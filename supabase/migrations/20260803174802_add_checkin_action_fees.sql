-- Check-in action fee settings. Amounts are stored in cents. A missing/null
-- add_entry value means use the normal fee configured for the selected show
-- section; every other action defaults to zero.
alter table public.show_checkin_settings
  add column if not exists entry_edit_fee_cents jsonb not null default '{}'::jsonb;

alter table public.show_checkin_change_requests
  add column if not exists fee_cents integer not null default 0,
  add column if not exists fee_breakdown jsonb not null default '{}'::jsonb;

alter table public.show_checkin_change_requests
  drop constraint if exists show_checkin_change_requests_fee_cents_check;
alter table public.show_checkin_change_requests
  add constraint show_checkin_change_requests_fee_cents_check
  check (fee_cents >= 0);

create or replace function public.get_checkin_action_fee_cents(
  p_show_id uuid,
  p_action text
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_action = 'add_entry'
      and (s.entry_edit_fee_cents ? 'add_entry')
      and nullif(s.entry_edit_fee_cents ->> 'add_entry', '') is not null
      then greatest(coalesce((s.entry_edit_fee_cents ->> 'add_entry')::integer, 0), 0)
    when p_action <> 'add_entry'
      then greatest(coalesce((s.entry_edit_fee_cents ->> p_action)::integer, 0), 0)
    else null
  end
  from public.show_checkin_settings s
  where s.show_id = p_show_id;
$$;

revoke all on function public.get_checkin_action_fee_cents(uuid, text) from public;
grant execute on function public.get_checkin_action_fee_cents(uuid, text)
  to service_role;

comment on column public.show_checkin_settings.entry_edit_fee_cents is
  'Cents by action key. add_entry null means use the selected section normal entry fee.';

-- Fee charges deliberately live on the existing entry-cart balance. A small
-- non-entry carrier item lets the established online and staff payment flows
-- handle a check-in-only charge without creating a separate checkout system.
alter table public.entry_cart_items
  add column if not exists is_checkin_fee_carrier boolean not null default false;

create table if not exists public.show_checkin_fee_carts (
  cart_id uuid primary key references public.entry_carts(id) on delete cascade,
  exhibitor_id uuid not null references public.exhibitors(id) on delete cascade,
  carrier_item_id uuid not null references public.entry_cart_items(id) on delete cascade,
  carrier_base_cents integer not null default 0 check (carrier_base_cents >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.show_checkin_fee_charges (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_id uuid not null references public.exhibitors(id) on delete cascade,
  cart_id uuid not null references public.entry_carts(id) on delete cascade,
  change_request_id uuid references public.show_checkin_change_requests(id) on delete cascade,
  action_key text not null,
  amount_cents integer not null,
  breakdown jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  voided_at timestamptz
);

create index if not exists show_checkin_fee_charges_cart_active_idx
  on public.show_checkin_fee_charges(cart_id, exhibitor_id)
  where voided_at is null;
create unique index if not exists show_checkin_fee_charges_request_action_uidx
  on public.show_checkin_fee_charges(change_request_id, action_key)
  where change_request_id is not null;

-- The carrier belongs to a valid section, but it is not an animal entry and
-- must not be subject to breed scope validation.
create or replace function public.enforce_cart_item_section_breed_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_cart_show_id uuid;
  v_section_show_id uuid;
  v_section_label text;
begin
  select c.show_id into v_cart_show_id from public.entry_carts c where c.id = new.cart_id;
  select ss.show_id, coalesce(nullif(btrim(ss.display_name), ''), concat(initcap(ss.kind::text), ' ', upper(ss.letter)))
    into v_section_show_id, v_section_label from public.show_sections ss where ss.id = new.section_id;
  if v_cart_show_id is null then raise exception 'The selected entry cart no longer exists.'; end if;
  if v_section_show_id is null then raise exception 'The selected show section no longer exists.'; end if;
  if v_cart_show_id is distinct from v_section_show_id then raise exception 'The selected show section belongs to a different show.'; end if;
  if coalesce(new.is_checkin_fee_carrier, false) then return new; end if;
  if not public.section_allows_breed(new.section_id, new.breed, new.species) then
    raise exception '% is not an allowed breed for %.', coalesce(nullif(btrim(new.breed), ''), 'This animal'), v_section_label;
  end if;
  return new;
end;
$$;

-- Never materialize a payment-only carrier as an entry when its cart is paid
-- or marked for payment at the show.
create or replace function public.skip_checkin_fee_carrier_entry()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.source_cart_item_id is not null and exists (
    select 1 from public.entry_cart_items i
    where i.id = new.source_cart_item_id and i.is_checkin_fee_carrier
  ) then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists aaa_skip_checkin_fee_carrier_entry on public.entries;
create trigger aaa_skip_checkin_fee_carrier_entry
before insert on public.entries
for each row execute function public.skip_checkin_fee_carrier_entry();

-- Re-apply check-in charges after the normal cart calculator has rebuilt a
-- balance. This keeps checkout, refreshes, and secretary payments on one
-- authoritative balance.
create or replace function public.apply_checkin_fee_adjustments_to_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base integer;
  v_fees integer;
  v_adjustment integer;
begin
  if pg_trigger_depth() > 1 or new.source <> 'cart'
     or new.calculated_at is not distinct from old.calculated_at then
    return new;
  end if;
  select fc.carrier_base_cents into v_base
  from public.show_checkin_fee_carts fc
  where fc.cart_id = new.entry_cart_id and fc.exhibitor_id = new.exhibitor_id;
  if not found then return new; end if;
  select coalesce(sum(c.amount_cents), 0)::integer into v_fees
  from public.show_checkin_fee_charges c
  where c.cart_id = new.entry_cart_id and c.exhibitor_id = new.exhibitor_id and c.voided_at is null;
  v_adjustment := v_fees - v_base;
  update public.show_exhibitor_balances
  set
    show_fee_subtotal_cents = greatest(show_fee_subtotal_cents + v_adjustment, 0),
    subtotal_before_discount_cents = greatest(subtotal_before_discount_cents + v_adjustment, 0),
    calculated_total_cents = greatest(calculated_total_cents + v_adjustment, 0),
    balance_due_cents = greatest(calculated_total_cents + v_adjustment - paid_online_cents - paid_manual_cents + refunded_cents, 0),
    payment_status = case
      when greatest(calculated_total_cents + v_adjustment - paid_online_cents - paid_manual_cents + refunded_cents, 0) = 0 then 'paid'
      when paid_online_cents + paid_manual_cents > 0 then 'partial'
      else 'unpaid'
    end,
    fee_snapshot = coalesce(fee_snapshot, '{}'::jsonb) || jsonb_build_object(
      'checkin_action_fee_cents', v_fees,
      'checkin_action_fee_breakdown', coalesce((
        select jsonb_object_agg(c.action_key, c.amount_cents)
        from public.show_checkin_fee_charges c
        where c.cart_id = new.entry_cart_id and c.exhibitor_id = new.exhibitor_id and c.voided_at is null
      ), '{}'::jsonb)),
    updated_at = now()
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists apply_checkin_fee_adjustments_to_balance on public.show_exhibitor_balances;
create trigger apply_checkin_fee_adjustments_to_balance
after update on public.show_exhibitor_balances
for each row execute function public.apply_checkin_fee_adjustments_to_balance();

create or replace function public.add_checkin_fee_charge(
  p_show_id uuid,
  p_exhibitor_id uuid,
  p_change_request_id uuid,
  p_action_key text,
  p_amount_cents integer,
  p_breakdown jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart public.entry_carts%rowtype;
  v_user_id uuid;
  v_section_id uuid;
  v_before integer := 0;
  v_after integer := 0;
  v_carrier_id uuid;
  v_charge_id uuid;
begin
  if p_amount_cents = 0 then return null; end if;
  select c.* into v_cart from public.entry_carts c
  where c.show_id = p_show_id and c.status = 'active' and c.payment_status not in ('paid', 'pending')
    and c.user_id in (
      select coalesce(e.exhibitor_user_id, x.owner_user_id, x.claimed_by_user_id)
      from public.exhibitors x left join public.entries e on e.exhibitor_id = x.id and e.show_id = p_show_id
      where x.id = p_exhibitor_id order by e.updated_at desc nulls last limit 1
    )
  order by c.updated_at desc limit 1 for update;
  if not found then
    select coalesce(owner_user_id, claimed_by_user_id, (select exhibitor_user_id from public.entries where show_id=p_show_id and exhibitor_id=p_exhibitor_id order by updated_at desc limit 1))
      into v_user_id from public.exhibitors where id = p_exhibitor_id;
    if v_user_id is null then raise exception 'This exhibitor does not have an account-backed cart. Please see the show secretary.'; end if;
    insert into public.entry_carts(user_id, show_id, status, payment_status, subtotal_cents, total_cents, currency)
      values(v_user_id, p_show_id, 'active', 'unpaid', 0, 0, 'usd') returning * into v_cart;
  end if;
  if not exists (select 1 from public.show_checkin_fee_carts where cart_id = v_cart.id) then
    select coalesce(sum(balance_due_cents), 0)::integer into v_before
      from public.show_exhibitor_balances where entry_cart_id = v_cart.id and exhibitor_id = p_exhibitor_id and source = 'cart';
    select id into v_section_id from public.show_sections where show_id = p_show_id order by sort_order, id limit 1;
    if v_section_id is null then raise exception 'This show has no entry section for a check-in fee.'; end if;
    insert into public.entry_cart_items(cart_id, section_id, exhibitor_id, species, tattoo, is_checkin_fee_carrier)
      values(v_cart.id, v_section_id, p_exhibitor_id, 'rabbit', 'CHECKIN-FEE', true) returning id into v_carrier_id;
    perform public.calculate_entry_cart_balance_internal(v_cart.id);
    select coalesce(sum(balance_due_cents), 0)::integer into v_after
      from public.show_exhibitor_balances where entry_cart_id = v_cart.id and exhibitor_id = p_exhibitor_id and source = 'cart';
    insert into public.show_checkin_fee_carts(cart_id, exhibitor_id, carrier_item_id, carrier_base_cents)
      values(v_cart.id, p_exhibitor_id, v_carrier_id, greatest(v_after - v_before, 0));
  end if;
  insert into public.show_checkin_fee_charges(show_id, exhibitor_id, cart_id, change_request_id, action_key, amount_cents, breakdown)
    values(p_show_id, p_exhibitor_id, v_cart.id, p_change_request_id, p_action_key, p_amount_cents, coalesce(p_breakdown, '{}'::jsonb))
    on conflict (change_request_id, action_key) where change_request_id is not null do update
      set amount_cents = excluded.amount_cents, breakdown = excluded.breakdown, voided_at = null
    returning id into v_charge_id;
  perform public.calculate_entry_cart_balance_internal(v_cart.id);
  return v_charge_id;
end;
$$;

revoke all on function public.add_checkin_fee_charge(uuid, uuid, uuid, text, integer, jsonb) from public;

create or replace function public.submit_exhibitor_checkin_change_request(
  p_session_token text, p_entry_id uuid, p_request_type text,
  p_requested_changes jsonb default '{}'::jsonb, p_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_entry public.entries%rowtype;
  v_id uuid; v_key text; v_permission text;
  v_changes jsonb := coalesce(p_requested_changes, '{}'::jsonb);
  v_automatic jsonb := '{}'::jsonb; v_approval jsonb := '{}'::jsonb; v_original jsonb := '{}'::jsonb;
  v_auto_fee integer := 0; v_approval_fee integer := 0; v_action_fee integer;
  v_breakdown jsonb := '{}'::jsonb; v_status text;
begin
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now() for update;
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501'; end if;
  if p_request_type not in ('entry_edit', 'scratch_entry') or jsonb_typeof(v_changes) <> 'object' then
    raise exception 'Invalid change request';
  end if;
  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;
  if not found or not v_settings.is_enabled then raise exception 'Check-in is not available'; end if;
  select * into v_entry from public.entries where id = p_entry_id and show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id;
  if not found then raise exception 'Entry not found'; end if;
  v_original := jsonb_build_object('ear_number', v_entry.tattoo, 'breed', v_entry.breed, 'variety', v_entry.variety,
    'class', v_entry.class_name, 'sex', v_entry.sex, 'fur_variety', v_entry.fur_variety,
    'scratch_entry', v_entry.scratched_at is not null or lower(coalesce(v_entry.status, '')) = 'scratched');
  for v_key in select jsonb_object_keys(v_changes) loop
    if v_key not in ('ear_number', 'breed', 'variety', 'class', 'sex', 'fur_variety', 'scratch_entry') then
      raise exception 'This field cannot be changed through the check-in portal';
    end if;
    if v_key = 'scratch_entry' and coalesce((v_changes ->> v_key)::boolean, false) is not true then
      raise exception 'Only scratching an entry can be requested through the check-in portal';
    end if;
    v_permission := coalesce(v_settings.entry_edit_permissions ->> v_key, 'disabled');
    if v_permission not in ('automatic', 'approval') then raise exception 'This field is not available for exhibitor changes'; end if;
    v_action_fee := coalesce(public.get_checkin_action_fee_cents(v_session.show_id, v_key), 0);
    if v_permission = 'automatic' then
      v_automatic := v_automatic || jsonb_build_object(v_key, v_changes -> v_key);
      v_auto_fee := v_auto_fee + v_action_fee;
    else
      v_approval := v_approval || jsonb_build_object(v_key, v_changes -> v_key);
      v_approval_fee := v_approval_fee + v_action_fee;
    end if;
    v_breakdown := v_breakdown || jsonb_build_object(v_key, v_action_fee);
  end loop;
  v_breakdown := v_breakdown || jsonb_build_object('automatic_fee_cents', v_auto_fee, 'approval_fee_cents', v_approval_fee);
  v_status := case when v_approval <> '{}'::jsonb then 'pending_review' when v_automatic <> '{}'::jsonb then 'approved' else 'submitted' end;
  insert into public.show_checkin_change_requests(show_id, exhibitor_id, entry_id, request_type, requested_changes, original_values,
    applied_changes, exhibitor_note, status, reviewed_at, fee_cents, fee_breakdown)
  values(v_session.show_id, v_session.exhibitor_id, p_entry_id, p_request_type, v_approval, v_original, v_automatic,
    nullif(btrim(coalesce(p_note, '')), ''), v_status, case when v_status = 'approved' then now() else null end,
    v_auto_fee + v_approval_fee, v_breakdown) returning id into v_id;
  if v_automatic <> '{}'::jsonb then
    perform public.apply_checkin_entry_changes(p_entry_id, v_automatic, 'exhibitor_portal', null, v_id);
    if v_auto_fee <> 0 then
      perform public.add_checkin_fee_charge(v_session.show_id, v_session.exhibitor_id, v_id, 'entry_edit_automatic', v_auto_fee, v_breakdown);
    end if;
  end if;
  insert into public.show_checkin_audit_events(show_id, exhibitor_id, event_type, actor_type, session_id, details)
  values(v_session.show_id, v_session.exhibitor_id, 'change_request_submitted', 'exhibitor_portal', v_session.id,
    jsonb_build_object('change_request_id', v_id, 'entry_id', p_entry_id, 'automatic_changes', v_automatic,
      'pending_review_changes', v_approval, 'fee_cents', v_auto_fee + v_approval_fee, 'fee_breakdown', v_breakdown));
  return jsonb_build_object('id', v_id, 'status', v_status, 'automatic_changes', v_automatic,
    'pending_review_changes', v_approval, 'fee_cents', v_auto_fee + v_approval_fee);
end;
$$;
revoke all on function public.submit_exhibitor_checkin_change_request(text, uuid, text, jsonb, text) from public;
grant execute on function public.submit_exhibitor_checkin_change_request(text, uuid, text, jsonb, text) to anon, authenticated, service_role;

create or replace function public.submit_exhibitor_checkin_add_entry(
  p_session_token text, p_changes jsonb, p_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.show_checkin_sessions%rowtype; cfg public.show_checkin_settings%rowtype;
  r uuid; mode text; item uuid; v_section uuid := nullif(p_changes ->> 'section_id', '')::uuid;
  v_configured_fee integer; v_normal_fee integer := 0; v_adjustment integer := 0;
  v_breakdown jsonb;
begin
  select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_session_token,'')),'sha256'),'hex') and revoked_at is null and expires_at>now() for update;
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
  select * into cfg from public.show_checkin_settings where show_id=s.show_id;
  mode := coalesce(cfg.entry_edit_permissions ->> 'add_entry','disabled');
  if mode not in ('automatic','approval') then raise exception 'Adding entries is not available through this portal'; end if;
  if v_section is null or not exists(select 1 from public.show_sections where id=v_section and show_id=s.show_id) then raise exception 'A valid show section is required'; end if;
  select round(coalesce(fee_per_entry, 0) * 100)::integer into v_normal_fee from public.show_section_fee_settings where section_id=v_section;
  v_normal_fee := coalesce(v_normal_fee, 0);
  v_configured_fee := public.get_checkin_action_fee_cents(s.show_id, 'add_entry');
  if v_configured_fee is not null then v_adjustment := v_configured_fee - v_normal_fee; end if;
  v_breakdown := jsonb_build_object('normal_entry_fee_cents', v_normal_fee, 'configured_entry_fee_cents', v_configured_fee,
    'cart_adjustment_cents', v_adjustment);
  insert into public.show_checkin_change_requests(show_id,exhibitor_id,request_type,requested_changes,exhibitor_note,status,reviewed_at,applied_changes,fee_cents,fee_breakdown)
  values(s.show_id,s.exhibitor_id,'add_entry',p_changes,nullif(btrim(coalesce(p_note,'')),''),case when mode='automatic' then 'approved' else 'pending_review' end,
    case when mode='automatic' then now() else null end,'{}',coalesce(v_configured_fee,v_normal_fee),v_breakdown) returning id into r;
  if mode='automatic' then
    item := public.apply_checkin_add_entry(s.show_id,s.exhibitor_id,p_changes,r);
    if v_adjustment <> 0 then perform public.add_checkin_fee_charge(s.show_id, s.exhibitor_id, r, 'add_entry_override', v_adjustment, v_breakdown); end if;
    update public.show_checkin_change_requests set applied_changes=jsonb_build_object('cart_item_id',item) where id=r;
  end if;
  return jsonb_build_object('id',r,'status',case when mode='automatic' then 'approved' else 'pending_review' end,
    'cart_item_id',item,'fee_cents',coalesce(v_configured_fee,v_normal_fee));
end;
$$;
revoke all on function public.submit_exhibitor_checkin_add_entry(text,jsonb,text) from public;
grant execute on function public.submit_exhibitor_checkin_add_entry(text,jsonb,text) to anon,authenticated,service_role;

create or replace function public.review_checkin_change_request(
  p_request_id uuid, p_approved boolean, p_review_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r public.show_checkin_change_requests%rowtype;
  v_status text := case when p_approved then 'approved' else 'denied' end;
  v_applied jsonb := '{}'::jsonb; v_cart_item_id uuid; v_pending_fee integer := 0;
  v_add_adjustment integer := 0;
begin
  select * into r from public.show_checkin_change_requests where id = p_request_id for update;
  if not found then raise exception 'Change request not found'; end if;
  if not public.user_can_manage_entries(r.show_id) and not public.user_can_manage_show_settings(r.show_id) then raise exception 'Permission denied' using errcode = '42501'; end if;
  if r.status not in ('submitted', 'pending_review') then raise exception 'This request has already been reviewed'; end if;
  if p_approved and r.request_type = 'add_entry' then
    v_cart_item_id := public.apply_checkin_add_entry(r.show_id, r.exhibitor_id, r.requested_changes, r.id);
    v_applied := jsonb_build_object('cart_item_id', v_cart_item_id);
    v_add_adjustment := coalesce((r.fee_breakdown ->> 'cart_adjustment_cents')::integer, 0);
    if v_add_adjustment <> 0 then
      perform public.add_checkin_fee_charge(r.show_id, r.exhibitor_id, r.id, 'add_entry_override', v_add_adjustment, r.fee_breakdown);
    end if;
  elsif p_approved and r.entry_id is not null and r.requested_changes <> '{}'::jsonb then
    perform public.apply_checkin_entry_changes(r.entry_id, r.requested_changes, 'secretary', auth.uid(), r.id);
    v_applied := r.requested_changes;
    v_pending_fee := coalesce((r.fee_breakdown ->> 'approval_fee_cents')::integer, r.fee_cents, 0);
    if v_pending_fee <> 0 then
      perform public.add_checkin_fee_charge(r.show_id, r.exhibitor_id, r.id, 'entry_edit_approval', v_pending_fee, r.fee_breakdown);
    end if;
  end if;
  update public.show_checkin_change_requests
  set status=v_status, reviewed_at=now(), reviewed_by_user_id=auth.uid(), review_note=nullif(btrim(coalesce(p_review_note,'')),''),
    applied_changes=case when p_approved then v_applied else '{}'::jsonb end, updated_at=now()
  where id=r.id;
  insert into public.show_checkin_audit_events(show_id,exhibitor_id,event_type,actor_type,actor_user_id,details)
  values(r.show_id,r.exhibitor_id,case when p_approved then 'change_request_approved' else 'change_request_denied' end,'secretary',auth.uid(),
    jsonb_build_object('change_request_id',r.id,'entry_id',r.entry_id,'request_type',r.request_type,'applied_changes',v_applied,'fee_cents',r.fee_cents));
  return jsonb_build_object('id',r.id,'status',v_status,'applied_changes',v_applied,'fee_cents',r.fee_cents);
end;
$$;
revoke all on function public.review_checkin_change_request(uuid,boolean,text) from public;
grant execute on function public.review_checkin_change_request(uuid,boolean,text) to authenticated,service_role;
