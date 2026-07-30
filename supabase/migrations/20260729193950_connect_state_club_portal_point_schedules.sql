-- State-club reports use the Display Points calculation.  This adds their own
-- prospective schedule mode without changing the completed report artifacts
-- already stored for prior shows.
create or replace function public.get_sweepstakes_portal_point_schedule_mode(p_portal_club_id uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when not (select public.can_preview_sweepstakes_portal_club(p_portal_club_id)) then 'none'
    when exists (
      select 1
      from public.sweepstakes_portal_clubs club
      join public.show_sanctions sanction
        on lower(btrim(sanction.club_name)) = club.normalized_name
      where club.id = p_portal_club_id
        and upper(btrim(coalesce(sanction.sanctioning_body, ''))) = 'STATE CLUB'
    ) then 'state'
    when exists (
      select 1
      from public.sweepstakes_portal_clubs club
      join public.show_sanctions sanction
        on lower(btrim(sanction.club_name)) = club.normalized_name
      where club.id = p_portal_club_id
        and lower(btrim(sanction.breed_name)) = 'cavy'
    ) then 'cavy'
    when exists (
      select 1
      from public.sweepstakes_portal_clubs club
      join public.show_sanctions sanction
        on lower(btrim(sanction.club_name)) = club.normalized_name
      join public.entries entry
        on entry.show_id = sanction.show_id
       and entry.species::text = 'rabbit'
      where club.id = p_portal_club_id
    ) then 'rabbit'
    else 'none'
  end;
$$;

revoke all on function public.get_sweepstakes_portal_point_schedule_mode(uuid) from public;
grant execute on function public.get_sweepstakes_portal_point_schedule_mode(uuid) to authenticated;

-- Keep the existing query as the default for every other report.  The wrapper
-- reads a state club's dated schedule only when the show carries its State Club
-- sanction.  A new schedule cannot retroactively apply because portal saves
-- require an effective date of today or later, and generated report artifacts
-- stay immutable.
alter function public.report_best_display_entry_rows(uuid, text, text)
  rename to report_best_display_entry_rows_baseline;

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
  )
  select
    base.show_id, base.section_id, base.scope, base.show_letter, base.species,
    base.exhibitor_id, base.exhibitor_name, base.entry_id, base.breed_name,
    base.variety_name, base.group_name, base.class_name, base.sex, base.tattoo,
    base.placement, base.animals_judged,
    case
      when state_schedule.rules is null then base.placement_multiplier
      else coalesce(scale.points, base.placement_multiplier)
    end::integer as placement_multiplier,
    case
      when state_schedule.rules is null then base.display_points
      when coalesce(state_schedule.rules ->> 'class_points_model', 'MULTIPLIER_BY_CLASS_SIZE') = 'FLAT_BY_PLACING'
        then coalesce(scale.points, base.placement_multiplier)::numeric
      else (base.animals_judged * coalesce(scale.points, base.placement_multiplier))::numeric
    end as display_points,
    base.is_point_earning
  from public.report_best_display_entry_rows_baseline(
    p_show_id := p_show_id,
    p_scope := p_scope,
    p_show_letter := p_show_letter
  ) base
  left join state_schedule on true
  left join lateral (
    select nullif(element ->> 'points', '')::numeric as points
    from jsonb_array_elements(coalesce(state_schedule.rules -> 'placements', '[]'::jsonb)) element
    where nullif(element ->> 'place', '')::integer = base.placement
    limit 1
  ) scale on true;
$$;

revoke all on function public.report_best_display_entry_rows(uuid, text, text) from public;
grant execute on function public.report_best_display_entry_rows(uuid, text, text)
  to authenticated, service_role;
