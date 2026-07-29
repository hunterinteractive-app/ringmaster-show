create function public.supports_rabbit_sweepstakes_point_schedules(
  p_portal_club_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select (select public.can_preview_sweepstakes_portal_club(p_portal_club_id))
    and exists (
      select 1
      from public.sweepstakes_portal_clubs portal_club
      join public.show_sanctions sanction
        on lower(btrim(sanction.club_name)) = portal_club.normalized_name
      join public.entries entry
        on entry.show_id = sanction.show_id
       and entry.species::text = 'rabbit'
      where portal_club.id = p_portal_club_id
      limit 1
    );
$$;

revoke all on function public.supports_rabbit_sweepstakes_point_schedules(uuid) from public;
grant execute on function public.supports_rabbit_sweepstakes_point_schedules(uuid)
  to authenticated;
