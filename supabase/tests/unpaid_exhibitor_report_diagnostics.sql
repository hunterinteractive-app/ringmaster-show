-- Read-only production/staging diagnostic.
-- Usage: \set show_id 'uuid'; \set exhibitor_name 'Annalise Dracocardos'
\set ON_ERROR_STOP on

with target as (
  select id from public.exhibitors
  where concat_ws(' ', first_name, last_name) ilike :'exhibitor_name'
     or display_name ilike :'exhibitor_name'
     or showing_name ilike :'exhibitor_name'
)
select e.id entry_id, e.source_cart_id registration_order_id,
  e.source_cart_item_id, ss.id section_id, ss.display_name section_show_name,
  ss.kind::text division, ss.letter show_letter,
  case when ss.breed_scope = 'all' then 'all-breed' else 'specialty' end show_type,
  e.species::text, e.breed, e.tattoo,
  coalesce(f.fee_per_entry, 0) entry_fee,
  case when coalesce(e.is_fur, false) then coalesce(f.fur_fee, 0) else 0 end additional_fee,
  e.payment_status, p.id allocated_payment_id, p.status allocated_payment_status,
  coalesce(p.amount_cents, p.total_cents, 0) allocated_payment_cents,
  case
    when e.exhibitor_id is null then 'excluded: missing exhibitor'
    when e.scratched_at is not null then 'excluded: scratched'
    when coalesce(e.is_test, false) then 'excluded: test entry'
    when lower(coalesce(e.status, '')) in ('deleted','cancelled','canceled') then 'excluded: cancelled/deleted'
    when ss.id is null then 'excluded: missing/foreign section'
    else 'included'
  end inclusion_reason
from public.entries e
left join public.show_sections ss on ss.id=e.section_id and ss.show_id=e.show_id
left join public.show_section_fee_settings f on f.section_id=e.section_id
left join public.show_payments p on p.id=e.show_payment_id
where e.show_id=:'show_id'::uuid and e.exhibitor_id in (select id from target)
order by division, show_letter, tattoo, entry_id;

with classified as (
  select case
    when e.exhibitor_id is null then 'missing exhibitor'
    when e.scratched_at is not null then 'scratched'
    when coalesce(e.is_test,false) then 'test entry'
    when lower(coalesce(e.status,'')) in ('deleted','cancelled','canceled') then 'cancelled/deleted'
    when ss.id is null then 'missing/foreign section'
    else 'included'
  end reason
  from public.entries e
  left join public.show_sections ss on ss.id=e.section_id and ss.show_id=e.show_id
  where e.show_id=:'show_id'::uuid
), report as (
  select coalesce(sum(entry_count),0)::bigint entries,
    coalesce(sum(balance_due_cents),0)::bigint balance_due_cents
  from public.show_exhibitor_balances
  where show_id=:'show_id'::uuid and source='entries' and balance_due_cents > 0
)
select reason, count(*) entry_count,
  (select entries from report) report_entries,
  (select balance_due_cents from report) report_balance_due_cents
from classified group by reason order by reason;
