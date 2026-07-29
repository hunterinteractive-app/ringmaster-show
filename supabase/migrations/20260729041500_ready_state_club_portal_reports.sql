-- State clubs receive a different set of reports than breed clubs. Make their
-- portal row ready when one of those delivered files is available.
alter function public.list_sweepstakes_portal_shows()
  rename to list_sweepstakes_portal_shows_sorted_base;

revoke all on function public.list_sweepstakes_portal_shows_sorted_base() from public;
revoke all on function public.list_sweepstakes_portal_shows_sorted_base() from authenticated;

create function public.list_sweepstakes_portal_shows()
returns table (
  portal_club_id uuid, club_name text, show_id uuid, show_name text,
  show_date date, show_location text, breed_name text, sanction_number text,
  sanctioning_body text, section_label text, eligible_entry_count integer,
  report_status text, report_artifact_id uuid
)
language sql stable security definer set search_path = ''
as $$
  select
    base.portal_club_id, base.club_name, base.show_id, base.show_name,
    base.show_date, base.show_location, base.breed_name, base.sanction_number,
    base.sanctioning_body, base.section_label, base.eligible_entry_count,
    case when state_artifact.id is not null then 'generated' else base.report_status end,
    coalesce(state_artifact.id, base.report_artifact_id)
  from public.list_sweepstakes_portal_shows_sorted_base() base
  left join lateral (
    select artifact.id
    from public.show_report_artifacts artifact
    where upper(btrim(base.sanctioning_body)) = 'STATE CLUB'
      and artifact.show_id = base.show_id
      and artifact.is_current
      and artifact.artifact_status = 'generated'::public.artifact_status
      and artifact.report_name in (
        'details_by_breed'::public.report_type,
        'exh_by_breed'::public.report_type,
        'best_display_report'::public.report_type
      )
      and lower(btrim(coalesce(artifact.metadata ->> 'club_name', ''))) = lower(btrim(base.club_name))
      and coalesce(artifact.metadata ->> 'sanction_number', base.sanction_number, '') = coalesce(base.sanction_number, '')
      and coalesce(artifact.storage_path, '') <> ''
    order by artifact.generated_at desc nulls last, artifact.created_at desc
    limit 1
  ) state_artifact on true;
$$;

revoke all on function public.list_sweepstakes_portal_shows() from public;
grant execute on function public.list_sweepstakes_portal_shows() to authenticated;
