-- The underlying function continues to determine whether a club-specific
-- report artifact is ready.  The portal wrapper adds a clear completed-show
-- state for sanctions that had no eligible animals.
alter function public.list_sweepstakes_portal_shows()
  rename to list_sweepstakes_portal_shows_base;

revoke all on function public.list_sweepstakes_portal_shows_base() from public;
revoke all on function public.list_sweepstakes_portal_shows_base() from authenticated;

create function public.list_sweepstakes_portal_shows()
returns table (
  portal_club_id uuid,
  club_name text,
  show_id uuid,
  show_name text,
  show_date date,
  show_location text,
  breed_name text,
  sanction_number text,
  sanctioning_body text,
  section_label text,
  eligible_entry_count integer,
  report_status text,
  report_artifact_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    portal_club_id,
    club_name,
    show_id,
    show_name,
    show_date,
    show_location,
    breed_name,
    sanction_number,
    sanctioning_body,
    section_label,
    eligible_entry_count,
    case
      when report_status = 'not_ready'
       and show_date < current_date
       and eligible_entry_count = 0 then 'no_animals_shown'
      else report_status
    end,
    report_artifact_id
  from public.list_sweepstakes_portal_shows_base();
$$;

revoke all on function public.list_sweepstakes_portal_shows() from public;
grant execute on function public.list_sweepstakes_portal_shows() to authenticated;
