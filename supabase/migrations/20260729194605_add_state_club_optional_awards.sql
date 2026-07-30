-- Layer dated optional award values onto the State Club Display Points rows.
-- The schedule is read by the show date, so past shows retain their rule set.
alter function public.report_best_display_entry_rows(uuid, text, text)
  rename to report_best_display_entry_rows_state_placements;

create function public.report_best_display_entry_rows(
  p_show_id uuid,
  p_scope text default null,
  p_show_letter text default null
)
returns table(
  show_id uuid, section_id uuid, scope text, show_letter text, species text,
  exhibitor_id uuid, exhibitor_name text, entry_id uuid, breed_name text,
  variety_name text, group_name text, class_name text, sex text, tattoo text,
  placement integer, animals_judged integer, placement_multiplier integer,
  display_points numeric, is_point_earning boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  with state_schedule as (
    select schedule.rules
    from public.shows show
    join public.show_sanctions sanction on sanction.show_id = show.id
    join public.sweepstakes_portal_clubs club
      on club.normalized_name = lower(btrim(sanction.club_name))
    join public.sweepstakes_point_schedules schedule
      on schedule.portal_club_id = club.id
     and schedule.effective_on <= show.start_date
    where show.id = p_show_id
      and upper(btrim(coalesce(sanction.sanctioning_body, ''))) = 'STATE CLUB'
      and coalesce(schedule.rules ->> 'points_mode', '') = 'state_display'
      and coalesce(schedule.rules ->> 'show_type', 'regular') =
        case when coalesce(show.is_national_show, false) then 'national' else 'regular' end
    order by schedule.effective_on desc, schedule.created_at desc
    limit 1
  ), award_points as (
    select award.entry_id, sum(coalesce(scale.rabbit_points, 0))::numeric as points
    from (
      select distinct entry_award.entry_id, upper(btrim(entry_award.award_code)) as code
      from public.entry_awards entry_award
      where entry_award.show_id = p_show_id
        and nullif(btrim(entry_award.award_code), '') is not null
      union
      select distinct result.entry_id, upper(btrim(result.award))
      from public.results result
      where result.show_id = p_show_id
        and nullif(btrim(result.award), '') is not null
    ) award
    cross join state_schedule
    join lateral jsonb_to_recordset(coalesce(state_schedule.rules -> 'awards', '[]'::jsonb))
      as scale(code text, rabbit_points numeric, active boolean)
      on upper(btrim(scale.code)) = award.code
     and coalesce(scale.active, true)
    group by award.entry_id
  )
  select
    base.show_id, base.section_id, base.scope, base.show_letter, base.species,
    base.exhibitor_id, base.exhibitor_name, base.entry_id, base.breed_name,
    base.variety_name, base.group_name, base.class_name, base.sex, base.tattoo,
    base.placement, base.animals_judged, base.placement_multiplier,
    (base.display_points + coalesce(award_points.points, 0))::numeric as display_points,
    base.is_point_earning
  from public.report_best_display_entry_rows_state_placements(
    p_show_id := p_show_id,
    p_scope := p_scope,
    p_show_letter := p_show_letter
  ) base
  left join award_points on award_points.entry_id = base.entry_id;
$$;

revoke all on function public.report_best_display_entry_rows(uuid, text, text) from public;
grant execute on function public.report_best_display_entry_rows(uuid, text, text)
  to authenticated, service_role;
