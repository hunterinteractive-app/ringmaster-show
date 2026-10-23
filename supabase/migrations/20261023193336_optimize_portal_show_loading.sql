-- Aggregate entries and reports separately to avoid the many-to-many join.
create or replace function public.list_sweepstakes_portal_shows_base()
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
  with assigned_clubs as (
    select distinct portal_club.id, portal_club.name, portal_club.normalized_name
    from public.sweepstakes_portal_clubs portal_club
    left join public.sweepstakes_portal_assignments assignment
      on assignment.portal_club_id = portal_club.id
     and assignment.is_active
     and assignment.normalized_email = lower(coalesce(auth.jwt() ->> 'email', ''))
    where (select public.is_sweepstakes_portal_tester())
       or assignment.id is not null
  )
  , entry_counts as materialized (
    select e.show_id,e.section_id,lower(btrim(coalesce(e.breed,''))) breed,count(*) n
    from public.entries e
    where e.scratched_at is null and lower(coalesce(e.status,'')) <> 'scratched'
    group by e.show_id,e.section_id,lower(btrim(coalesce(e.breed,'')))
  ), artifact_counts as materialized (
    select a.show_id,lower(btrim(coalesce(a.metadata->>'club_name',''))) club,
      coalesce(a.metadata->>'sanction_number','') sanction,
      bool_or(a.artifact_status='generated') generated,
      bool_or(a.artifact_status='failed') failed,
      bool_or(a.artifact_status='queued') queued,
      min(a.id::text) filter(where a.artifact_status='generated') report_id
    from public.show_report_artifacts a
    where a.is_current and a.report_name='sweepstakes_report'
    group by a.show_id,lower(btrim(coalesce(a.metadata->>'club_name',''))),coalesce(a.metadata->>'sanction_number','')
  )
  select distinct
    portal_club.id,
    portal_club.name,
    sanction.show_id,
    show.name,
    show.start_date,
    show.location_name,
    sanction.breed_name,
    sanction.sanction_number,
    sanction.sanctioning_body,
    coalesce(nullif(section.display_name, ''), initcap(section.kind::text) || ' ' || upper(section.letter::text)),
    coalesce(entry.n,0)::integer,
    case when artifact.generated then 'generated'
      when artifact.failed then 'failed' when artifact.queued then 'queued'
      else 'not_ready' end,
    artifact.report_id::uuid
  from assigned_clubs portal_club
  join public.show_sanctions sanction
    on lower(btrim(coalesce(sanction.club_name, ''))) = portal_club.normalized_name
  join public.shows show on show.id = sanction.show_id
  left join public.show_sections section on section.id = sanction.section_id
  left join lateral (
    select sum(e.n) n from entry_counts e
    where e.show_id=sanction.show_id
      and (sanction.section_id is null or e.section_id=sanction.section_id)
      and (upper(btrim(sanction.sanctioning_body))='STATE CLUB'
        or e.breed=lower(btrim(coalesce(sanction.breed_name,''))))
  ) entry on true
  left join artifact_counts artifact on artifact.show_id=sanction.show_id
    and artifact.club=portal_club.normalized_name
    and artifact.sanction=coalesce(sanction.sanction_number,'')
  where show.id not in (
    '9dac84c0-1ee4-48fc-92ab-ccf695635def'::uuid,
    '351c2d5b-da1b-4255-9284-34a120af71a2'::uuid,
    '736f5141-23b9-45ee-b474-ff65d6c88c12'::uuid,
    '0f432fe8-2be2-467a-842f-ff3777436992'::uuid
  );
$$;
