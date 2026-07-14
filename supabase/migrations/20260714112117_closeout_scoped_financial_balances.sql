-- Read-only, exact-scope financial projection for Closeout reports.
--
-- The persisted show_exhibitor_balances row remains the financial source of
-- truth. Its section_breakdown proves entry, fur/wool, and per-section fees.
-- Existing discount and payment ledgers do not identify a section, so a
-- partial projection reports that ambiguity instead of prorating money.

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
    select to_jsonb(existing_row)
    from public.report_show_exhibitor_balances(p_show_id) existing_row
  loop
    v_breakdown := case
      when jsonb_typeof(v_base -> 'section_breakdown') = 'array'
        then v_base -> 'section_breakdown'
      else '[]'::jsonb
    end;

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

comment on function public.report_show_exhibitor_balances_scoped(uuid, uuid[])
is 'Read-only exact-section Closeout balances. Partial rows explicitly report whole-balance discount/payment allocation ambiguity rather than prorating.';

revoke all on function public.report_show_exhibitor_balances_scoped(uuid, uuid[])
  from public, anon;
grant execute on function public.report_show_exhibitor_balances_scoped(uuid, uuid[])
  to authenticated, service_role;
