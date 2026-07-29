-- Keep the chair portal focused on current work: newest show dates first and
-- no records older than one year.
alter function public.list_sweepstakes_portal_shows()
  rename to list_sweepstakes_portal_shows_delivered_base;

revoke all on function public.list_sweepstakes_portal_shows_delivered_base() from public;
revoke all on function public.list_sweepstakes_portal_shows_delivered_base() from authenticated;

create function public.list_sweepstakes_portal_shows()
returns table (
  portal_club_id uuid, club_name text, show_id uuid, show_name text,
  show_date date, show_location text, breed_name text, sanction_number text,
  sanctioning_body text, section_label text, eligible_entry_count integer,
  report_status text, report_artifact_id uuid
)
language sql stable security definer set search_path = ''
as $$
  select *
  from public.list_sweepstakes_portal_shows_delivered_base()
  where show_date >= current_date - interval '1 year'
  order by show_date desc, show_name asc, section_label asc, sanction_number asc;
$$;

revoke all on function public.list_sweepstakes_portal_shows() from public;
grant execute on function public.list_sweepstakes_portal_shows() to authenticated;
