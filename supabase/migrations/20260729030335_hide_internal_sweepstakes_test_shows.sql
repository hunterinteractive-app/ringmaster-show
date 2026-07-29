-- Keep internal/demo shows out of the chair-facing Sweepstakes Portal.
-- These are explicit existing test records; no real club show is filtered by a
-- broad name or date heuristic.
create or replace function public.list_sweepstakes_portal_shows()
returns table (
  portal_club_id uuid, club_name text, show_id uuid, show_name text,
  show_date date, show_location text, breed_name text, sanction_number text,
  sanctioning_body text, section_label text, eligible_entry_count integer,
  report_status text, report_artifact_id uuid
)
language sql stable security definer set search_path = ''
as $$
  with assigned_clubs as (
    select distinct portal_club.id, portal_club.name, portal_club.normalized_name
    from public.sweepstakes_portal_clubs portal_club
    left join public.sweepstakes_portal_assignments assignment
      on assignment.portal_club_id = portal_club.id
     and assignment.is_active
     and assignment.normalized_email = lower(coalesce(auth.jwt() ->> 'email', ''))
    where (select public.is_sweepstakes_portal_tester()) or assignment.id is not null
  )
  select portal_club.id, portal_club.name, sanction.show_id, show.name,
    show.start_date, show.location_name, sanction.breed_name,
    sanction.sanction_number, sanction.sanctioning_body,
    coalesce(nullif(section.display_name, ''), initcap(section.kind::text) || ' ' || upper(section.letter::text)),
    count(entry.id) filter (
      where entry.scratched_at is null
        and lower(coalesce(entry.status, '')) <> 'scratched'
        and (upper(btrim(sanction.sanctioning_body)) = 'STATE CLUB'
          or lower(btrim(coalesce(entry.breed, ''))) = lower(btrim(coalesce(sanction.breed_name, ''))))
    )::integer,
    case
      when bool_or(artifact.artifact_status = 'generated'::public.artifact_status) then 'generated'
      when bool_or(artifact.artifact_status = 'failed'::public.artifact_status) then 'failed'
      when bool_or(artifact.artifact_status = 'queued'::public.artifact_status) then 'queued'
      else 'not_ready'
    end,
    (array_agg(artifact.id) filter (where artifact.artifact_status = 'generated'))[1]
  from assigned_clubs portal_club
  join public.show_sanctions sanction
    on lower(btrim(coalesce(sanction.club_name, ''))) = portal_club.normalized_name
  join public.shows show on show.id = sanction.show_id
   and show.id not in (
     '9dac84c0-1ee4-48fc-92ab-ccf695635def'::uuid, -- DO NOT ENTER - TEST SHOW
     '351c2d5b-da1b-4255-9284-34a120af71a2'::uuid, -- Hunter's Hopping
     '736f5141-23b9-45ee-b474-ff65d6c88c12'::uuid, -- Test Show
     '0f432fe8-2be2-467a-842f-ff3777436992'::uuid  -- RingMaster Demo Show
   )
  left join public.show_sections section on section.id = sanction.section_id
  left join public.entries entry on entry.show_id = sanction.show_id
    and (sanction.section_id is null or entry.section_id = sanction.section_id)
  left join public.show_report_artifacts artifact on artifact.show_id = sanction.show_id
    and artifact.is_current
    and artifact.report_name = 'sweepstakes_report'::public.report_type
    and lower(btrim(coalesce(artifact.metadata ->> 'club_name', ''))) = portal_club.normalized_name
    and coalesce(artifact.metadata ->> 'sanction_number', '') = coalesce(sanction.sanction_number, '')
  group by portal_club.id, portal_club.name, sanction.show_id, show.name, show.start_date,
    show.location_name, sanction.breed_name, sanction.sanction_number,
    sanction.sanctioning_body, section.display_name, section.kind, section.letter;
$$;

revoke all on function public.list_sweepstakes_portal_shows() from public;
grant execute on function public.list_sweepstakes_portal_shows() to authenticated;
