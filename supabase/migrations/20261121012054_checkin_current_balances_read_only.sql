CREATE OR REPLACE FUNCTION public.report_checkin_entries(p_show_id uuid, p_include_scratched boolean DEFAULT false, p_section_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(entry_id uuid, show_id uuid, section_id uuid, exhibitor_id uuid, exhibitor_label text, exhibitor_showing_name text, exhibitor_display_name text, exhibitor_first_name text, exhibitor_last_name text, exhibitor_arba_number text, exhibitor_address_line1 text, exhibitor_address_line2 text, exhibitor_city text, exhibitor_state text, exhibitor_zip text, exhibitor_phone text, exhibitor_email text, section_letter text, section_display_name text, section_kind text, section_sort_order integer, species text, breed text, group_name text, group_sort_order integer, variety text, variety_sort_order integer, sex text, class_name text, class_age_label text, class_sort_order integer, tattoo text, scratched_at timestamp with time zone, created_at timestamp with time zone, entry_fee_cents numeric, balance_due_all_shows numeric, balance_due_this_show numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not coalesce(public.user_can_manage_entries(p_show_id), false)
     and not coalesce(public.user_can_manage_show_settings(p_show_id), false) then
    raise exception 'You do not have access to this show' using errcode = '42501';
  end if;

  return query
with base as (
  select
    r.*,
    round(coalesce(fs.fee_per_entry, 0) * 100)::numeric as entry_fee_cents
  from public.report_entry_base_v r
  left join public.show_section_fee_settings fs
    on fs.section_id = r.section_id
  where r.show_id = p_show_id
    and (p_include_scratched = true or r.scratched_at is null)
    and (p_section_id is null or r.section_id = p_section_id)
),

-- Balances are maintained by entry/payment/credit write paths. Read the same
-- authoritative totals as Show Finances; never run the legacy balance writer
-- while fetching a report page. Aggregate submitted-cart fallbacks once, so
-- multiple carts neither duplicate entry rows nor omit part of a balance.
show_balances as materialized (
  select balance.exhibitor_id, sum(balance.balance_due_cents)::numeric as balance_due_cents
  from public.show_exhibitor_balances balance
  left join public.entry_carts cart
    on cart.id = coalesce(balance.entry_cart_id, balance.cart_id)
  where balance.show_id = p_show_id
    and (balance.source = 'entries' or (
      balance.source = 'cart' and cart.status = 'submitted'
      and not exists (
        select 1 from public.show_exhibitor_balances authoritative
        where authoritative.show_id = balance.show_id
          and authoritative.exhibitor_id = balance.exhibitor_id
          and authoritative.source = 'entries'
      )
    ))
  group by balance.exhibitor_id
)

select
  b.entry_id,
  b.show_id,
  b.section_id,
  b.exhibitor_id,
  b.exhibitor_label,
  b.exhibitor_showing_name,
  b.exhibitor_display_name,
  b.exhibitor_first_name,
  b.exhibitor_last_name,
  b.exhibitor_arba_number,
  b.exhibitor_address_line1,
  b.exhibitor_address_line2,
  b.exhibitor_city,
  b.exhibitor_state,
  b.exhibitor_zip,
  b.exhibitor_phone,
  b.exhibitor_email,
  b.section_letter,
  b.section_display_name,
  b.section_kind::text,
  b.section_sort_order,
  b.species::text,
  b.breed,
  b.group_name,
  b.group_sort_order,
  b.variety,
  b.variety_sort_order,
  b.sex,
  b.class_name,
  b.class_age_label,
  b.class_sort_order,
  b.tattoo,
  b.scratched_at,
  b.created_at,
  b.entry_fee_cents,

  -- The check-in sheet should show the same balance due as the Unpaid Exhibitor Balances report.
  (coalesce(sb.balance_due_cents, 0)::numeric / 100.0)
    as balance_due_all_shows,

  -- Keep this populated for older Flutter code paths.
  -- For combined/all-section check-in sheets, this intentionally matches all-show balance.
  (coalesce(sb.balance_due_cents, 0)::numeric / 100.0)
    as balance_due_this_show

from base b
left join show_balances sb
  on sb.exhibitor_id = b.exhibitor_id
order by
  lower(coalesce(b.exhibitor_label, '')),
  case
    when lower(coalesce(b.section_kind::text, '')) = 'open' then 1
    when lower(coalesce(b.section_kind::text, '')) = 'youth' then 2
    else 99
  end,
  coalesce(b.section_sort_order, 9999),
  coalesce(b.section_letter, ''),
  lower(coalesce(b.breed, '')),
  coalesce(b.group_sort_order, 9999),
  lower(coalesce(b.group_name, '')),
  coalesce(b.variety_sort_order, 9999),
  lower(coalesce(b.variety, '')),
  coalesce(b.class_sort_order, 9999),
  lower(coalesce(b.tattoo, ''));
end;
$function$;

revoke all on function public.report_checkin_entries(uuid, boolean, uuid) from public, anon;
grant execute on function public.report_checkin_entries(uuid, boolean, uuid) to authenticated, service_role;
comment on function public.report_checkin_entries(uuid, boolean, uuid) is
'Current check-in entries and trigger-maintained Show Finances balances. Read-only; no repeated balance refresh per page. Restricted to show staff.';
