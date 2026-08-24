-- Lock club-hosted shows after their 60-day post-show access window.
-- The job is idempotent: already locked shows are never changed.
create or replace function public.auto_lock_club_shows_after_sixty_days()
returns table (show_id uuid)
language sql
security invoker
set search_path = ''
as $function$
  update public.shows as show
  set
    is_locked = true,
    locked_at = coalesce(show.locked_at, now())
  where show.club_id is not null
    and show.end_date <= current_date - 60
    and not show.is_locked
  returning show.id;
$function$;

revoke all on function public.auto_lock_club_shows_after_sixty_days() from public, anon, authenticated;

select cron.unschedule(jobid)
from cron.job
where jobname = 'daily-club-show-auto-lock';

select cron.schedule(
  'daily-club-show-auto-lock',
  '45 5 * * *',
  $cron$select public.auto_lock_club_shows_after_sixty_days();$cron$
);
