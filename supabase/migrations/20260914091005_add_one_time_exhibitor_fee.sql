-- One assessment per exhibitor number and full show. Configuration uses the
-- same show entitlement as BBOS and Wave Schedule; billing remains server-side.
alter table public.show_fee_settings
  add column exhibitor_fee_enabled boolean not null default false,
  add column exhibitor_fee_label text not null default 'Exhibitor Fee'
    check (length(btrim(exhibitor_fee_label)) between 1 and 80),
  add column exhibitor_fee_amount numeric(10,2) not null default 0
    check (exhibitor_fee_amount >= 0 and exhibitor_fee_amount <= 99999.99),
  add constraint enabled_exhibitor_fee_amount check (not exhibitor_fee_enabled or exhibitor_fee_amount > 0);

alter table public.entry_cart_items
  add column is_exhibitor_fee_carrier boolean not null default false;

create schema exhibitor_fees_private;
revoke all on schema exhibitor_fees_private from public, anon, authenticated;
grant usage on schema exhibitor_fees_private to service_role;
create table exhibitor_fees_private.charges (
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_key text not null,
  exhibitor_id uuid not null references public.exhibitors(id),
  cart_id uuid not null references public.entry_carts(id),
  section_id uuid not null references public.show_sections(id),
  label text not null,
  amount_cents integer not null check (amount_cents > 0),
  created_at timestamptz not null default now(),
  primary key(show_id, exhibitor_key),
  unique(show_id, exhibitor_id)
);
create index exhibitor_fee_charges_cart_idx on exhibitor_fees_private.charges(cart_id,exhibitor_id);
create index exhibitor_fee_charges_exhibitor_idx on exhibitor_fees_private.charges(exhibitor_id);
create index exhibitor_fee_charges_section_idx on exhibitor_fees_private.charges(section_id);
alter table exhibitor_fees_private.charges enable row level security;
revoke all on exhibitor_fees_private.charges from public,anon,authenticated;
grant select on exhibitor_fees_private.charges to service_role;

create function exhibitor_fees_private.guard_settings()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='DELETE' then
    if old.exhibitor_fee_enabled or old.exhibitor_fee_amount<>0 then
      if coalesce(auth.jwt()->>'role','') <> 'service_role' and
          not public.can_configure_best_opposite_final_award(old.show_id) then
        raise exception 'The one-time exhibitor fee is only available for selected secretaries’ shows.' using errcode='42501';
      end if;
      if exists(select 1 from public.shows where id=old.show_id and (is_locked or finalized_at is not null)) then
        raise exception 'This show is locked or finalized. Fees cannot be changed.' using errcode='42501';
      end if;
    end if;
    return old;
  end if;
  if tg_op='UPDATE' and new.show_id is distinct from old.show_id
      and (old.exhibitor_fee_enabled or new.exhibitor_fee_enabled or old.exhibitor_fee_amount<>0 or new.exhibitor_fee_amount<>0) then
    raise exception 'Exhibitor fee settings cannot be moved to another show.' using errcode='42501';
  end if;
  if tg_op='UPDATE' and (new.exhibitor_fee_enabled,new.exhibitor_fee_label,new.exhibitor_fee_amount)
      is not distinct from (old.exhibitor_fee_enabled,old.exhibitor_fee_label,old.exhibitor_fee_amount) then return new; end if;
  if tg_op='INSERT' and not new.exhibitor_fee_enabled and new.exhibitor_fee_amount=0
      and new.exhibitor_fee_label='Exhibitor Fee' then return new; end if;
  if coalesce(auth.jwt()->>'role','') <> 'service_role' and
      not public.can_configure_best_opposite_final_award(new.show_id) then
    raise exception 'The one-time exhibitor fee is only available for selected secretaries’ shows.' using errcode='42501';
  end if;
  if exists(select 1 from public.shows where id=new.show_id and (is_locked or finalized_at is not null)) then
    raise exception 'This show is locked or finalized. Fees cannot be changed.' using errcode='42501';
  end if;
  new.exhibitor_fee_label := btrim(new.exhibitor_fee_label);
  return new;
end;
$$;
create trigger guard_one_time_exhibitor_fee before insert or update or delete on public.show_fee_settings
for each row execute function exhibitor_fees_private.guard_settings();

-- Apply the recorded charge to its owning balance. Subtract the previous
-- snapshot first so Canada discounts, retries and payment updates are idempotent.
create function exhibitor_fees_private.apply_balance()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_charge exhibitor_fees_private.charges%rowtype;
  v_previous integer := coalesce((new.fee_snapshot->>'exhibitor_fee_cents')::integer,0);
  v_amount integer := 0;
  v_delta integer;
begin
  if new.source <> 'cart' then return new; end if;
  select * into v_charge from exhibitor_fees_private.charges
    where cart_id=new.entry_cart_id and exhibitor_id=new.exhibitor_id;
  if found then v_amount:=v_charge.amount_cents; end if;
  if v_amount=0 and v_previous=0 then return new; end if;
  -- Existing payment quotes and receipts must never be repriced.
  if tg_op='UPDATE' and v_previous=0 and (
      old.paid_online_cents<>0 or old.paid_manual_cents<>0 or old.refunded_cents<>0
      or exists(select 1 from public.entry_carts c where c.id=new.entry_cart_id
        and (c.active_payment_session_id is not null or c.completed_payment_session_id is not null))) then
    return new;
  end if;
  v_delta:=v_amount-v_previous;
  new.show_fee_subtotal_cents:=new.show_fee_subtotal_cents+v_delta;
  new.subtotal_before_discount_cents:=new.subtotal_before_discount_cents+v_delta;
  new.calculated_total_cents:=greatest(new.calculated_total_cents+v_delta,0);
  new.balance_due_cents:=greatest(new.calculated_total_cents-new.paid_online_cents-new.paid_manual_cents+new.refunded_cents,0);
  if new.payment_status not in ('pending','refunded','overpaid') then
    new.payment_status:=case when new.balance_due_cents=0 then 'paid'
      when new.paid_online_cents+new.paid_manual_cents>0 then 'partial' else 'unpaid' end;
  end if;
  new.section_breakdown:=coalesce((select jsonb_agg(
    s || jsonb_build_object(
      'show_fee_cents',coalesce((s->>'show_fee_cents')::integer,0)-coalesce((s->>'exhibitor_fee_cents')::integer,0)
        +case when (s->>'section_id')::uuid=v_charge.section_id then v_amount else 0 end,
      'exhibitor_fee_cents',case when (s->>'section_id')::uuid=v_charge.section_id then v_amount else 0 end,
      'exhibitor_fee_label',v_charge.label) order by ord)
    from jsonb_array_elements(new.section_breakdown) with ordinality a(s,ord)), '[]'::jsonb);
  new.fee_snapshot:=coalesce(new.fee_snapshot,'{}'::jsonb)||jsonb_build_object(
    'exhibitor_fee_cents',v_amount,'exhibitor_fee_label',v_charge.label,
    'show_fee_subtotal_cents',new.show_fee_subtotal_cents,
    'subtotal_before_discount_cents',new.subtotal_before_discount_cents,
    'calculated_total_cents',new.calculated_total_cents);
  return new;
end;
$$;
-- Runs after the existing payment-protection BEFORE trigger.
create trigger z_apply_one_time_exhibitor_fee before insert or update on public.show_exhibitor_balances
for each row execute function exhibitor_fees_private.apply_balance();

create function exhibitor_fees_private.ensure_charge(p_show uuid,p_exhibitor uuid,p_cart uuid default null,p_section uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_settings public.show_fee_settings%rowtype;
  v_ex public.exhibitors%rowtype;
  v_cart uuid:=p_cart;
  v_section uuid:=p_section;
  v_key text;
  v_user uuid;
  v_existing exhibitor_fees_private.charges%rowtype;
begin
  select * into v_settings from public.show_fee_settings where show_id=p_show and exhibitor_fee_enabled;
  if not found then return null; end if;
  select * into v_ex from public.exhibitors where id=p_exhibitor;
  if not found then raise exception 'Exhibitor not found'; end if;
  v_key:=coalesce(v_ex.exhibitor_number::text,'id:'||p_exhibitor::text);
  perform pg_advisory_xact_lock(hashtextextended('exhibitor-fee:'||p_show::text||':'||v_key,0));
  select * into v_existing from exhibitor_fees_private.charges where show_id=p_show
    and (exhibitor_key=v_key or exhibitor_id=p_exhibitor);
  if found then
    -- A preview is not a completed assessment. Move its charge into whichever
    -- cart actually checks out first, while serializing with quote creation.
    if p_cart is not null and v_existing.exhibitor_id=p_exhibitor
        and not exists(select 1 from public.entries where source_cart_id=v_existing.cart_id and exhibitor_id=p_exhibitor)
        and exists(select 1 from public.entry_carts c where c.id=v_existing.cart_id and c.status='active'
          and c.active_payment_session_id is null and c.completed_payment_session_id is null
          and c.payment_status not in ('pending','paid','refunded'))
        and not exists(select 1 from public.show_exhibitor_balances b where b.entry_cart_id=v_existing.cart_id
          and (b.paid_online_cents<>0 or b.paid_manual_cents<>0 or b.refunded_cents<>0))
        and not exists(select 1 from public.entry_cart_items where cart_id=v_existing.cart_id and is_exhibitor_fee_carrier)
        and exists(select 1 from public.entry_cart_items where cart_id=p_cart and exhibitor_id=p_exhibitor and section_id=p_section) then
      update exhibitor_fees_private.charges set cart_id=p_cart,section_id=p_section
        where show_id=p_show and exhibitor_key=v_existing.exhibitor_key;
      if v_existing.cart_id<>p_cart then
        update public.show_exhibitor_balances set updated_at=now()
          where entry_cart_id=v_existing.cart_id and exhibitor_id=p_exhibitor;
      end if;
    end if;
    return null;
  end if;
  if v_cart is not null and not exists(select 1 from public.entry_carts c
      where c.id=v_cart and c.show_id=p_show and c.active_payment_session_id is null
      and c.completed_payment_session_id is null and c.payment_status not in ('pending','paid','refunded')
      and not exists(select 1 from public.show_exhibitor_balances b where b.entry_cart_id=c.id
        and (b.paid_online_cents<>0 or b.paid_manual_cents<>0 or b.refunded_cents<>0))) then
    v_cart:=null;
  end if;
  if v_section is null then
    select e.section_id into v_section from public.entries e join public.show_sections s on s.id=e.section_id
    where e.show_id=p_show and e.exhibitor_id=p_exhibitor order by s.sort_order,s.id,e.id limit 1;
  end if;
  if not exists(select 1 from public.show_sections where id=v_section and show_id=p_show) then
    raise exception 'The exhibitor fee must belong to an entered show section.';
  end if;
  if v_cart is null then
    -- A new balance keeps already-paid entries and their receipts unchanged.
    select coalesce(v_ex.owner_user_id,v_ex.claimed_by_user_id,
      (select exhibitor_user_id from public.entries where show_id=p_show and exhibitor_id=p_exhibitor
       and exhibitor_user_id is not null order by created_at limit 1),s.owner_user_id,s.created_by)
      into v_user from public.shows s where s.id=p_show;
    insert into public.entry_carts(user_id,show_id,status,payment_status,currency)
      values(v_user,p_show,'active','unpaid',lower(v_settings.currency)) returning id into v_cart;
    insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,is_checkin_fee_carrier,is_exhibitor_fee_carrier)
      values(v_cart,v_section,p_exhibitor,'rabbit','EXHIBITOR-FEE',true,true);
  end if;
  insert into exhibitor_fees_private.charges(show_id,exhibitor_key,exhibitor_id,cart_id,section_id,label,amount_cents)
    values(p_show,v_key,p_exhibitor,v_cart,v_section,v_settings.exhibitor_fee_label,round(v_settings.exhibitor_fee_amount*100)::integer);
  return v_cart;
end;
$$;

create function exhibitor_fees_private.prepare_cart(p_cart uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_show uuid; r record; v_other uuid;
begin
  select c.show_id into v_show from public.entry_carts c join public.show_fee_settings f on f.show_id=c.show_id
    where c.id=p_cart and f.exhibitor_fee_enabled;
  if not found then return; end if;
  for r in select i.exhibitor_id,(array_agg(i.section_id order by s.sort_order,s.id))[1] section_id
    from public.entry_cart_items i join public.show_sections s on s.id=i.section_id
    where i.cart_id=p_cart and not i.is_checkin_fee_carrier
    group by i.exhibitor_id order by i.exhibitor_id
  loop
    v_other:=exhibitor_fees_private.ensure_charge(v_show,r.exhibitor_id,p_cart,r.section_id);
    if v_other is not null and v_other<>p_cart then
      perform public.calculate_entry_cart_balance_internal(v_other);
    end if;
  end loop;
end;
$$;

create function exhibitor_fees_private.sync_settings()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record; v_cart uuid;
begin
  if not new.exhibitor_fee_enabled then return new; end if;
  if tg_op='UPDATE' and old.exhibitor_fee_enabled then return new; end if;
  for r in select distinct exhibitor_id from public.entries where show_id=new.show_id and exhibitor_id is not null order by exhibitor_id loop
    v_cart:=exhibitor_fees_private.ensure_charge(new.show_id,r.exhibitor_id);
    if v_cart is not null then perform public.calculate_entry_cart_balance_internal(v_cart); end if;
  end loop;
  return new;
end;
$$;
create trigger sync_one_time_exhibitor_fee after insert or update of exhibitor_fee_enabled,exhibitor_fee_label,exhibitor_fee_amount
on public.show_fee_settings for each row execute function exhibitor_fees_private.sync_settings();

create function exhibitor_fees_private.entered_exhibitors()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record; v_cart uuid;
begin
  for r in select distinct e.show_id,e.exhibitor_id,e.source_cart_id,e.section_id
    from new_entries e join public.show_fee_settings f on f.show_id=e.show_id
    where f.exhibitor_fee_enabled and e.exhibitor_id is not null order by e.show_id,e.exhibitor_id
  loop
    v_cart:=exhibitor_fees_private.ensure_charge(r.show_id,r.exhibitor_id,r.source_cart_id,r.section_id);
    if v_cart is not null then perform public.calculate_entry_cart_balance_internal(v_cart); end if;
  end loop;
  return null;
end;
$$;
create trigger assess_entered_exhibitor_fee after insert on public.entries
referencing new table as new_entries for each statement execute function exhibitor_fees_private.entered_exhibitors();

-- Clients cannot create fee-only rows or rewrite the private ledger.
create function exhibitor_fees_private.guard_carrier()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='DELETE' then
    if old.is_exhibitor_fee_carrier and current_user not in ('postgres','service_role','supabase_admin') then
      raise exception 'Exhibitor fee rows are managed by the show billing system.' using errcode='42501';
    end if;
    return old;
  end if;
  if (new.is_exhibitor_fee_carrier or (tg_op='UPDATE' and old.is_exhibitor_fee_carrier))
      and current_user not in ('postgres','service_role','supabase_admin') then
    raise exception 'Exhibitor fee rows are managed by the show billing system.' using errcode='42501';
  end if;
  return new;
end;
$$;
create trigger guard_exhibitor_fee_carrier before insert or update or delete on public.entry_cart_items
for each row execute function exhibitor_fees_private.guard_carrier();

revoke all on all functions in schema exhibitor_fees_private from public,anon,authenticated;

-- Preserve the existing entry and discount calculations; zero only fee-carrier rows.
CREATE OR REPLACE FUNCTION public.calculate_entry_cart_balance_without_canada_special(p_cart_id uuid)
 RETURNS SETOF show_exhibitor_balances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_show_id uuid;
  v_cart_user_id uuid;

  v_currency text := 'usd';

  v_discount_enabled boolean := false;
  v_discount_type text := 'amount';
  v_discount_value numeric := 0;

  v_discount_basis text := 'each_show';
  v_discount_scope text := 'both';
  v_discount_min_entries integer := 0;
  v_discount_max_entries integer := null;
  v_discount_required_shows integer := 0;
begin
  select
    c.show_id,
    c.user_id
  into
    v_show_id,
    v_cart_user_id
  from public.entry_carts c
  where c.id = p_cart_id;

  if v_show_id is null then
    raise exception 'Cart % not found', p_cart_id;
  end if;

  select
    lower(coalesce(sfs.currency, 'usd')),
    coalesce(sfs.multi_show_discount_enabled, false),
    lower(coalesce(sfs.multi_show_discount_type, 'amount')),
    coalesce(sfs.multi_show_discount_value, 0),
    lower(coalesce(sfs.multi_show_discount_basis, 'each_show')),
    lower(coalesce(sfs.multi_show_discount_scope, 'both')),
    coalesce(sfs.multi_show_discount_min_entries, 0),
    sfs.multi_show_discount_max_entries,
    coalesce(sfs.multi_show_discount_required_shows, 0)
  into
    v_currency,
    v_discount_enabled,
    v_discount_type,
    v_discount_value,
    v_discount_basis,
    v_discount_scope,
    v_discount_min_entries,
    v_discount_max_entries,
    v_discount_required_shows
  from public.show_fee_settings sfs
  where sfs.show_id = v_show_id;

  -- Apply safe defaults when the show has no fee-settings row.
  if not found then
    v_currency := 'usd';
    v_discount_enabled := false;
    v_discount_type := 'amount';
    v_discount_value := 0;
    v_discount_basis := 'each_show';
    v_discount_scope := 'both';
    v_discount_min_entries := 0;
    v_discount_max_entries := null;
    v_discount_required_shows := 0;
  end if;

  if length(v_currency) <> 3 then
    v_currency := 'usd';
  end if;

  if v_discount_type not in ('fixed_rate', 'amount', 'percent') then
    v_discount_type := 'amount';
  end if;

  if v_discount_basis not in ('each_show', 'cumulative') then
    v_discount_basis := 'each_show';
  end if;

  if v_discount_scope not in ('both', 'open', 'youth') then
    v_discount_scope := 'both';
  end if;

  v_discount_value := greatest(coalesce(v_discount_value, 0), 0);
  v_discount_min_entries :=
    greatest(coalesce(v_discount_min_entries, 0), 0);
  v_discount_required_shows :=
    greatest(coalesce(v_discount_required_shows, 0), 0);

  if v_discount_max_entries is not null then
    v_discount_max_entries :=
      greatest(v_discount_max_entries, 0);
  end if;

  if not exists (
    select 1
    from public.entry_cart_items eci
    where eci.cart_id = p_cart_id
  ) then
    raise exception 'Cart % is empty', p_cart_id;
  end if;

  if exists (
    select 1
    from public.entry_cart_items eci
    where eci.cart_id = p_cart_id
      and eci.exhibitor_id is null
  ) then
    raise exception
      'Cart % has one or more items missing exhibitor_id',
      p_cart_id;
  end if;

  perform exhibitor_fees_private.prepare_cart(p_cart_id);

  return query
  with cart_items as (
    select
      eci.id,
      eci.cart_id,
      eci.section_id,
      eci.animal_id,
      eci.exhibitor_id,
      coalesce(eci.is_fur, false) as is_fur,
      eci.created_at,
      coalesce(eci.is_exhibitor_fee_carrier, false) as is_exhibitor_fee_carrier
    from public.entry_cart_items eci
    where eci.cart_id = p_cart_id
      and eci.exhibitor_id is not null
  ),

  priced_items as (
    select
      ci.*,
      ss.show_id,
      lower(ss.kind::text) as section_kind,
      ss.letter as section_letter,
      coalesce(
        nullif(btrim(ss.display_name), ''),
        concat(
          initcap(ss.kind::text),
          ' ',
          coalesce(ss.letter, '')
        )
      ) as section_label,
      ss.sort_order as section_sort_order,

      (case when ci.is_exhibitor_fee_carrier then 0 else coalesce(sffs.fee_per_entry, 0) end)::numeric
        as fee_per_entry,

      (case when ci.is_exhibitor_fee_carrier then 0 else coalesce(sffs.fee_per_show, 0) end)::numeric
        as fee_per_show,

      (case when ci.is_exhibitor_fee_carrier then 0 else coalesce(sffs.fur_fee, 0) end)::numeric
        as fur_fee,

      case
        when ci.is_exhibitor_fee_carrier then false
        when v_discount_scope = 'both' then true
        when lower(ss.kind::text) = v_discount_scope then true
        else false
      end as eligible_for_discount

    from cart_items ci

    join public.show_sections ss
      on ss.id = ci.section_id

    left join public.show_section_fee_settings sffs
      on sffs.section_id = ci.section_id

    where ss.show_id = v_show_id
  ),

  /*
   * All section totals remain included in the balance, regardless of whether
   * the section is eligible for the selected discount scope.
   */
  section_counts as (
    select
      pi.exhibitor_id,
      pi.section_id,

      min(pi.section_kind) as section_kind,
      min(pi.section_letter) as section_letter,
      min(pi.section_label) as section_label,

      min(
        coalesce(pi.section_sort_order, 999999)
      ) as section_sort_order,

      count(*) filter (where not pi.is_fur and not pi.is_exhibitor_fee_carrier)::integer as entry_count,

      count(*) filter (
        where pi.is_fur
      )::integer as fur_count,

      round(
        sum(case when not pi.is_fur then pi.fee_per_entry else 0 end) * 100
      )::integer as entries_subtotal_cents,

      round(
        sum(
          case
            when pi.is_fur then pi.fur_fee
            else 0
          end
        ) * 100
      )::integer as fur_subtotal_cents,

      round(
        max(pi.fee_per_show) * 100
      )::integer as show_fee_cents

    from priced_items pi

    group by
      pi.exhibitor_id,
      pi.section_id
  ),

  /*
   * Counts only sections permitted by multi_show_discount_scope.
   */
  eligible_section_counts as (
    select
      pi.exhibitor_id,
      pi.section_id,
      count(*) filter (where not pi.is_fur and not pi.is_exhibitor_fee_carrier)::integer as eligible_entry_count

    from priced_items pi

    where pi.eligible_for_discount = true
      and not pi.is_fur and not pi.is_exhibitor_fee_carrier

    group by
      pi.exhibitor_id,
      pi.section_id
  ),

  /*
   * Determines whether each exhibitor qualifies.
   *
   * each_show:
   *   At least the configured number of sections must each contain the
   *   configured minimum number of entries.
   *
   * cumulative:
   *   The exhibitor must enter at least the configured number of sections
   *   and have at least the configured total number of eligible entries.
   */
  exhibitor_discount_stats as (
    select
      pi.exhibitor_id,

      count(*) filter (
        where pi.eligible_for_discount
          and not pi.is_fur and not pi.is_exhibitor_fee_carrier
      )::integer as eligible_entry_count,

      count(
        distinct pi.section_id
      ) filter (
        where pi.eligible_for_discount
      )::integer as eligible_show_count,

      coalesce((
        select count(*)::integer
        from eligible_section_counts esc
        where esc.exhibitor_id = pi.exhibitor_id
          and esc.eligible_entry_count >= v_discount_min_entries
      ), 0) as qualifying_show_count

    from priced_items pi

    group by pi.exhibitor_id
  ),

  /*
   * Add deterministic numbering so an optional maximum can be applied.
   *
   * For cumulative discounts, maximum entries is applied across all eligible
   * entries for the exhibitor.
   *
   * For each-show discounts, maximum entries is applied separately to each
   * qualifying show section, matching the cart-screen calculation.
   */
  eligible_ranked_items as (
    select
      pi.*,

      row_number() over (
        partition by pi.exhibitor_id
        order by
          pi.created_at,
          pi.id
      ) as cumulative_entry_number,

      row_number() over (
        partition by
          pi.exhibitor_id,
          pi.section_id
        order by
          pi.created_at,
          pi.id
      ) as section_entry_number

    from priced_items pi

    where pi.eligible_for_discount = true
      and not pi.is_fur and not pi.is_exhibitor_fee_carrier
  ),

  discount_eligible_items as (
    select eri.*

    from eligible_ranked_items eri

    join exhibitor_discount_stats eds
      on eds.exhibitor_id = eri.exhibitor_id

    join eligible_section_counts esc
      on esc.exhibitor_id = eri.exhibitor_id
     and esc.section_id = eri.section_id

    where
      v_discount_enabled = true

      and v_discount_min_entries > 0

      and v_discount_required_shows > 0

      and (
        (
          v_discount_basis = 'cumulative'

          and eds.eligible_show_count
            >= v_discount_required_shows

          and eds.eligible_entry_count
            >= v_discount_min_entries

          and (
            v_discount_max_entries is null
            or eri.cumulative_entry_number
              <= v_discount_max_entries
          )
        )

        or

        (
          v_discount_basis = 'each_show'

          and eds.qualifying_show_count
            >= v_discount_required_shows

          and esc.eligible_entry_count
            >= v_discount_min_entries

          and (
            v_discount_max_entries is null
            or eri.section_entry_number
              <= v_discount_max_entries
          )
        )
      )
  ),

  /*
   * Calculate the discount one item at a time so differing section entry
   * fees are handled correctly.
   */
  exhibitor_discount_totals as (
    select
      dei.exhibitor_id,

      count(*)::integer as qualifying_entry_count,

      count(
        distinct dei.section_id
      )::integer as discounted_show_count,

      round(
        sum(
          least(
            dei.fee_per_entry,

            greatest(
              case
                when v_discount_type = 'fixed_rate' then
                  dei.fee_per_entry - v_discount_value

                when v_discount_type = 'percent' then
                  dei.fee_per_entry
                  *
                  case
                    when v_discount_value <= 1 then
                      v_discount_value
                    else
                      v_discount_value / 100.0
                  end

                when v_discount_type = 'amount' then
                  v_discount_value

                else 0
              end,
              0
            )
          )
        ) * 100
      )::integer as discount_cents

    from discount_eligible_items dei

    group by dei.exhibitor_id
  ),

  exhibitor_totals_raw as (
    select
      pi.exhibitor_id,

      count(*) filter (where not pi.is_fur and not pi.is_exhibitor_fee_carrier)::integer as entry_count,

      count(*) filter (
        where pi.is_fur
      )::integer as fur_count,

      round(
        sum(case when not pi.is_fur then pi.fee_per_entry else 0 end) * 100
      )::integer as entries_subtotal_cents,

      round(
        sum(
          case
            when pi.is_fur then pi.fur_fee
            else 0
          end
        ) * 100
      )::integer as fur_subtotal_cents,

      coalesce((
        select sum(sc.show_fee_cents)::integer
        from section_counts sc
        where sc.exhibitor_id = pi.exhibitor_id
      ), 0) as show_fee_subtotal_cents,

      coalesce(
        eds.eligible_entry_count,
        0
      )::integer as eligible_entry_count,

      coalesce(
        eds.eligible_show_count,
        0
      )::integer as eligible_show_count,

      coalesce(
        eds.qualifying_show_count,
        0
      )::integer as qualifying_show_count,

      coalesce(
        edt.qualifying_entry_count,
        0
      )::integer as qualifying_entry_count,

      coalesce(
        edt.discounted_show_count,
        0
      )::integer as discounted_show_count,

      greatest(
        coalesce(edt.discount_cents, 0),
        0
      )::integer as discount_cents

    from priced_items pi

    left join exhibitor_discount_stats eds
      on eds.exhibitor_id = pi.exhibitor_id

    left join exhibitor_discount_totals edt
      on edt.exhibitor_id = pi.exhibitor_id

    group by
      pi.exhibitor_id,
      eds.eligible_entry_count,
      eds.eligible_show_count,
      eds.qualifying_show_count,
      edt.qualifying_entry_count,
      edt.discounted_show_count,
      edt.discount_cents
  ),

  exhibitor_totals as (
    select
      etr.*,

      (
        etr.entries_subtotal_cents
        + etr.fur_subtotal_cents
        + etr.show_fee_subtotal_cents
      )::integer as subtotal_before_discount_cents

    from exhibitor_totals_raw etr
  ),

  final_rows as (
    select
      et.exhibitor_id,

      coalesce(
        ex.owner_user_id,
        v_cart_user_id
      ) as exhibitor_user_id,

      et.entry_count,
      et.fur_count,
      et.entries_subtotal_cents,
      et.fur_subtotal_cents,
      et.show_fee_subtotal_cents,
      et.subtotal_before_discount_cents,

      least(
        greatest(et.discount_cents, 0),
        et.entries_subtotal_cents
      )::integer as discount_cents,

      greatest(
        et.subtotal_before_discount_cents
        - least(
            greatest(et.discount_cents, 0),
            et.entries_subtotal_cents
          ),
        0
      )::integer as calculated_total_cents,

      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'section_id', sc.section_id,
            'kind', sc.section_kind,
            'letter', sc.section_letter,
            'label', sc.section_label,
            'entry_count', sc.entry_count,
            'fur_count', sc.fur_count,
            'entries_subtotal_cents',
              sc.entries_subtotal_cents,
            'fur_subtotal_cents',
              sc.fur_subtotal_cents,
            'show_fee_cents',
              sc.show_fee_cents,
            'discount_scope_eligible',
              case
                when v_discount_scope = 'both' then true
                when lower(sc.section_kind) = v_discount_scope then true
                else false
              end
          )
          order by
            sc.section_sort_order,
            sc.section_kind,
            sc.section_letter
        )
        from section_counts sc
        where sc.exhibitor_id = et.exhibitor_id
      ), '[]'::jsonb) as section_breakdown,

      jsonb_build_object(
        'source', 'cart',
        'cart_id', p_cart_id,
        'show_id', v_show_id,
        'currency', v_currency,

        'discount_enabled', v_discount_enabled,
        'discount_type', v_discount_type,
        'discount_value', v_discount_value,
        'discount_basis', v_discount_basis,
        'discount_scope', v_discount_scope,
        'discount_min_entries', v_discount_min_entries,
        'discount_max_entries', v_discount_max_entries,
        'discount_required_shows', v_discount_required_shows,

        'eligible_entry_count',
          et.eligible_entry_count,
        'eligible_show_count',
          et.eligible_show_count,
        'qualifying_show_count',
          et.qualifying_show_count,
        'qualifying_entry_count',
          et.qualifying_entry_count,
        'discounted_show_count',
          et.discounted_show_count,

        'entry_count', et.entry_count,
        'fur_count', et.fur_count,

        'entries_subtotal_cents',
          et.entries_subtotal_cents,

        'fur_subtotal_cents',
          et.fur_subtotal_cents,

        'show_fee_subtotal_cents',
          et.show_fee_subtotal_cents,

        'subtotal_before_discount_cents',
          et.subtotal_before_discount_cents,

        'discount_cents',
          least(
            greatest(et.discount_cents, 0),
            et.entries_subtotal_cents
          ),

        'calculated_total_cents',
          greatest(
            et.subtotal_before_discount_cents
            - least(
                greatest(et.discount_cents, 0),
                et.entries_subtotal_cents
              ),
            0
          )
      ) as fee_snapshot

    from exhibitor_totals et

    left join public.exhibitors ex
      on ex.id = et.exhibitor_id
  ),

  upserted as (
    insert into public.show_exhibitor_balances (
      show_id,
      exhibitor_id,
      exhibitor_user_id,
      entry_cart_id,
      cart_id,
      currency,
      entry_count,
      fur_count,
      entries_subtotal_cents,
      fur_subtotal_cents,
      show_fee_subtotal_cents,
      subtotal_before_discount_cents,
      discount_cents,
      calculated_total_cents,
      paid_online_cents,
      paid_manual_cents,
      refunded_cents,
      balance_due_cents,
      payment_status,
      latest_show_payment_id,
      latest_checkout_session_id,
      latest_payment_intent_id,
      section_breakdown,
      fee_snapshot,
      source,
      calculated_at,
      updated_at
    )
    select
      v_show_id,
      fr.exhibitor_id,
      fr.exhibitor_user_id,
      p_cart_id,
      p_cart_id,
      v_currency,
      fr.entry_count,
      fr.fur_count,
      fr.entries_subtotal_cents,
      fr.fur_subtotal_cents,
      fr.show_fee_subtotal_cents,
      fr.subtotal_before_discount_cents,
      fr.discount_cents,
      fr.calculated_total_cents,
      0,
      0,
      0,
      fr.calculated_total_cents,

      case
        when fr.calculated_total_cents <= 0 then 'paid'
        else 'unpaid'
      end,

      null,
      null,
      null,
      fr.section_breakdown,
      fr.fee_snapshot,
      'cart',
      now(),
      now()

    from final_rows fr

    on conflict (entry_cart_id, exhibitor_id)
      where (
        entry_cart_id is not null
        and exhibitor_id is not null
        and source = 'cart'
      )

    do update set
      show_id = excluded.show_id,
      exhibitor_user_id = excluded.exhibitor_user_id,
      cart_id = excluded.cart_id,
      currency = excluded.currency,
      entry_count = excluded.entry_count,
      fur_count = excluded.fur_count,
      entries_subtotal_cents =
        excluded.entries_subtotal_cents,
      fur_subtotal_cents =
        excluded.fur_subtotal_cents,
      show_fee_subtotal_cents =
        excluded.show_fee_subtotal_cents,
      subtotal_before_discount_cents =
        excluded.subtotal_before_discount_cents,
      discount_cents =
        excluded.discount_cents,
      calculated_total_cents =
        excluded.calculated_total_cents,
      paid_online_cents = 0,
      paid_manual_cents = 0,
      refunded_cents = 0,
      balance_due_cents =
        excluded.calculated_total_cents,

      payment_status = case
        when excluded.calculated_total_cents <= 0 then 'paid'
        else 'unpaid'
      end,

      latest_show_payment_id = null,
      latest_checkout_session_id = null,
      latest_payment_intent_id = null,
      section_breakdown =
        excluded.section_breakdown,
      fee_snapshot =
        excluded.fee_snapshot,
      source = 'cart',
      calculated_at = now(),
      updated_at = now()

    returning public.show_exhibitor_balances.*
  )

  select *
  from upserted
  order by exhibitor_id;
end;
$function$;

-- Payment receipts itemize the custom fee without double-counting show fees.
do $migration$
declare d text;
begin
  d:=pg_get_functiondef('public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)'::regprocedure);
  if strpos(d, '(''per_show_fee'', ''Per-show fees'', b.show_fee_subtotal_cents)')=0 then
    raise exception 'Expected payment quote line items were not found';
  end if;
  d:=replace(d,'(''per_show_fee'', ''Per-show fees'', b.show_fee_subtotal_cents)',
    '(''per_show_fee'', ''Per-show fees'', b.show_fee_subtotal_cents-coalesce((b.fee_snapshot->>''exhibitor_fee_cents'')::integer,0)),
    (''per_show_fee'', coalesce(b.fee_snapshot->>''exhibitor_fee_label'',''Exhibitor Fee''), coalesce((b.fee_snapshot->>''exhibitor_fee_cents'')::integer,0))');
  execute d;
end;
$migration$;

create function exhibitor_fees_private.cart_fees(p_cart_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_cart public.entry_carts%rowtype; v_result jsonb;
begin
  select * into v_cart from public.entry_carts where id=p_cart_id;
  if not found or (coalesce(auth.jwt()->>'role','')<>'service_role'
    and not household_private.has_access(v_cart.user_id)
    and not public.user_can_manage_entries(v_cart.show_id)
    and not public.user_can_manage_show_settings(v_cart.show_id)) then
    raise exception 'You do not have access to this cart' using errcode='42501';
  end if;
  if not exists(select 1 from public.entry_cart_items where cart_id=p_cart_id) then return '[]'::jsonb; end if;
  if not exists(select 1 from public.show_fee_settings where show_id=v_cart.show_id and exhibitor_fee_enabled)
    and not exists(select 1 from exhibitor_fees_private.charges where cart_id=p_cart_id) then return '[]'::jsonb; end if;
  perform public.calculate_entry_cart_balance_internal(p_cart_id);
  select coalesce(jsonb_agg(jsonb_build_object('exhibitor_id',b.exhibitor_id,
    'label',b.fee_snapshot->>'exhibitor_fee_label','amount_cents',(b.fee_snapshot->>'exhibitor_fee_cents')::integer)
    order by b.exhibitor_id),'[]'::jsonb) into v_result
    from public.show_exhibitor_balances b where b.entry_cart_id=p_cart_id and b.source='cart'
      and coalesce((b.fee_snapshot->>'exhibitor_fee_cents')::integer,0)>0;
  return v_result;
end;
$$;
grant usage on schema exhibitor_fees_private to authenticated;
revoke all on function exhibitor_fees_private.cart_fees(uuid) from public,anon;
grant execute on function exhibitor_fees_private.cart_fees(uuid) to authenticated,service_role;
create function public.get_cart_exhibitor_fees(p_cart_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select exhibitor_fees_private.cart_fees(p_cart_id);
$$;
revoke all on function public.get_cart_exhibitor_fees(uuid) from public,anon;
grant execute on function public.get_cart_exhibitor_fees(uuid) to authenticated,service_role;

-- Removing a wholly unsubmitted exhibitor from a draft releases its assessment.
create function exhibitor_fees_private.release_draft_charge()
returns trigger language plpgsql security definer set search_path='' as $$
declare c exhibitor_fees_private.charges%rowtype;
begin
  select * into c from exhibitor_fees_private.charges where cart_id=old.cart_id and exhibitor_id=old.exhibitor_id;
  if not found then return old; end if;
  perform pg_advisory_xact_lock(hashtextextended('exhibitor-fee:'||c.show_id::text||':'||c.exhibitor_key,0));
  if not exists(select 1 from public.entry_cart_items where cart_id=old.cart_id and exhibitor_id=old.exhibitor_id)
    and not exists(select 1 from public.entries where show_id=c.show_id and exhibitor_id=c.exhibitor_id)
    and exists(select 1 from public.entry_carts where id=c.cart_id and status='active'
      and active_payment_session_id is null and completed_payment_session_id is null and payment_status not in ('paid','pending','refunded'))
    and not exists(select 1 from public.show_exhibitor_balances where entry_cart_id=c.cart_id
      and (paid_online_cents<>0 or paid_manual_cents<>0 or refunded_cents<>0)) then
    delete from exhibitor_fees_private.charges where show_id=c.show_id and exhibitor_key=c.exhibitor_key;
    delete from public.show_exhibitor_balances where entry_cart_id=c.cart_id and exhibitor_id=c.exhibitor_id;
  end if;
  return old;
end;
$$;
revoke all on function exhibitor_fees_private.release_draft_charge() from public,anon,authenticated;
create trigger release_unsubmitted_exhibitor_fee after delete on public.entry_cart_items
for each row execute function exhibitor_fees_private.release_draft_charge();

-- Day-of checkout must also assess and persist this fee before submitting.
do $migration$
declare d text; needle text := E'  update public.entry_carts\n  set\n    selected_payment_timing';
begin
  d:=pg_get_functiondef('public.commit_entry_cart_day_of(uuid)'::regprocedure);
  if strpos(d,needle)=0 then raise exception 'Expected day-of checkout statement was not found'; end if;
  d:=replace(d,needle,E'  if exists(select 1 from public.show_fee_settings where show_id=v_cart.show_id and exhibitor_fee_enabled)\n    or exists(select 1 from exhibitor_fees_private.charges where cart_id=p_cart_id) then\n    perform public.calculate_entry_cart_balance_internal(p_cart_id);\n  end if;\n\n'||needle);
  execute d;
end;
$migration$;

-- Reassigning an existing entry to a newly entered exhibitor also assesses it.
create function exhibitor_fees_private.updated_exhibitors()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record; v_cart uuid;
begin
  for r in select distinct e.show_id,e.exhibitor_id,e.source_cart_id,e.section_id
    from new_entries e join old_entries o on o.id=e.id
    join public.show_fee_settings f on f.show_id=e.show_id
    where f.exhibitor_fee_enabled and e.exhibitor_id is not null
      and (e.show_id,e.exhibitor_id) is distinct from (o.show_id,o.exhibitor_id)
    order by e.show_id,e.exhibitor_id
  loop
    v_cart:=exhibitor_fees_private.ensure_charge(r.show_id,r.exhibitor_id,r.source_cart_id,r.section_id);
    if v_cart is not null then perform public.calculate_entry_cart_balance_internal(v_cart); end if;
  end loop;
  return null;
end;
$$;
revoke all on function exhibitor_fees_private.updated_exhibitors() from public,anon,authenticated;
create trigger assess_reassigned_exhibitor_fee after update on public.entries
referencing new table as new_entries old table as old_entries
for each statement execute function exhibitor_fees_private.updated_exhibitors();
