create function public.get_sweepstakes_portal_point_schedule_mode(p_portal_club_id uuid)
returns text language sql stable security invoker set search_path='' as $$
  select case
    when not (select public.can_preview_sweepstakes_portal_club(p_portal_club_id)) then 'none'
    when exists (select 1 from public.sweepstakes_portal_clubs club join public.show_sanctions sanction on lower(btrim(sanction.club_name))=club.normalized_name where club.id=p_portal_club_id and lower(btrim(sanction.breed_name))='cavy') then 'cavy'
    when exists (select 1 from public.sweepstakes_portal_clubs club join public.show_sanctions sanction on lower(btrim(sanction.club_name))=club.normalized_name join public.entries entry on entry.show_id=sanction.show_id and entry.species::text='rabbit' where club.id=p_portal_club_id) then 'rabbit'
    else 'none' end;
$$;
revoke all on function public.get_sweepstakes_portal_point_schedule_mode(uuid) from public;
grant execute on function public.get_sweepstakes_portal_point_schedule_mode(uuid) to authenticated;
