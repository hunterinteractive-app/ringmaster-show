-- Fur/Wool is a separate judging class. Earlier result saves wrote its
-- placement to entries.placement, which is reserved for the rabbit's regular
-- breed class. This is a one-time data correction, including locked shows;
-- retain the normal lock trigger for all application writes immediately after.
alter table public.entries
  disable trigger prevent_entry_changes_when_locked;

update public.entries
set
  fur_placement = coalesce(
    fur_placement,
    case
      when placement ~ '^[0-9]+$' then placement::integer
      else null
    end
  ),
  placement = null,
  updated_at = now()
where coalesce(is_fur, false) = true
  and placement is not null;

alter table public.entries
  enable trigger prevent_entry_changes_when_locked;

create or replace function public.save_results_entry(
  p_show_id uuid,
  p_entry_id uuid,
  p_placement text,
  p_result_status text,
  p_disqualified_reason text,
  p_is_shown boolean,
  p_is_disqualified boolean,
  p_judged_by_show_judge_id uuid,
  p_result_entered_by_name text,
  p_result_entered_by_phone text,
  p_awards text[],
  p_is_qr_entry_mode boolean
)
returns table(
  id uuid,
  placement integer,
  result_status text,
  judged_by_show_judge_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_section_id uuid;
  v_breed text;
  v_is_fur boolean;
  v_bob_awarded_at timestamptz;
  v_placement integer := nullif(trim(p_placement), '')::integer;
begin
  select e.section_id, e.breed, coalesce(e.is_fur, false)
    into v_section_id, v_breed, v_is_fur
  from public.entries e
  where e.id = p_entry_id
    and e.show_id = p_show_id;

  if not found then
    raise exception 'Entry not found';
  end if;

  update public.entries
  set
    placement = case when v_is_fur then placement else v_placement end,
    fur_placement = case when v_is_fur then v_placement else fur_placement end,
    result_status = p_result_status,
    disqualified_reason = p_disqualified_reason,
    is_shown = p_is_shown,
    is_disqualified = p_is_disqualified,
    judged_by_show_judge_id = p_judged_by_show_judge_id,
    result_entered_by_user_id = auth.uid(),
    result_entered_by_name = p_result_entered_by_name,
    result_entered_by_phone = p_result_entered_by_phone,
    result_entered_at = now(),
    updated_at = now()
  where public.entries.id = p_entry_id
    and public.entries.show_id = p_show_id;

  delete from public.entry_awards ea
  where ea.show_id = p_show_id
    and ea.entry_id = p_entry_id
    and not (
      upper(trim(ea.award_code)) = any(
        select upper(trim(x)) from unnest(coalesce(p_awards, array[]::text[])) as x
      )
    );

  if p_awards is not null and array_length(p_awards, 1) > 0 then
    insert into public.entry_awards (show_id, entry_id, award_code)
    select distinct p_show_id, p_entry_id, upper(trim(award_code))
    from unnest(p_awards) as award_code
    where trim(award_code) <> ''
    on conflict (entry_id, award_code) do nothing;
  end if;

  return query
  select
    e.id,
    (case when coalesce(e.is_fur, false) then e.fur_placement else e.placement end)::integer,
    e.result_status,
    e.judged_by_show_judge_id
  from public.entries e
  where e.id = p_entry_id
    and e.show_id = p_show_id;
end;
$$;

-- An unplaced Fur/Wool entry is still eligible to receive a placement. The
-- prior feed inferred "not shown" from a blank fur_placement, which limited a
-- ten-rabbit class to a single available placement.
create or replace function public.report_results_entry_rows(
  p_show_id uuid,
  p_section_id uuid default null,
  p_show_letter text default null
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
set search_path = public
as $$
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
from public.entries e
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
  and (p_section_id is null or e.section_id = p_section_id)
  and (p_show_letter is null or p_show_letter = '' or upper(coalesce(s.letter::text, '')) = upper(p_show_letter))
order by e.id, breed, group_sort_order, group_name, variety_sort_order, variety, class_sort_order, sex, tattoo;
$$;
