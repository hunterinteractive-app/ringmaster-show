-- Rabbit-only portal schedules.  Cavy points use their separate award-based
-- calculator and intentionally do not read this table.
--
-- A completed show retains its already-persisted result rows.  This is what
-- keeps historical reports stable even when a club adds a later schedule.

create or replace function public.get_effective_rabbit_sweepstakes_portal_rule(
  p_show_id uuid,
  p_breed_name text
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with show_context as (
    select show.id, show.start_date, coalesce(show.is_national_show, false) as is_national_show
    from public.shows show
    where show.id = p_show_id
  ), candidates as (
    select schedule.rules, schedule.effective_on
    from show_context context
    join public.show_sanctions sanction on sanction.show_id = context.id
    join public.sweepstakes_portal_clubs portal_club
      on portal_club.normalized_name = lower(btrim(sanction.club_name))
    join public.sweepstakes_point_schedules schedule
      on schedule.portal_club_id = portal_club.id
     and schedule.effective_on <= context.start_date
    where lower(btrim(sanction.breed_name)) = lower(btrim(p_breed_name))
      and coalesce(schedule.rules ->> 'show_type', 'regular') =
        case when context.is_national_show then 'national' else 'regular' end
      and coalesce(schedule.rules ->> 'class_points_model', '') in (
        'MULTIPLIER_BY_CLASS_SIZE',
        'FLAT_BY_PLACING'
      )
    order by schedule.effective_on desc, schedule.created_at desc
    limit 1
  )
  select rules from candidates;
$$;

revoke all on function public.get_effective_rabbit_sweepstakes_portal_rule(uuid, text) from public;
grant execute on function public.get_effective_rabbit_sweepstakes_portal_rule(uuid, text)
  to authenticated, service_role;

-- Preserve the fully tested existing calculator as the baseline, then layer a
-- club's effective placement schedule onto rabbit class and fur placements.
alter function public.calculate_sweepstakes_for_breed_legacy(uuid, text, text, text)
  rename to calculate_sweepstakes_for_breed_baseline;

create function public.calculate_sweepstakes_for_breed_legacy(
  p_show_id uuid,
  p_breed_name text,
  p_scope text,
  p_show_letter text default null
)
returns setof public.sweepstakes_results
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_letter text := upper(coalesce(nullif(btrim(p_show_letter), ''), 'ALL'));
  v_rules jsonb;
  v_is_completed boolean := false;
  v_has_saved_results boolean := false;
begin
  if upper(coalesce(p_scope, '')) not in ('OPEN', 'YOUTH') then
    raise exception 'Invalid scope: %. Expected OPEN or YOUTH.', p_scope;
  end if;

  select coalesce(show.is_closed, false) or show.finalized_at is not null
    into v_is_completed
  from public.shows show
  where show.id = p_show_id;

  select exists (
    select 1
    from public.sweepstakes_results result
    where result.show_id = p_show_id
      and result.breed_name = p_breed_name
      and upper(result.scope) = upper(p_scope)
      and upper(coalesce(result.show_letter, 'ALL')) = v_letter
  ) into v_has_saved_results;

  -- Never regenerate a completed show's persisted points.  Reports and their
  -- point snapshots remain historical records.
  if v_is_completed and v_has_saved_results then
    return query
    select result.*
    from public.sweepstakes_results result
    where result.show_id = p_show_id
      and result.breed_name = p_breed_name
      and upper(result.scope) = upper(p_scope)
      and upper(coalesce(result.show_letter, 'ALL')) = v_letter
    order by result.total_points desc, result.exhibitor_name;
    return;
  end if;

  perform public.calculate_sweepstakes_for_breed_baseline(
    p_show_id, p_breed_name, p_scope, p_show_letter
  );

  select public.get_effective_rabbit_sweepstakes_portal_rule(p_show_id, p_breed_name)
    into v_rules;

  if v_rules is null then
    return query
    select result.*
    from public.sweepstakes_results result
    where result.show_id = p_show_id
      and result.breed_name = p_breed_name
      and upper(result.scope) = upper(p_scope)
      and upper(coalesce(result.show_letter, 'ALL')) = v_letter
    order by result.total_points desc, result.exhibitor_name;
    return;
  end if;

  delete from public.sweepstakes_entry_results entry_result
  where entry_result.show_id = p_show_id
    and entry_result.breed_name = p_breed_name
    and upper(entry_result.scope) = upper(p_scope)
    and upper(coalesce(entry_result.show_letter, 'ALL')) = v_letter
    and entry_result.points_source in ('CLASS', 'FUR');

  insert into public.sweepstakes_entry_results (
    show_id, exhibitor_id, entry_id, animal_id, breed_name, variety_name,
    class_name, sex, tattoo, show_letter, scope, points_source, points
  )
  with placement_scale as (
    select scale.place, scale.points
    from jsonb_to_recordset(coalesce(v_rules -> 'placements', '[]'::jsonb))
      as scale(place integer, points numeric)
  ), result_rows as (
    select
      row.entry_id,
      row.exhibitor_id::text as exhibitor_id,
      p_show_id as show_id,
      row.breed_name,
      row.variety_name,
      row.class_name,
      row.sex,
      row.tattoo,
      coalesce(row.fur_variety, '') as fur_variety,
      coalesce(row.is_fur, false) as is_fur,
      row.section_id,
      row.section_letter,
      case when btrim(coalesce(row.placement, '')) ~ '^\\d+$'
        then btrim(row.placement)::integer end as placement_num,
      row.is_shown,
      row.is_disqualified
    from public.show_sections section
    cross join lateral public.report_results_entry_rows(p_show_id, section.id, p_show_letter) row
    where section.show_id = p_show_id
      and upper(section.kind::text) = upper(p_scope)
      and row.breed_name = p_breed_name
      and (
        (p_show_letter is not null and btrim(p_show_letter) <> ''
          and upper(coalesce(section.letter::text, '')) = upper(p_show_letter))
        or (p_show_letter is null or btrim(p_show_letter) = '')
      )
  ), eligible_rows as (
    select * from result_rows
    where coalesce(is_shown, true)
      and not coalesce(is_disqualified, false)
      and placement_num between 1 and 5
  ), class_counts as (
    select
      is_fur,
      case when is_fur then fur_variety else variety_name end as variety_key,
      case when is_fur then null else sex end as sex_key,
      case when is_fur then null else class_name end as class_key,
      section_id,
      count(*)::numeric as entry_count
    from eligible_rows
    group by 1, 2, 3, 4, 5
  )
  select
    row.show_id,
    row.exhibitor_id::uuid,
    row.entry_id,
    null,
    row.breed_name,
    case when row.is_fur then coalesce(nullif(row.fur_variety, ''), 'Wool') else row.variety_name end,
    case when row.is_fur then '' else row.class_name end,
    case when row.is_fur then '' else row.sex end,
    row.tattoo,
    coalesce(row.section_letter, v_letter),
    upper(p_scope),
    case when row.is_fur then 'FUR' else 'CLASS' end,
    (
      coalesce(scale.points, 0) *
      case when coalesce(v_rules ->> 'class_points_model', 'MULTIPLIER_BY_CLASS_SIZE') = 'FLAT_BY_PLACING'
        then 1 else coalesce(counts.entry_count, 0) end
    )::numeric(10,2)
  from eligible_rows row
  join placement_scale scale on scale.place = row.placement_num
  join class_counts counts
    on counts.is_fur = row.is_fur
   and counts.variety_key is not distinct from case when row.is_fur then row.fur_variety else row.variety_name end
   and counts.sex_key is not distinct from case when row.is_fur then null else row.sex end
   and counts.class_key is not distinct from case when row.is_fur then null else row.class_name end
   and counts.section_id = row.section_id;

  update public.sweepstakes_results result
  set
    class_points = coalesce(replacement.class_points, 0),
    fur_points = coalesce(replacement.fur_points, 0),
    total_points = (
      coalesce(replacement.class_points, 0)
      + coalesce(result.variety_points, 0)
      + coalesce(result.group_points, 0)
      + coalesce(result.bob_points, 0)
      + coalesce(result.bis_points, 0)
      + coalesce(replacement.fur_points, 0)
    )::numeric(10,2),
    rule_source = 'PORTAL_EFFECTIVE_SCHEDULE'
  from (
    select
      entry_result.exhibitor_id::text as exhibitor_id,
      sum(entry_result.points) filter (where entry_result.points_source = 'CLASS')::numeric(10,2) as class_points,
      sum(entry_result.points) filter (where entry_result.points_source = 'FUR')::numeric(10,2) as fur_points
    from public.sweepstakes_entry_results entry_result
    where entry_result.show_id = p_show_id
      and entry_result.breed_name = p_breed_name
      and upper(entry_result.scope) = upper(p_scope)
      and upper(coalesce(entry_result.show_letter, 'ALL')) = v_letter
      and entry_result.points_source in ('CLASS', 'FUR')
    group by entry_result.exhibitor_id
  ) replacement
  where result.show_id = p_show_id
    and result.breed_name = p_breed_name
    and upper(result.scope) = upper(p_scope)
    and upper(coalesce(result.show_letter, 'ALL')) = v_letter
    and result.exhibitor_id = replacement.exhibitor_id;

  return query
  select result.*
  from public.sweepstakes_results result
  where result.show_id = p_show_id
    and result.breed_name = p_breed_name
    and upper(result.scope) = upper(p_scope)
    and upper(coalesce(result.show_letter, 'ALL')) = v_letter
  order by result.total_points desc, result.exhibitor_name;
end;
$function$;

revoke all on function public.calculate_sweepstakes_for_breed_legacy(uuid, text, text, text) from public, anon;
grant execute on function public.calculate_sweepstakes_for_breed_legacy(uuid, text, text, text)
  to authenticated, service_role;

alter function public.calculate_sweepstakes_for_breed_baseline(uuid, text, text, text) set search_path = '';
alter function public.calculate_sweepstakes_for_breed_legacy(uuid, text, text, text) set search_path = '';
