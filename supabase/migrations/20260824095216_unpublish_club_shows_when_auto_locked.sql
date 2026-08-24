-- A show past the club access window must no longer appear publicly.
create or replace function public.auto_lock_club_shows_after_sixty_days()
returns table (show_id uuid)
language sql
security invoker
set search_path = ''
as $function$
  update public.shows as show
  set
    is_locked = true,
    is_published = false,
    locked_at = coalesce(show.locked_at, now())
  where show.club_id is not null
    and show.end_date <= current_date - 60
    and (not show.is_locked or show.is_published)
  returning show.id;
$function$;
