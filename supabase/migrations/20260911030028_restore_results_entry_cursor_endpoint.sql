-- Restore the cursor RPC required by the deployed results screen.
-- Bound joins to a page and require show staff access or the worker service role.
create or replace function public.report_results_entry_rows_page(
  p_show_id uuid,
  p_section_id uuid default null,
  p_show_letter text default null,
  p_breed text default null,
  p_entry_ids uuid[] default null,
  p_after_entry_id uuid default null,
  p_page_size integer default 1000
)
returns table(
  entry_id uuid,
  section_id uuid,
  exhibitor_id uuid,
  exhibitor_label text,
  exhibitor_number text,
  exhibitor_showing_name text,
  exhibitor_first_name text,
  exhibitor_last_name text,
  exhibitor_address_line1 text,
  exhibitor_address_line2 text,
  exhibitor_city text,
  exhibitor_state text,
  exhibitor_zip text,
  breed text,
  breed_id uuid,
  breed_name text,
  variety text,
  variety_name text,
  fur_variety text,
  group_name text,
  class_name text,
  sex text,
  tattoo text,
  placement text,
  result_status text,
  is_shown boolean,
  is_disqualified boolean,
  disqualified_reason text,
  scratched_at timestamptz,
  judged_by_show_judge_id uuid,
  is_fur boolean,
  uses_group_awards boolean,
  uses_variety_awards boolean,
  breed_sort_order integer,
  group_sort_order integer,
  variety_sort_order integer,
  class_sort_order integer
)
language sql
stable
security definer
set search_path = ''
as $$
with page_entries as materialized (
  select e.* from public.entries e
  left join public.show_sections s on s.id = e.section_id
  where e.show_id = p_show_id
    and (
      coalesce(auth.jwt()->>'role', '') = 'service_role'
      or (auth.uid() is not null and public.user_can_manage_entries(p_show_id))
    )
    and (p_section_id is null or e.section_id = p_section_id)
    and (p_show_letter is null or p_show_letter = '' or upper(coalesce(s.letter::text, '')) = upper(p_show_letter))
    and (p_breed is null or lower(btrim(e.breed)) = lower(btrim(p_breed)))
    and (p_entry_ids is null or e.id = any(p_entry_ids))
    and (p_after_entry_id is null or e.id > p_after_entry_id)
  order by e.id
  limit greatest(1, least(coalesce(p_page_size, 1000), 1000))
)
select distinct on (e.id)
  e.id as entry_id,
  e.section_id,
  e.exhibitor_id,
  coalesce(
    nullif(ex.display_name, ''),
    nullif(ex.showing_name, ''),
    nullif(trim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
    ''
  )::text as exhibitor_label,
  coalesce(ex.exhibitor_number::text, sen.exhibitor_number::text, '')::text as exhibitor_number,
  coalesce(ex.showing_name, '')::text as exhibitor_showing_name,
  coalesce(ex.first_name, '')::text as exhibitor_first_name,
  coalesce(ex.last_name, '')::text as exhibitor_last_name,
  coalesce(ex.address_line1, '')::text as exhibitor_address_line1,
  coalesce(ex.address_line2, '')::text as exhibitor_address_line2,
  coalesce(ex.city, '')::text as exhibitor_city,
  coalesce(ex.state, '')::text as exhibitor_state,
  coalesce(ex.zip, '')::text as exhibitor_zip,
  coalesce(e.breed, '')::text as breed,
  b.id as breed_id,
  coalesce(b.name, e.breed, '')::text as breed_name,
  coalesce(e.variety, '')::text as variety,
  coalesce(v.name, e.variety, '')::text as variety_name,
  coalesce(e.fur_variety, '')::text as fur_variety,
  case when coalesce(e.is_fur, false) then 'Fur / Wool' else coalesce(vg.name, '')::text end::text as group_name,
  coalesce(e.class_name, '')::text as class_name,
  coalesce(e.sex, '')::text as sex,
  coalesce(e.tattoo, '')::text as tattoo,
  case when coalesce(e.is_fur, false) then e.fur_placement::text else e.placement::text end as placement,
  case
    when lower(coalesce(e.result_status, '')) like 'disqualified%' then e.result_status::text
    when coalesce(e.is_disqualified, false) then ('Disqualified - ' || coalesce(nullif(trim(e.disqualified_reason), ''), 'Other'))::text
    else coalesce(e.result_status, 'Shown')::text
  end as result_status,
  case
    when e.scratched_at is not null then false
    when coalesce(e.is_fur, false) then coalesce(e.is_shown, true)
    else coalesce(e.is_shown, true)
  end::boolean as is_shown,
  coalesce(e.is_disqualified, false)::boolean as is_disqualified,
  coalesce(e.disqualified_reason, '')::text as disqualified_reason,
  e.scratched_at,
  e.judged_by_show_judge_id,
  coalesce(e.is_fur, false)::boolean as is_fur,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_group_awards, false) end::boolean as uses_group_awards,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_variety_awards, false) end::boolean as uses_variety_awards,
  0::integer as breed_sort_order,
  case when coalesce(e.is_fur, false) then 9999 when vg.id is null then 9998 else coalesce(vg.sort_order, 9998)::integer end as group_sort_order,
  case when coalesce(e.is_fur, false) then 9999 else coalesce(v.sort_order, 9999)::integer end as variety_sort_order,
  case
    when coalesce(e.is_fur, false) then 1000
    when lower(coalesce(e.class_name, '')) like '%senior%' then 0
    when lower(coalesce(e.class_name, '')) like '%intermediate%' then 1
    when lower(coalesce(e.class_name, '')) like '%junior%' then 2
    else 99
  end::integer as class_sort_order
from page_entries e
left join public.exhibitors ex on ex.id = e.exhibitor_id
left join lateral (
  select sen.* from public.show_exhibitor_numbers sen
  where sen.show_id = e.show_id and sen.exhibitor_id = e.exhibitor_id
  order by sen.exhibitor_number nulls last, sen.id limit 1
) sen on true
left join lateral (
  select b.* from public.breeds b
  where b.is_active = true
    and lower(trim(b.name)) = lower(trim(e.breed))
    and lower(b.species::text) = lower(e.species::text)
  order by b.name, b.id limit 1
) b on true
left join lateral (
  select v.* from public.varieties v
  where v.breed_id = b.id and lower(trim(v.name)) = lower(trim(e.variety))
  order by v.sort_order nulls last, v.name, v.id limit 1
) v on true
left join public.variety_groups vg on vg.id = v.group_id
left join public.show_sections s on s.id = e.section_id
where e.show_id = p_show_id
  and (p_breed is null or lower(btrim(e.breed)) = lower(btrim(p_breed)))
  and (p_section_id is null or e.section_id = p_section_id)
  and (p_show_letter is null or p_show_letter = '' or upper(coalesce(s.letter::text, '')) = upper(p_show_letter))
order by e.id, breed, group_sort_order, group_name, variety_sort_order, variety, class_sort_order, sex, tattoo;
$$;

revoke all on function public.report_results_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer) from public, anon;
grant execute on function public.report_results_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer) to authenticated, service_role;
notify pgrst, 'reload schema';
