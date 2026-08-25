-- Keep closeout Step 3 aligned with the final-award modes used by Results
-- Entry.  Previously it only evaluated the legacy BIS/1RIS/2RIS mode, which
-- let B4C/B6C/BIS and BIS/RIS requirements appear only when reports ran.
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
  select lower(trim(coalesce(s.final_award_mode, 'four_six_bis'))) as final_award_mode
  from public.shows s where s.id = p_show_id
),
eligible_rows as (
  select e.id as entry_id, e.section_id,
    case when lower(trim(coalesce(e.sex, ''))) in ('boar', 'sow') then 'cavy' else 'rabbit' end as species_key,
    coalesce(e.is_shown, true) as is_shown, coalesce(e.is_disqualified, false) as is_disqualified,
    coalesce(e.is_fur, false) as is_fur_key, e.scratched_at,
    lower(trim(coalesce(e.result_status, 'Shown'))) as result_status_key,
    nullif(trim(case when coalesce(e.is_fur, false) then e.fur_placement::text else e.placement::text end), '') as placement,
    e.judged_by_show_judge_id,
    lower(trim(coalesce(nullif(e.breed, ''), ''))) as breed_key,
    lower(trim(coalesce(nullif(e.variety, ''), ''))) as variety_key,
    lower(trim(coalesce(e.class_name, ''))) as class_name_key,
    lower(trim(coalesce(e.sex, ''))) as sex_key
  from public.entries e
  where e.show_id = p_show_id and e.section_id = any(coalesce(p_section_ids, array[]::uuid[]))
),
required_results as (
  select * from eligible_rows
  where scratched_at is null and is_shown = true and is_disqualified = false
    and result_status_key not in ('no show', 'unworthy of award')
    and result_status_key not like 'disqualified%'
),
required_entries as (
  select distinct entry_id, section_id, species_key, breed_key from required_results
),
missing_placement as (
  select count(distinct entry_id)::int as total from required_results where placement is null
),
missing_judge as (
  select count(distinct entry_id)::int as total from required_results where judged_by_show_judge_id is null
),
duplicate_placement_groups as (
  select count(*)::int as total from (
    select section_id, breed_key, variety_key, class_name_key, sex_key, is_fur_key, placement
    from required_results where placement is not null
    group by section_id, breed_key, variety_key, class_name_key, sex_key, is_fur_key, placement
    having count(distinct entry_id) > 1
  ) duplicates
),
applicable_final_award_sections as (
  select distinct re.section_id, re.species_key,
    coalesce(nullif(trim(sec.display_name), ''), initcap(sec.kind::text) || ' ' || upper(sec.letter)) as section_label,
    sec.sort_order
  from required_entries re
  join public.show_sections sec on sec.id = re.section_id
  cross join show_settings ss
  where ss.final_award_mode in ('four_six_bis', 'bis_ris', 'bis_1ris_2ris')
    and (ss.final_award_mode <> 'four_six_bis' or re.species_key = 'rabbit')
),
normalized_final_awards as (
  select distinct re.entry_id, re.section_id, re.species_key,
    case
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('bob', 'bestofbreed') then 'BOB'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('b4c', 'best4class', 'bestfourclass') then 'B4C'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('b6c', 'best6class', 'bestsixclass') then 'B6C'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('bis', 'bestinshow', 'bestinshowrabbit') then 'BIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('ris', 'reserveinshow') then 'RIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('1ris', '1stris', 'firstris', '1streserveinshow', 'firstreserveinshow') then '1RIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('2ris', '2ndris', 'secondris', '2ndreserveinshow', 'secondreserveinshow') then '2RIS'
      else null
    end as award_kind
  from required_entries re join public.entry_awards ea on ea.entry_id = re.entry_id
),
final_awards as (
  select nfa.* from normalized_final_awards nfa cross join show_settings ss
  where nfa.award_kind is not null and (
    (ss.final_award_mode = 'four_six_bis' and nfa.award_kind in ('BOB', 'B4C', 'B6C', 'BIS')) or
    (ss.final_award_mode = 'bis_ris' and nfa.award_kind in ('BOB', 'BIS', 'RIS')) or
    (ss.final_award_mode = 'bis_1ris_2ris' and nfa.award_kind in ('BIS', '1RIS', '2RIS'))
  )
),
bob_awards as (
  select distinct section_id, species_key, entry_id
  from final_awards
  where award_kind = 'BOB'
),
breed_classified_bobs as (
  select distinct fa.section_id, fa.species_key, fa.entry_id,
    case when lower(trim(coalesce(sb.class_system_override, b.class_system, 'four'))) in ('six', 'sixclass', 'six_class', 'six-class', '6') then 'six' else 'four' end as class_system
  from bob_awards fa
  join required_entries re on re.entry_id = fa.entry_id
  join public.breeds b on lower(trim(b.name)) = re.breed_key and lower(trim(b.species::text)) = 'rabbit'
  left join public.show_breeds sb on sb.show_id = p_show_id and sb.breed_id = b.id
  where fa.species_key = 'rabbit'
),
invalid_final_award_rows as (
  select
    fa.section_id,
    fa.species_key,
    coalesce(nullif(trim(sec.display_name), ''), initcap(sec.kind::text) || ' ' || upper(sec.letter)) as section_label,
    sec.sort_order as section_sort_order,
    fa.award_kind as award_code,
    case fa.award_kind
      when 'B4C' then 'Best 4-Class'
      when 'B6C' then 'Best 6-Class'
      when 'BIS' then 'Best in Show'
      when 'RIS' then 'Reserve in Show'
      else fa.award_kind
    end as award_label,
    case
      when fa.award_kind = 'B4C' then
        'Best 4-Class must be awarded to Best of Breed from a four-class rabbit breed.'
      when fa.award_kind = 'B6C' then
        'Best 6-Class must be awarded to Best of Breed from a six-class rabbit breed.'
      when ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'BIS' then
        'Best in Show must be selected from the Best 4-Class or Best 6-Class winner.'
      when ss.final_award_mode = 'bis_ris' and fa.award_kind = 'BIS' then
        'Best in Show must be awarded to a Best of Breed winner.'
      when ss.final_award_mode = 'bis_ris' and fa.award_kind = 'RIS' then
        'Reserve in Show must be awarded to a Best of Breed winner.'
    end as reason
  from final_awards fa
  join public.show_sections sec on sec.id = fa.section_id
  cross join show_settings ss
  where
    (ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'B4C' and not exists (
      select 1 from breed_classified_bobs bob
      where bob.section_id = fa.section_id
        and bob.species_key = fa.species_key
        and bob.entry_id = fa.entry_id
        and bob.class_system = 'four'
    ))
    or
    (ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'B6C' and not exists (
      select 1 from breed_classified_bobs bob
      where bob.section_id = fa.section_id
        and bob.species_key = fa.species_key
        and bob.entry_id = fa.entry_id
        and bob.class_system = 'six'
    ))
    or
    (ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'BIS' and not exists (
      select 1 from final_awards qualifier
      where qualifier.section_id = fa.section_id
        and qualifier.species_key = fa.species_key
        and qualifier.entry_id = fa.entry_id
        and qualifier.award_kind in ('B4C', 'B6C')
    ))
    or
    (ss.final_award_mode = 'bis_ris' and fa.award_kind in ('BIS', 'RIS') and not exists (
      select 1 from bob_awards bob
      where bob.section_id = fa.section_id
        and bob.species_key = fa.species_key
        and bob.entry_id = fa.entry_id
    ))
),
invalid_final_awards as (
  select
    count(*)::integer as total,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'section_id', section_id,
          'species_key', species_key,
          'section_label', section_label,
          'award_code', award_code,
          'award_label', award_label,
          'reason', reason
        )
        order by section_sort_order, section_label, species_key, award_code
      ),
      '[]'::jsonb
    ) as items
  from invalid_final_award_rows
),
final_award_requirements as (
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'B4C'::text as award_kind, 'Best 4-Class'::text as award_label, 1 as award_order, true as required_for_readiness
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'four_six_bis' and exists (select 1 from breed_classified_bobs b where b.section_id = s.section_id and b.class_system = 'four')
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'B6C', 'Best 6-Class', 2, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'four_six_bis' and exists (select 1 from breed_classified_bobs b where b.section_id = s.section_id and b.class_system = 'six')
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'BIS', 'Best in Show', 3, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'four_six_bis' and exists (select 1 from breed_classified_bobs b where b.section_id = s.section_id)
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'BIS', 'Best in Show', 1, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'bis_ris' and exists (
    select 1 from bob_awards b
    where b.section_id = s.section_id and b.species_key = s.species_key
  )
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'RIS', 'Reserve in Show', 2, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'bis_ris' and (
    select count(*) from bob_awards b
    where b.section_id = s.section_id and b.species_key = s.species_key
  ) > 1
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, v.award_kind, v.award_label, v.award_order, v.required_for_readiness
  from applicable_final_award_sections s cross join show_settings ss
  cross join (values ('BIS'::text, 'Best in Show'::text, 1, true), ('1RIS', 'First Reserve in Show', 2, true), ('2RIS', 'Second Reserve in Show', 3, false)) v(award_kind, award_label, award_order, required_for_readiness)
  where ss.final_award_mode = 'bis_1ris_2ris'
),
final_award_counts as (
  select r.section_id, r.species_key, r.section_label, r.sort_order, r.award_kind, r.award_label, r.award_order, r.required_for_readiness,
    count(distinct fa.entry_id)::int as winner_count
  from final_award_requirements r
  left join final_awards fa on fa.section_id = r.section_id and fa.species_key = r.species_key and fa.award_kind = r.award_kind
  group by r.section_id, r.species_key, r.section_label, r.sort_order, r.award_kind, r.award_label, r.award_order, r.required_for_readiness
),
missing_final_awards as (
  select count(*) filter (where winner_count < 1 and required_for_readiness)::int as total from final_award_counts
),
missing_final_award_details as (
  select coalesce(jsonb_agg(jsonb_build_object('section_id', section_id, 'section_label', section_label, 'species', species_key, 'award_code', award_kind, 'award_label', award_label) order by sort_order, section_label, species_key, award_order) filter (where winner_count < 1 and required_for_readiness), '[]'::jsonb) as items from final_award_counts
),
suggested_final_awards as (
  select count(*) filter (where winner_count < 1 and not required_for_readiness)::int as total,
    coalesce(jsonb_agg(jsonb_build_object('section_id', section_id, 'section_label', section_label, 'species', species_key, 'award_code', award_kind, 'award_label', award_label) order by sort_order, section_label, species_key, award_order) filter (where winner_count < 1 and not required_for_readiness), '[]'::jsonb) as items from final_award_counts
),
duplicate_final_award_winners as (
  select coalesce(sum(greatest(winner_count - 1, 0)), 0)::int as total from final_award_counts
),
same_entry_final_award_conflicts as (
  select count(*)::int as total from (
    select fa.section_id, fa.species_key, fa.entry_id from final_awards fa cross join show_settings ss
    where ss.final_award_mode = 'four_six_bis' and fa.award_kind in ('B4C', 'B6C')
    group by fa.section_id, fa.species_key, fa.entry_id having count(distinct fa.award_kind) > 1
    union all
    select fa.section_id, fa.species_key, fa.entry_id from final_awards fa cross join show_settings ss
    where ss.final_award_mode <> 'four_six_bis' and fa.award_kind in ('BIS', 'RIS', '1RIS', '2RIS')
    group by fa.section_id, fa.species_key, fa.entry_id having count(distinct fa.award_kind) > 1
  ) conflicts
),
counts as (
  select (select total from missing_placement) as missing_placement_count,
    (select total from missing_judge) as missing_judge_count,
    (select total from duplicate_placement_groups) as duplicate_placement_group_count,
    (select total from missing_final_awards) as missing_final_award_count,
    ((select total from duplicate_final_award_winners) + (select total from same_entry_final_award_conflicts))::int as duplicate_final_award_count,
    (select total from invalid_final_awards) as invalid_final_award_count,
    (select items from missing_final_award_details) as missing_final_awards,
    (select items from invalid_final_awards) as invalid_final_awards,
    (select total from suggested_final_awards) as suggested_final_award_count,
    (select items from suggested_final_awards) as suggested_final_awards
)
select jsonb_build_object(
  'ready', missing_placement_count = 0 and missing_judge_count = 0 and duplicate_placement_group_count = 0 and missing_final_award_count = 0 and duplicate_final_award_count = 0 and invalid_final_award_count = 0,
  'missing_placement_count', missing_placement_count, 'missing_judge_count', missing_judge_count,
  'duplicate_placement_group_count', duplicate_placement_group_count, 'missing_final_award_count', missing_final_award_count,
  'duplicate_final_award_count', duplicate_final_award_count, 'invalid_final_award_count', invalid_final_award_count,
  'missing_final_awards', missing_final_awards, 'invalid_final_awards', invalid_final_awards,
  'suggested_final_award_count', suggested_final_award_count, 'suggested_final_awards', suggested_final_awards
) from counts;
$function$;

revoke all on function public.show_results_readiness_scoped(uuid, uuid[]) from public, anon;
grant execute on function public.show_results_readiness_scoped(uuid, uuid[]) to authenticated, service_role;
