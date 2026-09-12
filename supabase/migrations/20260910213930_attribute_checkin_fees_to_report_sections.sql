-- Preserve the section on the charge itself; a payment-only carrier is never
-- evidence that a fee belongs to the show's first section.
alter table public.show_checkin_fee_charges
  add column section_id uuid references public.show_sections(id);
update public.show_checkin_fee_charges c set section_id = coalesce(
  e.section_id, nullif(r.requested_changes ->> 'section_id', '')::uuid
)
from public.show_checkin_change_requests r
left join public.entries e on e.id = r.entry_id and e.show_id = r.show_id
where c.change_request_id = r.id and c.show_id = r.show_id;

create function report_generation_private.set_checkin_charge_section()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.section_id is null then
    select coalesce(e.section_id, nullif(r.requested_changes ->> 'section_id', '')::uuid)
      into new.section_id
    from public.show_checkin_change_requests r
    left join public.entries e on e.id = r.entry_id and e.show_id = r.show_id
    where r.id = new.change_request_id and r.show_id = new.show_id and r.exhibitor_id = new.exhibitor_id;
  end if;
  if new.section_id is null or not exists (
    select 1 from public.show_sections s where s.id = new.section_id and s.show_id = new.show_id
  ) then
    raise exception 'The check-in charge must identify its show section.' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function report_generation_private.set_checkin_charge_section() from public, anon, authenticated;
create trigger set_checkin_charge_section before insert or update on public.show_checkin_fee_charges
for each row execute function report_generation_private.set_checkin_charge_section();

-- Read-only normalization of historical carrier-backed balances. Never change
-- the amounts collected, refunds, discounts, or balance due to make a report pass.
create function report_generation_private.balance_with_checkin_sections(p_balance jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_cart uuid := coalesce(p_balance ->> 'entry_cart_id', p_balance ->> 'cart_id')::uuid;
  v_base integer;
  v_carrier_section uuid;
  v_sections jsonb;
  v_fee_total integer;
  v_expected integer;
begin
  if p_balance ->> 'source' <> 'cart' then return p_balance; end if;
  select fc.carrier_base_cents, i.section_id into v_base, v_carrier_section
  from public.show_checkin_fee_carts fc join public.entry_cart_items i on i.id = fc.carrier_item_id
  where fc.cart_id = v_cart and fc.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid;
  if not found then return p_balance; end if;
  if exists (select 1 from public.show_checkin_fee_charges c where c.cart_id = v_cart
      and c.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid and c.voided_at is null and c.section_id is null) then
    raise exception 'A historical check-in fee has no section; assign its section before reporting.';
  end if;
  select coalesce(sum(c.amount_cents), 0)::integer into v_fee_total
  from public.show_checkin_fee_charges c where c.cart_id = v_cart
    and c.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid and c.voided_at is null;

  with parts as (
    select (i ->> 'section_id')::uuid section_id,
      coalesce((i ->> 'entry_count')::integer,0) - case when (i ->> 'section_id')::uuid = v_carrier_section then 1 else 0 end entry_count,
      coalesce((i ->> 'fur_count')::integer,0) fur_count,
      coalesce((i ->> 'entries_subtotal_cents')::integer,0) - case when (i ->> 'section_id')::uuid = v_carrier_section then v_base else 0 end entries_cents,
      coalesce((i ->> 'fur_subtotal_cents')::integer,0) fur_cents,
      coalesce((i ->> 'show_fee_cents')::integer,0) show_cents
    from jsonb_array_elements(coalesce(p_balance -> 'section_breakdown','[]'::jsonb)) i
    union all
    select c.section_id,0,0,0,0,c.amount_cents from public.show_checkin_fee_charges c
    where c.cart_id = v_cart and c.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid and c.voided_at is null
  ), totals as (
    select section_id,sum(entry_count) entry_count,sum(fur_count) fur_count,
      sum(entries_cents) entries_cents,sum(fur_cents) fur_cents,sum(show_cents) show_cents
    from parts group by section_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'section_id',s.id,'kind',s.kind,'letter',s.letter,'label',s.display_name,
    'entry_count',t.entry_count,'fur_count',t.fur_count,
    'entries_subtotal_cents',t.entries_cents,'fur_subtotal_cents',t.fur_cents,'show_fee_cents',t.show_cents
  ) order by s.id),'[]'::jsonb), coalesce(sum(t.entries_cents+t.fur_cents+t.show_cents),0)::integer
  into v_sections,v_expected
  from totals t join public.show_sections s on s.id = t.section_id
  where t.entry_count <> 0 or t.fur_count <> 0 or t.entries_cents <> 0 or t.fur_cents <> 0 or t.show_cents <> 0;
  if v_expected <> (p_balance ->> 'subtotal_before_discount_cents')::integer then
    raise exception 'Check-in fee section totals do not reconcile to the stored balance.';
  end if;
  return p_balance || jsonb_build_object(
    'section_breakdown',v_sections,
    'entry_count',(p_balance ->> 'entry_count')::integer - 1,
    'entries_subtotal_cents',(p_balance ->> 'entries_subtotal_cents')::integer - v_base,
    'show_fee_subtotal_cents',v_expected - ((p_balance ->> 'entries_subtotal_cents')::integer - v_base) - coalesce((p_balance ->> 'fur_subtotal_cents')::integer,0)
  );
end;
$$;
revoke all on function report_generation_private.balance_with_checkin_sections(jsonb) from public, anon, authenticated;

create or replace function public.report_show_exhibitor_balances_scoped(
  p_show_id uuid,
  p_section_ids uuid[]
)
returns setof jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_requested_ids uuid[];
  v_enabled_count integer;
  v_is_entire_show boolean;
  v_base jsonb;
  v_breakdown jsonb;
  v_scoped_breakdown jsonb;
  v_entry_count integer;
  v_fur_count integer;
  v_entries_cents integer;
  v_fur_cents integer;
  v_show_fee_cents integer;
  v_subtotal_cents integer;
  v_discount_cents integer;
  v_paid_online_cents integer;
  v_paid_manual_cents integer;
  v_refunded_cents integer;
  v_has_unallocated_discount boolean;
  v_has_unallocated_payment boolean;
  v_has_unallocated_adjustment boolean;
  v_allocation_status text;
  v_ambiguity_reasons jsonb;
begin
  if p_show_id is null then
    raise exception 'show_id is required' using errcode = '22023';
  end if;

  if p_section_ids is null or cardinality(p_section_ids) = 0 then
    raise exception 'section_ids must contain at least one section'
      using errcode = '22023';
  end if;

  if not exists (select 1 from public.shows s where s.id = p_show_id) then
    raise exception 'Show not found' using errcode = 'P0002';
  end if;

  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have access to this show'
      using errcode = '42501';
  end if;

  select array_agg(x.section_id order by x.section_id)
  into v_requested_ids
  from (select distinct unnest(p_section_ids) as section_id) x;

  if exists (
    select 1
    from unnest(v_requested_ids) requested(section_id)
    left join public.show_sections ss
      on ss.id = requested.section_id
     and ss.show_id = p_show_id
     and ss.is_enabled = true
    where ss.id is null
  ) then
    raise exception
      'Every section_id must identify an enabled section in the requested show'
      using errcode = '22023';
  end if;

  select count(*) into v_enabled_count
  from public.show_sections ss
  where ss.show_id = p_show_id and ss.is_enabled = true;

  v_is_entire_show := cardinality(v_requested_ids) = v_enabled_count;

  for v_base in
    select (
      report_generation_private.balance_with_checkin_sections(to_jsonb(b))
        - 'id'
        - 'cart_id'
        - 'created_at'
        - 'updated_at'
        - 'calculated_at'
        - 'fee_snapshot'
        - 'entry_cart_id'
        - 'latest_show_payment_id'
        - 'latest_payment_intent_id'
        - 'latest_checkout_session_id'
    ) || jsonb_build_object(
      'balance_id', b.id,
      'exhibitor_user_id', coalesce(
        to_jsonb(ex) -> 'user_id',
        to_jsonb(ex) -> 'exhibitor_user_id'
      ),
      'exhibitor_name', coalesce(
        nullif(btrim(ex.display_name), ''),
        nullif(btrim(ex.showing_name), ''),
        nullif(btrim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
        'Exhibitor'
      ),
      'showing_name', ex.showing_name,
      'display_name', ex.display_name,
      'first_name', ex.first_name,
      'last_name', ex.last_name,
      'exhibitor_type', ex.type,
      'phone', ex.phone,
      'email', ex.email,
      'address_line1', ex.address_line1,
      'address_line2', ex.address_line2,
      'city', ex.city,
      'state', ex.state,
      'zip', ex.zip,
      'arba_number', ex.arba_number
    )
    from public.show_exhibitor_balances b
    left join public.exhibitors ex on ex.id = b.exhibitor_id
    where b.show_id = p_show_id
    order by b.id
  loop
    v_breakdown := case
      when jsonb_typeof(v_base -> 'section_breakdown') = 'array'
        then v_base -> 'section_breakdown'
      else '[]'::jsonb
    end;

    if v_breakdown <> '[]'::jsonb and not exists (
      select 1 from jsonb_array_elements(v_breakdown) item
      where not ((item ->> 'section_id')::uuid = any(v_requested_ids))
    ) and coalesce((v_base ->> 'subtotal_before_discount_cents')::integer, 0) = (
      select coalesce(sum(coalesce((item ->> 'entries_subtotal_cents')::integer,0)
        + coalesce((item ->> 'fur_subtotal_cents')::integer,0)
        + coalesce((item ->> 'show_fee_cents')::integer,0)),0)
      from jsonb_array_elements(v_breakdown) item
    ) then
      return next v_base || jsonb_build_object(
        'scope_is_entire_show', v_is_entire_show,
        'payment_allocation_status', 'exact_balance_scope',
        'payment_allocation_ambiguity_reasons', '[]'::jsonb
      );
      continue;
    end if;

    if v_is_entire_show then
      return next v_base || jsonb_build_object(
        'scope_is_entire_show', true,
        'payment_allocation_status', 'exact_entire_show',
        'payment_allocation_ambiguity_reasons', '[]'::jsonb
      );
      continue;
    end if;

    select
      coalesce(jsonb_agg(item order by item ->> 'section_id'), '[]'::jsonb),
      coalesce(sum((item ->> 'entry_count')::integer), 0)::integer,
      coalesce(sum((item ->> 'fur_count')::integer), 0)::integer,
      coalesce(sum((item ->> 'entries_subtotal_cents')::integer), 0)::integer,
      coalesce(sum((item ->> 'fur_subtotal_cents')::integer), 0)::integer,
      coalesce(sum((item ->> 'show_fee_cents')::integer), 0)::integer
    into
      v_scoped_breakdown,
      v_entry_count,
      v_fur_count,
      v_entries_cents,
      v_fur_cents,
      v_show_fee_cents
    from jsonb_array_elements(v_breakdown) item
    where (item ->> 'section_id')::uuid = any(v_requested_ids);

    if v_scoped_breakdown = '[]'::jsonb then
      continue;
    end if;

    v_subtotal_cents := v_entries_cents + v_fur_cents + v_show_fee_cents;
    v_discount_cents := coalesce((v_base ->> 'discount_cents')::integer, 0);
    v_paid_online_cents := coalesce((v_base ->> 'paid_online_cents')::integer, 0);
    v_paid_manual_cents := coalesce((v_base ->> 'paid_manual_cents')::integer, 0);
    v_refunded_cents := coalesce((v_base ->> 'refunded_cents')::integer, 0);

    -- Current snapshots record these values only at balance/cart granularity.
    -- They therefore cannot be attributed to one selected section safely.
    v_has_unallocated_discount := v_discount_cents <> 0;
    v_has_unallocated_payment :=
      v_paid_online_cents <> 0 or v_paid_manual_cents <> 0
      or v_refunded_cents <> 0;
    v_has_unallocated_adjustment :=
      coalesce((v_base ->> 'subtotal_before_discount_cents')::integer, 0)
      <> coalesce((
        select sum(
          coalesce((item ->> 'entries_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'fur_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'show_fee_cents')::integer, 0)
        )::integer
        from jsonb_array_elements(v_breakdown) item
      ), 0);

    v_allocation_status := case
      when v_has_unallocated_discount
        or v_has_unallocated_payment
        or v_has_unallocated_adjustment
      then 'ambiguous'
      else 'exact'
    end;
    v_ambiguity_reasons := jsonb_strip_nulls(jsonb_build_object(
      'discount', case when v_has_unallocated_discount then
        'The stored discount applies to the whole exhibitor balance and has no section allocation.' end,
      'payment', case when v_has_unallocated_payment then
        'Financial payments for this exhibitor are recorded only at the whole-show level and cannot be allocated reliably to the selected sections.' end,
      'adjustment', case when v_has_unallocated_adjustment then
        'The stored balance contains charges or adjustments that are not represented in its section breakdown.' end
    ));

    select coalesce(jsonb_agg(
      item || jsonb_build_object(
        'discount_cents', 0,
        'paid_online_cents', 0,
        'paid_manual_cents', 0,
        'refunded_cents', 0,
        'balance_due_cents',
          coalesce((item ->> 'entries_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'fur_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'show_fee_cents')::integer, 0)
      ) order by item ->> 'section_id'
    ), '[]'::jsonb)
    into v_scoped_breakdown
    from jsonb_array_elements(v_scoped_breakdown) item;

    return next v_base || jsonb_build_object(
      'scope_is_entire_show', false,
      'section_breakdown', v_scoped_breakdown,
      'entry_count', v_entry_count,
      'fur_count', v_fur_count,
      'entries_subtotal_cents', v_entries_cents,
      'fur_subtotal_cents', v_fur_cents,
      'show_fee_subtotal_cents', v_show_fee_cents,
      'subtotal_before_discount_cents', v_subtotal_cents,
      'discount_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'calculated_total_cents', case when v_allocation_status = 'exact' then v_subtotal_cents else null end,
      'paid_online_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'paid_manual_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'refunded_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'balance_due_cents', case when v_allocation_status = 'exact' then v_subtotal_cents else null end,
      'payment_status', case when v_allocation_status = 'exact' then
        case when v_subtotal_cents <= 0 then 'paid' else 'unpaid' end
        else 'allocation_ambiguous' end,
      'payment_allocation_status', v_allocation_status,
      'payment_allocation_ambiguity_reasons', v_ambiguity_reasons
    );
  end loop;
end;
$$;

create or replace function public.report_show_exhibitor_balances_scoped(
  p_show_id uuid,
  p_section_ids uuid[],
  p_submitted_only boolean
)
returns setof jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_requested_ids uuid[];
  v_enabled_count integer;
  v_is_entire_show boolean;
  v_base jsonb;
  v_breakdown jsonb;
  v_scoped_breakdown jsonb;
  v_entry_count integer;
  v_fur_count integer;
  v_entries_cents integer;
  v_fur_cents integer;
  v_show_fee_cents integer;
  v_subtotal_cents integer;
  v_discount_cents integer;
  v_paid_online_cents integer;
  v_paid_manual_cents integer;
  v_refunded_cents integer;
  v_has_unallocated_discount boolean;
  v_has_unallocated_payment boolean;
  v_has_unallocated_adjustment boolean;
  v_allocation_status text;
  v_ambiguity_reasons jsonb;
begin
  if p_show_id is null then
    raise exception 'show_id is required' using errcode = '22023';
  end if;

  if p_section_ids is null or cardinality(p_section_ids) = 0 then
    raise exception 'section_ids must contain at least one section'
      using errcode = '22023';
  end if;

  if not exists (select 1 from public.shows s where s.id = p_show_id) then
    raise exception 'Show not found' using errcode = 'P0002';
  end if;

  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have access to this show'
      using errcode = '42501';
  end if;

  select array_agg(x.section_id order by x.section_id)
  into v_requested_ids
  from (select distinct unnest(p_section_ids) as section_id) x;

  if exists (
    select 1
    from unnest(v_requested_ids) requested(section_id)
    left join public.show_sections ss
      on ss.id = requested.section_id
     and ss.show_id = p_show_id
     and ss.is_enabled = true
    where ss.id is null
  ) then
    raise exception
      'Every section_id must identify an enabled section in the requested show'
      using errcode = '22023';
  end if;

  select count(*) into v_enabled_count
  from public.show_sections ss
  where ss.show_id = p_show_id and ss.is_enabled = true;

  v_is_entire_show := cardinality(v_requested_ids) = v_enabled_count;

  for v_base in
    select (
      report_generation_private.balance_with_checkin_sections(to_jsonb(b))
        - 'id'
        - 'cart_id'
        - 'created_at'
        - 'updated_at'
        - 'calculated_at'
        - 'fee_snapshot'
        - 'entry_cart_id'
        - 'latest_show_payment_id'
        - 'latest_payment_intent_id'
        - 'latest_checkout_session_id'
    ) || jsonb_build_object(
      'balance_id', b.id,
      'exhibitor_user_id', coalesce(
        to_jsonb(ex) -> 'user_id',
        to_jsonb(ex) -> 'exhibitor_user_id'
      ),
      'exhibitor_name', coalesce(
        nullif(btrim(ex.display_name), ''),
        nullif(btrim(ex.showing_name), ''),
        nullif(btrim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
        'Exhibitor'
      ),
      'showing_name', ex.showing_name,
      'display_name', ex.display_name,
      'first_name', ex.first_name,
      'last_name', ex.last_name,
      'exhibitor_type', ex.type,
      'phone', ex.phone,
      'email', ex.email,
      'address_line1', ex.address_line1,
      'address_line2', ex.address_line2,
      'city', ex.city,
      'state', ex.state,
      'zip', ex.zip,
      'arba_number', ex.arba_number
    )
    from public.show_exhibitor_balances b
    left join public.exhibitors ex on ex.id = b.exhibitor_id
    left join public.entry_carts c on c.id = coalesce(b.entry_cart_id, b.cart_id)
    where b.show_id = p_show_id
      and (
        b.source = 'entries'
        or not exists (
          select 1
          from public.show_exhibitor_balances authoritative
          where authoritative.show_id = b.show_id
            and authoritative.exhibitor_id = b.exhibitor_id
            and authoritative.source = 'entries'
        )
      )
      and (not p_submitted_only or c.status = 'submitted')
    order by b.id
  loop
    v_breakdown := case
      when jsonb_typeof(v_base -> 'section_breakdown') = 'array'
        then v_base -> 'section_breakdown'
      else '[]'::jsonb
    end;

    if v_breakdown <> '[]'::jsonb and not exists (
      select 1 from jsonb_array_elements(v_breakdown) item
      where not ((item ->> 'section_id')::uuid = any(v_requested_ids))
    ) and coalesce((v_base ->> 'subtotal_before_discount_cents')::integer, 0) = (
      select coalesce(sum(coalesce((item ->> 'entries_subtotal_cents')::integer,0)
        + coalesce((item ->> 'fur_subtotal_cents')::integer,0)
        + coalesce((item ->> 'show_fee_cents')::integer,0)),0)
      from jsonb_array_elements(v_breakdown) item
    ) then
      return next v_base || jsonb_build_object(
        'scope_is_entire_show', v_is_entire_show,
        'payment_allocation_status', 'exact_balance_scope',
        'payment_allocation_ambiguity_reasons', '[]'::jsonb
      );
      continue;
    end if;

    if v_is_entire_show then
      return next v_base || jsonb_build_object(
        'scope_is_entire_show', true,
        'payment_allocation_status', 'exact_entire_show',
        'payment_allocation_ambiguity_reasons', '[]'::jsonb
      );
      continue;
    end if;

    select
      coalesce(jsonb_agg(item order by item ->> 'section_id'), '[]'::jsonb),
      coalesce(sum((item ->> 'entry_count')::integer), 0)::integer,
      coalesce(sum((item ->> 'fur_count')::integer), 0)::integer,
      coalesce(sum((item ->> 'entries_subtotal_cents')::integer), 0)::integer,
      coalesce(sum((item ->> 'fur_subtotal_cents')::integer), 0)::integer,
      coalesce(sum((item ->> 'show_fee_cents')::integer), 0)::integer
    into
      v_scoped_breakdown,
      v_entry_count,
      v_fur_count,
      v_entries_cents,
      v_fur_cents,
      v_show_fee_cents
    from jsonb_array_elements(v_breakdown) item
    where (item ->> 'section_id')::uuid = any(v_requested_ids);

    if v_scoped_breakdown = '[]'::jsonb then
      continue;
    end if;

    v_subtotal_cents := v_entries_cents + v_fur_cents + v_show_fee_cents;
    v_discount_cents := coalesce((v_base ->> 'discount_cents')::integer, 0);
    v_paid_online_cents := coalesce((v_base ->> 'paid_online_cents')::integer, 0);
    v_paid_manual_cents := coalesce((v_base ->> 'paid_manual_cents')::integer, 0);
    v_refunded_cents := coalesce((v_base ->> 'refunded_cents')::integer, 0);

    v_has_unallocated_discount := v_discount_cents <> 0;
    v_has_unallocated_payment :=
      v_paid_online_cents <> 0 or v_paid_manual_cents <> 0
      or v_refunded_cents <> 0;
    v_has_unallocated_adjustment :=
      coalesce((v_base ->> 'subtotal_before_discount_cents')::integer, 0)
      <> coalesce((
        select sum(
          coalesce((item ->> 'entries_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'fur_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'show_fee_cents')::integer, 0)
        )::integer
        from jsonb_array_elements(v_breakdown) item
      ), 0);

    v_allocation_status := case
      when v_has_unallocated_discount
        or v_has_unallocated_payment
        or v_has_unallocated_adjustment
      then 'ambiguous'
      else 'exact'
    end;
    v_ambiguity_reasons := jsonb_strip_nulls(jsonb_build_object(
      'discount', case when v_has_unallocated_discount then
        'The stored discount applies to the whole exhibitor balance and has no section allocation.' end,
      'payment', case when v_has_unallocated_payment then
        'Financial payments for this exhibitor are recorded only at the whole-show level and cannot be allocated reliably to the selected sections.' end,
      'adjustment', case when v_has_unallocated_adjustment then
        'The stored balance contains charges or adjustments that are not represented in its section breakdown.' end
    ));

    select coalesce(jsonb_agg(
      item || jsonb_build_object(
        'discount_cents', 0,
        'paid_online_cents', 0,
        'paid_manual_cents', 0,
        'refunded_cents', 0,
        'balance_due_cents',
          coalesce((item ->> 'entries_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'fur_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'show_fee_cents')::integer, 0)
      ) order by item ->> 'section_id'
    ), '[]'::jsonb)
    into v_scoped_breakdown
    from jsonb_array_elements(v_scoped_breakdown) item;

    return next v_base || jsonb_build_object(
      'scope_is_entire_show', false,
      'section_breakdown', v_scoped_breakdown,
      'entry_count', v_entry_count,
      'fur_count', v_fur_count,
      'entries_subtotal_cents', v_entries_cents,
      'fur_subtotal_cents', v_fur_cents,
      'show_fee_subtotal_cents', v_show_fee_cents,
      'subtotal_before_discount_cents', v_subtotal_cents,
      'discount_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'calculated_total_cents', case when v_allocation_status = 'exact' then v_subtotal_cents else null end,
      'paid_online_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'paid_manual_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'refunded_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'balance_due_cents', case when v_allocation_status = 'exact' then v_subtotal_cents else null end,
      'payment_status', case when v_allocation_status = 'exact' then
        case when v_subtotal_cents <= 0 then 'paid' else 'unpaid' end
        else 'allocation_ambiguous' end,
      'payment_allocation_status', v_allocation_status,
      'payment_allocation_ambiguity_reasons', v_ambiguity_reasons
    );
  end loop;
end;
$$;

-- Two recalculations in one RPC share now(). Comparing calculated_at therefore
-- skipped non-default action fees. Derive the adjustment from the unchanged
-- section breakdown so repeated payment/balance updates cannot apply it twice.
create or replace function public.apply_checkin_fee_adjustments_to_balance()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_base integer;
  v_fees integer;
  v_subtotal integer;
  v_show_fees integer;
  v_total integer;
  v_due integer;
  v_status text;
begin
  if pg_trigger_depth() > 1 or new.source <> 'cart' then return new; end if;
  select carrier_base_cents into v_base from public.show_checkin_fee_carts
    where cart_id = new.entry_cart_id and exhibitor_id = new.exhibitor_id;
  if not found then return new; end if;
  select coalesce(sum(amount_cents),0)::integer into v_fees from public.show_checkin_fee_charges
    where cart_id = new.entry_cart_id and exhibitor_id = new.exhibitor_id and voided_at is null;
  select coalesce(sum(coalesce((i->>'entries_subtotal_cents')::integer,0)
    + coalesce((i->>'fur_subtotal_cents')::integer,0) + coalesce((i->>'show_fee_cents')::integer,0)),0)::integer,
    coalesce(sum(coalesce((i->>'show_fee_cents')::integer,0)),0)::integer
    into v_subtotal,v_show_fees from jsonb_array_elements(new.section_breakdown) i;
  v_subtotal := greatest(v_subtotal + v_fees - v_base,0);
  v_show_fees := greatest(v_show_fees + v_fees - v_base,0);
  v_total := greatest(v_subtotal - coalesce(new.discount_cents,0),0);
  v_due := greatest(v_total - new.paid_online_cents - new.paid_manual_cents + new.refunded_cents,0);
  v_status := case when v_due=0 then 'paid' when new.paid_online_cents+new.paid_manual_cents>0 then 'partial' else 'unpaid' end;
  if (new.subtotal_before_discount_cents,new.show_fee_subtotal_cents,new.calculated_total_cents,new.balance_due_cents,new.payment_status)
    is not distinct from (v_subtotal,v_show_fees,v_total,v_due,v_status)
    and new.fee_snapshot->>'checkin_action_fee_cents'=v_fees::text then return new; end if;
  update public.show_exhibitor_balances set
    show_fee_subtotal_cents=v_show_fees,subtotal_before_discount_cents=v_subtotal,
    calculated_total_cents=v_total,balance_due_cents=v_due,payment_status=v_status,
    fee_snapshot=coalesce(fee_snapshot,'{}'::jsonb) || jsonb_build_object(
      'checkin_action_fee_cents',v_fees,
      'checkin_action_fee_breakdown',coalesce((select jsonb_object_agg(c.action_key,c.amount_cents)
        from public.show_checkin_fee_charges c where c.cart_id=new.entry_cart_id
        and c.exhibitor_id=new.exhibitor_id and c.voided_at is null),'{}'::jsonb)),
    updated_at=now()
  where id=new.id;
  return new;
end;
$$;
revoke all on function public.apply_checkin_fee_adjustments_to_balance() from public,anon,authenticated;
