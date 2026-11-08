-- Server-authoritative, cumulative discounts. No production data backfill.
create schema if not exists entry_discount_private;
revoke all on schema entry_discount_private from public, anon;
grant usage on schema entry_discount_private to authenticated, service_role;
create table entry_discount_private.codes (
 id uuid primary key default gen_random_uuid(),
 show_id uuid not null references public.shows(id) on delete cascade,
 code text not null check(code=upper(btrim(code)) and code ~ '^[A-Z0-9][A-Z0-9-]{3,31}$'),
 label text not null default 'Club member discount' check(length(label) between 1 and 100),
 discount_type text not null check(discount_type in ('amount','percent','fixed_rate')),
 basis text not null check(basis in ('per_entry','overall')),
 value numeric(12,2) not null check(value>=0 and value<=100000 and (discount_type<>'percent' or value<=100)),
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 check(basis='per_entry' or discount_type<>'fixed_rate'), unique(show_id,code), unique(show_id,id)
);
create table entry_discount_private.accepted_codes (
 show_id uuid not null,
 exhibitor_id uuid not null references public.exhibitors(id) on delete cascade,
 code_id uuid not null,
 accepted_by uuid not null references auth.users(id),
 accepted_at timestamptz not null default now(),
 primary key(show_id,exhibitor_id,code_id),
 foreign key(show_id,code_id) references entry_discount_private.codes(show_id,id) on delete cascade
);
create index on entry_discount_private.accepted_codes(code_id);
create table entry_discount_private.code_attempts (
 actor uuid primary key references auth.users(id) on delete cascade,
 started_at timestamptz not null default now(), attempts integer not null default 0
);
alter table entry_discount_private.codes enable row level security;
alter table entry_discount_private.accepted_codes enable row level security;
alter table entry_discount_private.code_attempts enable row level security;
revoke all on all tables in schema entry_discount_private from public,anon,authenticated;

create function public.manage_show_discount_code(p_show_id uuid, p_id uuid default null,
 p_code text default null,p_label text default 'Club member discount',
 p_type text default 'amount',p_basis text default 'per_entry',p_value numeric default 0,
 p_enabled boolean default true,p_action text default 'list') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_code text; v_result jsonb;
begin
 if auth.uid() is null or not public.user_can_manage_show_settings(p_show_id) then
  raise exception 'You cannot manage discounts for this show.' using errcode='42501';
 end if;
 if p_action='save' then
  perform 1 from public.shows where id=p_show_id and not coalesce(is_locked,false) and finalized_at is null for update;
  if not found then raise exception 'Unlock the show before changing discounts. Finalized shows are read-only.'; end if;
  v_code:=upper(btrim(coalesce(p_code,'')));
  if v_code='' then v_code:=upper(encode(extensions.gen_random_bytes(6),'hex')); end if;
  if p_id is null then
   insert into entry_discount_private.codes(show_id,code,label,discount_type,basis,value,enabled)
   values(p_show_id,v_code,btrim(p_label),p_type,p_basis,p_value,p_enabled);
  else
   -- Keep the accepted code stable; enable/disable and future pricing can change.
   update entry_discount_private.codes set code=v_code,label=btrim(p_label),discount_type=p_type,
    basis=p_basis,value=p_value,enabled=p_enabled where id=p_id and show_id=p_show_id;
   if not found then raise exception 'Discount code not found.'; end if;
  end if;
 elsif p_action<>'list' then raise exception 'Invalid discount action.'; end if;
 select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at,c.id),'[]') into v_result
 from entry_discount_private.codes c where show_id=p_show_id;
 return v_result;
end $$;
revoke all on function public.manage_show_discount_code(uuid,uuid,text,text,text,text,numeric,boolean,text) from public,anon;
grant execute on function public.manage_show_discount_code(uuid,uuid,text,text,text,text,numeric,boolean,text) to authenticated;

-- Evaluate one alternative across the exhibitor's full show history. Cents
-- remain decimal until final rounding. Existing volume percent conventions
-- are retained; discount-code percentages always mean 0..100.
create function entry_discount_private.candidate(p_sections jsonb,p_type text,p_value numeric,
 p_basis text default 'per_entry',p_scope text default 'both',p_min integer default 0,
 p_required integer default 0,p_max integer default null,p_letters text[] default '{}')
returns integer language sql immutable set search_path='' as $$
 with items as (
  select s.ordinality as seq,n.i,(s.v->>'section_id') as section,
   (s.v->>'entries_subtotal_cents')::numeric/nullif((s.v->>'entry_count')::integer,0) as fee
  from jsonb_array_elements(p_sections) with ordinality s(v,ordinality)
  cross join lateral generate_series(1,coalesce((s.v->>'entry_count')::integer,0)) n(i)
  where (p_scope='both' or lower(s.v->>'kind')=p_scope)
   and (cardinality(p_letters)=0 or upper(btrim(s.v->>'letter'))=any(p_letters))
 ), ranked as (
  select *,count(*) over(partition by section) as section_count,
   row_number() over(order by seq,i) as total_rank,
   row_number() over(partition by section order by seq,i) as section_rank from items
 ), stats as (
  select count(*) as entries,count(distinct section) as sections,
   count(distinct section) filter(where section_count>=p_min) as qualifying from ranked
 ), eligible as (
  select r.* from ranked r cross join stats s
  where p_basis in ('per_entry','overall') or (p_min>0 and p_required>0 and (
   (p_basis='cumulative' and s.entries>=p_min and s.sections>=p_required and (p_max is null or total_rank<=p_max)) or
   (p_basis='each_show' and s.qualifying>=p_required and section_count>=p_min and (p_max is null or section_rank<=p_max))))
 )
 select greatest(0,round(case when p_basis='overall' and p_type='amount'
  then least(coalesce(sum(fee),0),p_value*100)
  else coalesce(sum(least(fee,greatest(0,case p_type when 'amount' then p_value*100
   when 'fixed_rate' then fee-p_value*100 when 'percent' then fee*p_value/100 else 0 end))),0) end))::integer from eligible;
$$;
revoke all on function entry_discount_private.candidate(jsonb,text,numeric,text,text,integer,integer,integer,text[]) from public,anon,authenticated;

create or replace function public.calculate_entry_cart_balance_internal(p_cart_id uuid)
returns setof public.show_exhibitor_balances language plpgsql security definer set search_path='' as $$
declare c public.entry_carts; f public.show_fee_settings; b public.show_exhibitor_balances;
 v_ex uuid; v_sections jsonb; v_prior integer; v_volume integer; v_special integer; v_code integer;
 v_best integer; v_discount integer; v_winner text; v_winner_code uuid; d record;
 v_reprice text:=coalesce(current_setting('ringmaster.checkout_reprice',true),'off');
 v_canadian boolean; v_total integer;
begin
 select * into c from public.entry_carts where id=p_cart_id for update;
 if not found then raise exception 'Cart not found'; end if;
 -- Pending and submitted amounts are immutable outside the existing explicit
 -- checkout-reprice path. In particular, webhook retries use the frozen quote.
 if v_reprice<>'on' and (c.status='submitted' or c.active_payment_session_id is not null
  or c.payment_status in ('pending','paid','refunded')) then
  return query select * from public.show_exhibitor_balances where entry_cart_id=p_cart_id and source='cart'; return;
 end if;
 for v_ex in select distinct exhibitor_id from public.entry_cart_items where cart_id=p_cart_id order by exhibitor_id loop
  perform pg_advisory_xact_lock(hashtextextended('entry-discount:'||c.show_id::text||':'||v_ex::text,0));
 end loop;
 select * into f from public.show_fee_settings where show_id=c.show_id;
 -- A zero-dollar preview is still editable until submitted. Paid funds remain
 -- protected by protect_cart_balance_after_payment_attempt.
 perform set_config('ringmaster.checkout_reprice','on',true);
 perform 1 from public.calculate_entry_cart_balance_without_canada_special(p_cart_id);
 for b in select * from public.show_exhibitor_balances where entry_cart_id=p_cart_id and source='cart'
  and exhibitor_id in(select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id) loop
  select coalesce(jsonb_agg(section.v order by h.created_at,h.id,section.n),'[]'),
   coalesce((select sum(h2.discount_cents) from public.show_exhibitor_balances h2
    join public.entry_carts hc on hc.id=h2.entry_cart_id
    where h2.show_id=c.show_id and h2.exhibitor_id=b.exhibitor_id and h2.source='cart' and hc.id<>p_cart_id
    and (hc.status='submitted' or exists(select 1 from public.show_payment_sessions ps where ps.id=hc.active_payment_session_id
      and ps.attempt_status in ('created','pending','processing')))),0)
   into v_sections,v_prior
  from public.show_exhibitor_balances h join public.entry_carts hc on hc.id=h.entry_cart_id
  cross join lateral jsonb_array_elements(h.section_breakdown) with ordinality section(v,n)
  where h.show_id=c.show_id and h.exhibitor_id=b.exhibitor_id and h.source='cart' and hc.id<>p_cart_id
   and (hc.status='submitted' or exists(select 1 from public.show_payment_sessions ps where ps.id=hc.active_payment_session_id
    and ps.attempt_status in ('created','pending','processing')));
  v_sections:=v_sections||coalesce(b.section_breakdown,'[]');
  v_volume:=0; v_special:=0; v_best:=0; v_winner:='none'; v_winner_code:=null;
  if coalesce(f.multi_show_discount_enabled,false) then
   v_volume:=entry_discount_private.candidate(v_sections,f.multi_show_discount_type,
    case when f.multi_show_discount_type='percent' and f.multi_show_discount_value<=1 then f.multi_show_discount_value*100 else f.multi_show_discount_value end,
    f.multi_show_discount_basis,f.multi_show_discount_scope,f.multi_show_discount_min_entries,f.multi_show_discount_required_shows,f.multi_show_discount_max_entries);
  end if;
  select public.is_canadian_exhibitor_address(state,zip) into v_canadian from public.exhibitors where id=b.exhibitor_id;
  if coalesce(f.canada_special_discount_enabled,false) and v_canadian then
   v_special:=entry_discount_private.candidate(v_sections,f.canada_special_discount_type,
    case when f.canada_special_discount_type='percent' and f.canada_special_discount_value<=1 then f.canada_special_discount_value*100 else f.canada_special_discount_value end,
    'per_entry',f.canada_special_discount_scope,0,0,null,
    array(select upper(btrim(x)) from unnest(f.canada_special_show_letters) x));
  end if;
  v_best:=greatest(v_volume,v_special);
  if v_best>0 then v_winner:=case when v_special>v_volume then 'special' else 'volume' end; end if;
  for d in select codes.* from entry_discount_private.codes codes join entry_discount_private.accepted_codes a on a.code_id=codes.id
   where a.show_id=c.show_id and a.exhibitor_id=b.exhibitor_id and codes.enabled order by codes.created_at,codes.id loop
   v_code:=entry_discount_private.candidate(v_sections,d.discount_type,d.value,d.basis);
   if v_code>v_best then v_best:=v_code; v_winner:='code'; v_winner_code:=d.id; end if;
  end loop;
  v_discount:=least(b.entries_subtotal_cents,greatest(0,v_best-v_prior));
  v_total:=greatest(0,b.subtotal_before_discount_cents-v_discount);
  update public.show_exhibitor_balances set discount_cents=v_discount,calculated_total_cents=v_total,
   balance_due_cents=greatest(0,v_total-paid_online_cents-paid_manual_cents+refunded_cents),
   payment_status=case when v_total=0 then 'paid' else 'unpaid' end,
   fee_snapshot=coalesce(fee_snapshot,'{}')||jsonb_build_object('discount_strategy','best_cumulative',
    'volume_discount_cents',v_volume,'special_discount_cents',v_special,'applied_discount',v_winner,
    'discount_code_id',v_winner_code,'discount_earned_show_cents',v_best,'discount_previously_received_cents',v_prior,
    'discount_cents',v_discount,'calculated_total_cents',v_total),updated_at=now()
   where id=b.id;
 end loop;
 perform set_config('ringmaster.checkout_reprice',v_reprice,true);
 return query select * from public.show_exhibitor_balances where entry_cart_id=p_cart_id and source='cart' order by exhibitor_id;
end $$;
revoke all on function public.calculate_entry_cart_balance_internal(uuid) from public,anon,authenticated;
grant execute on function public.calculate_entry_cart_balance_internal(uuid) to service_role;

create function public.entry_cart_discounts(p_cart_id uuid,p_code text default null,p_exhibitor_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.entry_carts; d entry_discount_private.codes; v_ex uuid; v_count integer; v_balances jsonb; v_codes jsonb;
begin
 select * into c from public.entry_carts where id=p_cart_id for update;
 if not found or auth.uid() is null or not (household_private.has_access(c.user_id)
  or public.user_can_manage_entries(c.show_id) or public.user_can_manage_show_settings(c.show_id)) then
  raise exception 'You do not have access to this cart.' using errcode='42501';
 end if;
 if p_code is not null then
  if c.status<>'active' or c.active_payment_session_id is not null or c.payment_status in ('pending','paid') then
   raise exception 'Finish or cancel the current checkout before changing discounts.';
  end if;
  insert into entry_discount_private.code_attempts(actor,attempts) values(auth.uid(),1)
  on conflict(actor) do update set attempts=case when entry_discount_private.code_attempts.started_at<now()-interval '10 minutes' then 1 else entry_discount_private.code_attempts.attempts+1 end,
   started_at=case when entry_discount_private.code_attempts.started_at<now()-interval '10 minutes' then now() else entry_discount_private.code_attempts.started_at end
  returning attempts into v_count;
  if v_count>20 then return jsonb_build_object('error','Too many code attempts. Please wait ten minutes.'); end if;
  select * into d from entry_discount_private.codes where show_id=c.show_id and code=upper(btrim(p_code)) and enabled;
  if not found then return jsonb_build_object('error','This discount code is not active for this show.'); end if;
  if p_exhibitor_id is null or not exists(select 1 from public.entry_cart_items i join public.exhibitors e on e.id=i.exhibitor_id
   where i.cart_id=p_cart_id and i.exhibitor_id=p_exhibitor_id and (household_private.has_access(e.owner_user_id)
    or public.user_can_manage_entries(c.show_id) or public.user_can_manage_show_settings(c.show_id))) then
   raise exception 'Select an exhibitor in this cart.' using errcode='42501';
  end if;
  insert into entry_discount_private.accepted_codes(show_id,exhibitor_id,code_id,accepted_by)
  values(c.show_id,p_exhibitor_id,d.id,auth.uid()) on conflict do nothing;
 end if;
 select coalesce(jsonb_agg(to_jsonb(b)),'[]') into v_balances from public.calculate_entry_cart_balance_internal(p_cart_id) b
 where b.exhibitor_id in(select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id);
 select coalesce(jsonb_agg(jsonb_build_object('exhibitor_id',a.exhibitor_id,'code',saved.code,'label',saved.label,'enabled',saved.enabled) order by saved.code),'[]') into v_codes
 from entry_discount_private.accepted_codes a join entry_discount_private.codes saved on saved.id=a.code_id
 where a.show_id=c.show_id and a.exhibitor_id in(select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id);
 return jsonb_build_object('balances',v_balances,'codes',v_codes);
end $$;
revoke all on function public.entry_cart_discounts(uuid,text,uuid) from public,anon;
grant execute on function public.entry_cart_discounts(uuid,text,uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.commit_free_entry_cart(p_cart_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cart public.entry_carts%rowtype;
  v_show public.shows%rowtype;
  v_added integer;
  v_inserted integer := 0;
  v_now timestamptz := now();
  v_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  select * into v_cart
  from public.entry_carts
  where id = p_cart_id
  for update;

  if not found then
    raise exception 'Cart not found';
  end if;
  if not v_is_service
     and not household_private.has_access(v_cart.user_id)
     and not public.user_can_manage_entries(v_cart.show_id)
     and not public.user_can_manage_show_settings(v_cart.show_id) then
    raise exception 'You do not have access to this cart'
      using errcode = '42501';
  end if;
  if v_cart.status = 'submitted' then
    return 0;
  end if;
  if v_cart.status <> 'active' then
    raise exception 'Only active carts can be submitted';
  end if;

  select * into v_show from public.shows where id = v_cart.show_id;
  if not found then
    raise exception 'Show not found';
  end if;
  if v_show.entry_close_at is not null and v_now > v_show.entry_close_at and exists (select 1 from public.entry_cart_items where cart_id=p_cart_id and not is_show_addon_carrier) then
    raise exception 'This show''s entry deadline has passed';
  end if;

  if not exists (
    select 1 from public.entry_cart_items where cart_id = p_cart_id
  ) then
    raise exception 'Cart is empty';
  end if;
  if exists (
    select 1 from public.entry_cart_items
    where cart_id = p_cart_id and exhibitor_id is null
  ) then
    raise exception 'One or more cart items are missing an exhibitor assignment';
  end if;
  if v_cart.active_payment_session_id is not null
     or v_cart.payment_status in ('pending', 'paid') then
    raise exception 'Cart has an online payment attempt in progress';
  end if;

  if exists(select 1 from public.show_fee_settings where show_id=v_cart.show_id and exhibitor_fee_enabled)
    or exists(select 1 from exhibitor_fees_private.charges where cart_id=p_cart_id) then
    perform public.calculate_entry_cart_balance_internal(p_cart_id);
  end if;

  perform show_addons_private.validate_cart(p_cart_id);
  perform public.calculate_entry_cart_balance_internal(p_cart_id);

  if exists(select 1 from public.show_exhibitor_balances where entry_cart_id=p_cart_id and source='cart' and balance_due_cents<>0 and exhibitor_id in(select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id)) then
    raise exception 'This cart has an outstanding amount. Refresh and complete payment.';
  end if;

  update public.entry_carts
  set
    selected_payment_timing = null,
    selected_payment_provider = null,
    payment_provider = 'offline',
    payment_status = 'paid',
    updated_at = v_now
  where id = p_cart_id;

  insert into public.entries (
    show_id, exhibitor_user_id, exhibitor_id, animal_id, species, tattoo,
    animal_name, breed, variety, fur_variety, sex, class_name, status,
    section_id, is_fur, payment_status, source_cart_id,
    source_cart_item_id, cart_entry_kind
  )
  select
    v_cart.show_id, v_cart.user_id, i.exhibitor_id, i.animal_id, i.species,
    i.tattoo, coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed,
    i.variety, null, i.sex, i.class_name, 'submitted', i.section_id, false,
    'paid', p_cart_id, i.id, 'entry'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id and not i.is_show_addon_carrier and not coalesce(i.is_fur, false)
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_inserted := v_inserted + v_added;

  insert into public.entries (
    show_id, exhibitor_user_id, exhibitor_id, animal_id, species, tattoo,
    animal_name, breed, variety, fur_variety, sex, class_name, status,
    section_id, is_fur, payment_status, source_cart_id,
    source_cart_item_id, cart_entry_kind
  )
  select
    v_cart.show_id, v_cart.user_id, i.exhibitor_id, i.animal_id, i.species,
    i.tattoo, coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed,
    i.variety, coalesce(nullif(btrim(i.fur_variety), ''), 'Colored'),
    null, 'Fur / Wool', 'submitted', i.section_id, true, 'paid',
    p_cart_id, i.id, 'fur'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id and not i.is_show_addon_carrier and coalesce(i.is_fur, false)
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_inserted := v_inserted + v_added;

  update public.entry_carts
  set status = 'submitted', submitted_at = coalesce(submitted_at, v_now),
      updated_at = v_now
  where id = p_cart_id;

  -- Persist the unpaid balance snapshot for pay-at-show entries.
  perform public.calculate_entry_cart_balance_internal(p_cart_id);

  return v_inserted;
end;
$function$;

revoke all on function public.commit_free_entry_cart(uuid) from public,anon;
grant execute on function public.commit_free_entry_cart(uuid) to authenticated,service_role;
