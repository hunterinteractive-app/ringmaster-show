-- Keep dashboard polling cheap. Readiness is fetched separately by the client
-- when the scope changes and immediately before finalization.
create or replace function public.get_closeout_dashboard_scoped(
  p_show_id uuid,
  p_scope_key text,
  p_section_ids uuid[],
  p_artifact_limit integer default 100,
  p_artifact_offset integer default 0,
  p_report_name public.report_type default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select public.get_closeout_dashboard_scoped_without_readiness_details(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );
$function$;

revoke all on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) to authenticated, service_role;

-- `show_results_readiness_scoped` used the report loader for every dashboard
-- request. That loader expands every entry into a report-shaped row, performs
-- unrelated exhibitor-number lookups, and sorts the full result set. Preserve
-- the readiness rules while reading only columns the validator actually needs.
create or replace function public.show_results_readiness_scoped(
  p_show_id uuid,
  p_section_ids uuid[]
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
with show_settings as (
  select lower(trim(coalesce(s.final_award_mode, 'four_six_bis')))
    as final_award_mode
  from public.shows s
  where s.id = p_show_id
),
eligible_rows as (
  select
    e.id as entry_id,
    e.section_id,
    case
      when lower(trim(coalesce(e.sex, ''))) in ('boar', 'sow') then 'cavy'
      else 'rabbit'
    end as species_key,
    coalesce(e.is_shown, true) as is_shown,
    coalesce(e.is_disqualified, false) as is_disqualified,
    coalesce(e.is_fur, false) as is_fur_key,
    e.scratched_at,
    lower(trim(coalesce(e.result_status, 'Shown'))) as result_status_key,
    nullif(trim(case when coalesce(e.is_fur, false)
      then e.fur_placement::text else e.placement::text end), '') as placement,
    e.judged_by_show_judge_id,
    lower(trim(coalesce(nullif(e.breed, ''), ''))) as breed_key,
    lower(trim(coalesce(nullif(e.variety, ''), ''))) as variety_key,
    lower(trim(coalesce(e.class_name, ''))) as class_name_key,
    lower(trim(coalesce(e.sex, ''))) as sex_key
  from public.entries e
  where e.show_id = p_show_id
    and e.section_id = any(coalesce(p_section_ids, array[]::uuid[]))
),
required_results as (
  select *
  from eligible_rows
  where scratched_at is null
    and is_shown = true
    and is_disqualified = false
    and result_status_key not in ('no show', 'unworthy of award')
    and result_status_key not like 'disqualified%'
),
required_entries as (
  select distinct entry_id, section_id, species_key
  from required_results
),
missing_placement as (
  select count(distinct entry_id)::int as total
  from required_results
  where placement is null
),
missing_judge as (
  select count(distinct entry_id)::int as total
  from required_results
  where judged_by_show_judge_id is null
),
duplicate_placement_groups as (
  select count(*)::int as total
  from (
    select section_id, breed_key, variety_key, class_name_key, sex_key,
      is_fur_key, placement
    from required_results
    where placement is not null
    group by section_id, breed_key, variety_key, class_name_key, sex_key,
      is_fur_key, placement
    having count(distinct entry_id) > 1
  ) duplicates
),
applicable_final_award_sections as (
  select distinct re.section_id, re.species_key,
    coalesce(nullif(trim(sec.display_name), ''),
      initcap(sec.kind::text) || ' ' || upper(sec.letter)) as section_label,
    sec.sort_order
  from required_entries re
  join public.show_sections sec on sec.id = re.section_id
  cross join show_settings ss
  where ss.final_award_mode = 'bis_1ris_2ris'
),
normalized_final_awards as (
  select distinct re.entry_id, re.section_id, re.species_key,
    case
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g')
        in ('bis', 'bestinshow', 'bestinshowrabbit') then 'BIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g')
        in ('1ris', '1stris', 'firstris', '1streserveinshow', 'firstreserveinshow') then '1RIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g')
        in ('2ris', '2ndris', 'secondris', '2ndreserveinshow', 'secondreserveinshow') then '2RIS'
      else null
    end as award_kind
  from required_entries re
  join public.entry_awards ea on ea.entry_id = re.entry_id
),
final_awards as (
  select nfa.*
  from normalized_final_awards nfa
  cross join show_settings ss
  where ss.final_award_mode = 'bis_1ris_2ris'
    and nfa.award_kind is not null
),
required_final_award_types as (
  select *
  from (values
    ('BIS', 'Best in Show', 1, true),
    ('1RIS', 'First Reserve in Show', 2, true),
    ('2RIS', 'Second Reserve in Show', 3, false)
  ) as awards(award_kind, award_label, award_order, required_for_readiness)
),
final_award_counts as (
  select s.section_id, s.species_key, s.section_label, s.sort_order,
    t.award_kind, t.award_label, t.award_order, t.required_for_readiness,
    count(distinct fa.entry_id)::int as winner_count
  from applicable_final_award_sections s
  cross join required_final_award_types t
  left join final_awards fa on fa.section_id = s.section_id
    and fa.species_key = s.species_key and fa.award_kind = t.award_kind
  group by s.section_id, s.species_key, s.section_label, s.sort_order,
    t.award_kind, t.award_label, t.award_order, t.required_for_readiness
),
missing_final_awards as (
  select count(*) filter (where winner_count < 1 and required_for_readiness)::int as total
  from final_award_counts
),
missing_final_award_details as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'section_id', section_id, 'section_label', section_label,
    'species', species_key, 'award_code', award_kind,
    'award_label', award_label
  ) order by sort_order, section_label, species_key, award_order)
    filter (where winner_count < 1 and required_for_readiness), '[]'::jsonb) as items
  from final_award_counts
),
suggested_final_awards as (
  select count(*) filter (where winner_count < 1 and not required_for_readiness)::int as total,
    coalesce(jsonb_agg(jsonb_build_object(
      'section_id', section_id, 'section_label', section_label,
      'species', species_key, 'award_code', award_kind,
      'award_label', award_label
    ) order by sort_order, section_label, species_key, award_order)
      filter (where winner_count < 1 and not required_for_readiness), '[]'::jsonb) as items
  from final_award_counts
),
duplicate_final_award_winners as (
  select coalesce(sum(greatest(winner_count - 1, 0)), 0)::int as total
  from final_award_counts
),
same_entry_final_award_conflicts as (
  select count(*)::int as total
  from (
    select section_id, species_key, entry_id
    from final_awards
    group by section_id, species_key, entry_id
    having count(distinct award_kind) > 1
  ) conflicts
),
counts as (
  select
    (select total from missing_placement) as missing_placement_count,
    (select total from missing_judge) as missing_judge_count,
    (select total from duplicate_placement_groups) as duplicate_placement_group_count,
    (select total from missing_final_awards) as missing_final_award_count,
    ((select total from duplicate_final_award_winners) +
      (select total from same_entry_final_award_conflicts))::int as duplicate_final_award_count,
    (select items from missing_final_award_details) as missing_final_awards,
    (select total from suggested_final_awards) as suggested_final_award_count,
    (select items from suggested_final_awards) as suggested_final_awards
)
select jsonb_build_object(
  'ready', missing_placement_count = 0 and missing_judge_count = 0
    and duplicate_placement_group_count = 0 and missing_final_award_count = 0
    and duplicate_final_award_count = 0,
  'missing_placement_count', missing_placement_count,
  'missing_judge_count', missing_judge_count,
  'duplicate_placement_group_count', duplicate_placement_group_count,
  'missing_final_award_count', missing_final_award_count,
  'duplicate_final_award_count', duplicate_final_award_count,
  'missing_final_awards', missing_final_awards,
  'suggested_final_award_count', suggested_final_award_count,
  'suggested_final_awards', suggested_final_awards
)
from counts;
$function$;

revoke all on function public.show_results_readiness_scoped(uuid, uuid[])
  from public, anon;
grant execute on function public.show_results_readiness_scoped(uuid, uuid[])
  to authenticated, service_role;

create index if not exists entry_awards_entry_id_idx
  on public.entry_awards (entry_id);
