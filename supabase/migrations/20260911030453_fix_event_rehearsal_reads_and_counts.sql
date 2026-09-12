-- Optional filters in a cached SQL-function plan scanned far beyond each
-- page under national load. EXECUTE plans with the actual cursor/section/breed
-- values so the existing identity indexes bound work before hydration. Values
-- remain bound parameters, never interpolated SQL.
CREATE OR REPLACE FUNCTION public.report_results_entry_rows_page(p_show_id uuid, p_section_id uuid DEFAULT NULL::uuid, p_show_letter text DEFAULT NULL::text, p_breed text DEFAULT NULL::text, p_entry_ids uuid[] DEFAULT NULL::uuid[], p_after_entry_id uuid DEFAULT NULL::uuid, p_page_size integer DEFAULT 1000)
 RETURNS TABLE(entry_id uuid, section_id uuid, exhibitor_id uuid, exhibitor_label text, exhibitor_number text, exhibitor_showing_name text, exhibitor_first_name text, exhibitor_last_name text, exhibitor_address_line1 text, exhibitor_address_line2 text, exhibitor_city text, exhibitor_state text, exhibitor_zip text, breed text, breed_id uuid, breed_name text, variety text, variety_name text, fur_variety text, group_name text, class_name text, sex text, tattoo text, placement text, result_status text, is_shown boolean, is_disqualified boolean, disqualified_reason text, scratched_at timestamp with time zone, judged_by_show_judge_id uuid, is_fur boolean, uses_group_awards boolean, uses_variety_awards boolean, breed_sort_order integer, group_sort_order integer, variety_sort_order integer, class_sort_order integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- Preserve the access boundary restored by 20260911030028. Check once
  -- before planning the page, rather than once for every candidate entry.
  if coalesce(auth.jwt()->>'role', '') <> 'service_role'
    and (auth.uid() is null or not public.user_can_manage_entries(p_show_id)) then
    return;
  end if;
  return query execute $page$
with page_entries as materialized (
  select e.* from public.entries e
  left join public.show_sections s on s.id = e.section_id
  where e.show_id = $1
    and ($2 is null or e.section_id = $2)
    and ($3 is null or $3 = '' or upper(coalesce(s.letter::text, '')) = upper($3))
    and ($4 is null or lower(btrim(e.breed)) = lower(btrim($4)))
    and ($5 is null or e.id = any($5))
    and ($6 is null or e.id > $6)
  order by e.id
  limit greatest(1, least(coalesce($7, 1000), 1000))
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
where e.show_id = $1
  and ($4 is null or lower(btrim(e.breed)) = lower(btrim($4)))
  and ($2 is null or e.section_id = $2)
  and ($3 is null or $3 = '' or upper(coalesce(s.letter::text, '')) = upper($3))
order by e.id, breed, group_sort_order, group_name, variety_sort_order, variety, class_sort_order, sex, tattoo
$page$ using p_show_id, p_section_id, p_show_letter, p_breed, p_entry_ids, p_after_entry_id, p_page_size;
end;
$function$;

-- Force a primary-key lookup for each bounded result instead of hashing every
-- entry in the show again for every 250-row staff page.
CREATE OR REPLACE FUNCTION public.get_judging_entry_rows_page(p_show_id uuid, p_section_id uuid DEFAULT NULL::uuid, p_show_letter text DEFAULT NULL::text, p_breed text DEFAULT NULL::text, p_entry_ids uuid[] DEFAULT NULL::uuid[], p_after_entry_id uuid DEFAULT NULL::uuid, p_page_size integer DEFAULT 250)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
    and not public.user_can_enter_results(p_show_id)
    and not public.user_can_manage_entries(p_show_id)
    and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have access to this show' using errcode = '42501';
  end if;
  return query
  with results as materialized (
    select r.* from public.report_results_entry_rows_page(p_show_id, p_section_id,
      p_show_letter, p_breed, p_entry_ids, p_after_entry_id, p_page_size) r
  )
  select to_jsonb(r) || jsonb_build_object(
    'animal_id', e.animal_id, 'species', e.species, 'animal_name', e.animal_name,
    'coop_number', coalesce(coop.coop_number, ''), '_awards', coalesce(aw.codes, '[]'::jsonb)
  )
  from results r
  join lateral (
    select e.animal_id, e.species, e.animal_name, e.id, e.show_id, e.section_id
    from public.entries e
    where e.id = r.entry_id and e.show_id = p_show_id
    limit 1
  ) e on true
  join public.shows sh on sh.id = e.show_id
  left join public.show_sections ss on ss.id = e.section_id
  left join public.show_animal_coop_numbers coop on coop.show_id = e.show_id and coop.animal_id = e.animal_id
    and coop.scope = case when sh.coop_numbering_mode = 'combined' then 'all' else lower(ss.kind::text) end
  left join lateral (
    select jsonb_agg(a.award_code order by a.award_code, a.id) codes
    from public.entry_awards a where a.show_id = p_show_id and a.entry_id = e.id
  ) aw on true
  order by r.entry_id;
end;
$function$;

-- Use the same active-entry definition even when a scratch leaves is_shown
-- true or a later edit changes another entry field. Invoker security retains
-- the caller's entry RLS; workers use their existing service role.
create or replace function public.count_shown_species(
  p_show_id uuid, p_section_id uuid, p_species text
) returns bigint language sql stable security invoker set search_path = '' as $$
  select count(*) from public.entries e
  where e.show_id = p_show_id
    and e.section_id = p_section_id
    and e.species::text = p_species
    and e.is_shown = true
    and e.scratched_at is null
    and lower(btrim(coalesce(e.status, ''))) not in
      ('scratch', 'scratched', 'cancelled', 'canceled', 'deleted');
$$;
revoke all on function public.count_shown_species(uuid,uuid,text) from public, anon;
grant execute on function public.count_shown_species(uuid,uuid,text) to authenticated, service_role;
