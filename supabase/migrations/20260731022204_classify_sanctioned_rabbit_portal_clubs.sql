-- A valid rabbit breed club can have sanctioned shows before any entry rows exist.
-- Classify those clubs from their sanctions, rather than requiring a matching entry.
create or replace function public.get_sweepstakes_portal_point_schedule_mode(
  p_portal_club_id uuid
)
returns text
language sql
stable
set search_path = ''
as $function$
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
      where club.id = p_portal_club_id
    ) then 'rabbit'
    else 'none'
  end;
$function$;
