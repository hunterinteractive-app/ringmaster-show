-- Return closeout entry blockers as one JSON value so PostgREST's row limit
-- cannot hide issues in shows with more than 1,000 entries. Keep the entry
-- eligibility rules identical to show_results_readiness_scoped.
create or replace function public.show_results_blocking_entry_issues_scoped(
  p_show_id uuid,
  p_section_ids uuid[]
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
with eligible_rows as (
  select
    e.id as entry_id,
    e.section_id,
    coalesce(e.is_fur, false) as is_fur_key,
    nullif(
      trim(
        case
          when coalesce(e.is_fur, false) then e.fur_placement::text
          else e.placement::text
        end
      ),
      ''
    ) as placement,
    e.judged_by_show_judge_id,
    coalesce(e.tattoo, '')::text as tattoo,
    coalesce(e.breed, '')::text as breed,
    coalesce(e.variety, '')::text as variety,
    coalesce(e.class_name, '')::text as class_name,
    coalesce(e.sex, '')::text as sex,
    e.exhibitor_id
  from public.entries e
  where e.show_id = p_show_id
    and (
      e.section_id = any(coalesce(p_section_ids, array[]::uuid[]))
      or (
        p_section_ids is null
        and exists (
          select 1
          from public.show_sections enabled_section
          where enabled_section.id = e.section_id
            and enabled_section.show_id = p_show_id
            and enabled_section.is_enabled = true
        )
      )
    )
    and e.scratched_at is null
    and coalesce(e.is_shown, true) = true
    and coalesce(e.is_disqualified, false) = false
    and lower(trim(coalesce(e.result_status, 'Shown'))) not in (
      'no show',
      'unworthy of award'
    )
    and lower(trim(coalesce(e.result_status, 'Shown'))) not like 'disqualified%'
),
described_rows as (
  select
    row.entry_id,
    row.section_id,
    coalesce(
      nullif(trim(section.display_name), ''),
      initcap(section.kind::text) || ' ' || upper(section.letter)
    )::text as section_label,
    coalesce(section.sort_order, 0)::integer as section_sort_order,
    row.tattoo,
    coalesce(breed.name, row.breed, '')::text as breed_name,
    case
      when row.is_fur_key then 'Fur / Wool'
      else coalesce(variety_group.name, '')
    end::text as group_name,
    coalesce(variety.name, row.variety, '')::text as variety_name,
    row.class_name,
    row.sex,
    coalesce(
      nullif(trim(exhibitor.display_name), ''),
      nullif(trim(exhibitor.showing_name), ''),
      nullif(trim(concat_ws(' ', exhibitor.first_name, exhibitor.last_name)), ''),
      ''
    )::text as exhibitor_label,
    row.placement,
    row.judged_by_show_judge_id
  from eligible_rows row
  join public.show_sections section on section.id = row.section_id
  left join public.exhibitors exhibitor on exhibitor.id = row.exhibitor_id
  left join lateral (
    select candidate.*
    from public.breeds candidate
    where candidate.is_active = true
      and lower(trim(candidate.name)) = lower(trim(row.breed))
    order by candidate.name, candidate.id
    limit 1
  ) breed on true
  left join lateral (
    select candidate.*
    from public.varieties candidate
    where candidate.breed_id = breed.id
      and lower(trim(candidate.name)) = lower(trim(row.variety))
    order by candidate.sort_order nulls last, candidate.name, candidate.id
    limit 1
  ) variety on true
  left join public.variety_groups variety_group on variety_group.id = variety.group_id
),
issues as (
  select described.*, 'missing_placement'::text as issue_type
  from described_rows described
  where described.placement is null

  union all

  select described.*, 'missing_judge'::text as issue_type
  from described_rows described
  where described.judged_by_show_judge_id is null
),
issue_summary as (
  select
    count(*) filter (where issue_type = 'missing_placement')::integer
      as missing_placement_count,
    count(*) filter (where issue_type = 'missing_judge')::integer
      as missing_judge_count,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'issue_type', issue_type,
          'entry_id', entry_id,
          'section_id', section_id,
          'section_label', section_label,
          'tattoo', tattoo,
          'breed_name', breed_name,
          'group_name', group_name,
          'variety_name', variety_name,
          'class_name', class_name,
          'sex', sex,
          'exhibitor_label', exhibitor_label
        )
        order by
          section_sort_order,
          section_label,
          breed_name,
          group_name,
          variety_name,
          class_name,
          sex,
          tattoo,
          exhibitor_label,
          issue_type
      ),
      '[]'::jsonb
    ) as items
  from issues
)
select jsonb_build_object(
  'missing_placement_count', missing_placement_count,
  'missing_judge_count', missing_judge_count,
  'items', items
)
from issue_summary;
$function$;

comment on function public.show_results_blocking_entry_issues_scoped(uuid, uuid[]) is
  'Returns every missing placement and judge issue in one JSON response, avoiding PostgREST row truncation for large closeouts.';

revoke all on function public.show_results_blocking_entry_issues_scoped(uuid, uuid[])
  from public, anon;
grant execute on function public.show_results_blocking_entry_issues_scoped(uuid, uuid[])
  to authenticated, service_role;
