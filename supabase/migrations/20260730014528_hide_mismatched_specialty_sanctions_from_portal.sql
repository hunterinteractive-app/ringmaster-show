-- A specialty-only section is exclusively for the breed named in its label.
-- Older imported sanction sheets occasionally copied every club's sanction into
-- those sections. Do not expose those mismatched records to the chair portal.
do $$
begin
  if to_regprocedure('public.list_sweepstakes_portal_shows_specialty_base()') is null then
    alter function public.list_sweepstakes_portal_shows()
      rename to list_sweepstakes_portal_shows_specialty_base;
  end if;
end;
$$;

revoke all on function public.list_sweepstakes_portal_shows_specialty_base() from public;
revoke all on function public.list_sweepstakes_portal_shows_specialty_base() from authenticated;

create or replace function public.list_sweepstakes_portal_shows()
returns table (
  portal_club_id uuid, club_name text, show_id uuid, show_name text,
  show_date date, show_location text, breed_name text, sanction_number text,
  sanctioning_body text, section_label text, eligible_entry_count integer,
  report_status text, report_artifact_id uuid
)
language sql stable security definer set search_path = ''
as $$
  select base.*
  from public.list_sweepstakes_portal_shows_specialty_base() base
  where upper(btrim(coalesce(base.sanctioning_body, ''))) in ('ARBA', 'STATE CLUB')
     or lower(coalesce(base.section_label, '')) not like '%specialty only%'
     or lower(regexp_replace(coalesce(base.section_label, ''), '[^a-z0-9]+', ' ', 'g'))
          like '%' || lower(regexp_replace(coalesce(base.breed_name, ''), '[^a-z0-9]+', ' ', 'g')) || '%';
$$;

revoke all on function public.list_sweepstakes_portal_shows() from public;
grant execute on function public.list_sweepstakes_portal_shows() to authenticated;
