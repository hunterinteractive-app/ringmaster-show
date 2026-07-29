-- Some ARBA report jobs remain in a warning/deferred state after their PDF has
-- already been produced and delivered.  A stored current PDF is safe to expose
-- as ready in the chair portal.
alter function public.list_sweepstakes_portal_shows()
  rename to list_sweepstakes_portal_shows_arba_status_base;

revoke all on function public.list_sweepstakes_portal_shows_arba_status_base() from public;
revoke all on function public.list_sweepstakes_portal_shows_arba_status_base() from authenticated;

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
    case
      when delivered_arba.id is not null then 'generated'
      else base.report_status
    end,
    coalesce(delivered_arba.id, base.report_artifact_id)
  from public.list_sweepstakes_portal_shows_arba_status_base() base
  left join public.show_sections matched_section
    on lower(base.club_name) = 'arba'
   and matched_section.show_id = base.show_id
   and coalesce(nullif(matched_section.display_name, ''), initcap(matched_section.kind::text) || ' ' || upper(matched_section.letter::text)) = base.section_label
  left join lateral (
    select artifact.id
    from public.show_report_artifacts artifact
    where lower(base.club_name) = 'arba'
      and artifact.show_id = base.show_id
      and artifact.report_name = 'arba_report'::public.report_type
      and artifact.is_current
      and artifact.artifact_status in ('generated'::public.artifact_status, 'warning'::public.artifact_status)
      and coalesce(artifact.storage_path, '') <> ''
      and coalesce(artifact.metadata ->> 'section_id', '') = coalesce(matched_section.id::text, '')
    order by artifact.generated_at desc nulls last, artifact.created_at desc
    limit 1
  ) delivered_arba on true;
$$;

revoke all on function public.list_sweepstakes_portal_shows() from public;
grant execute on function public.list_sweepstakes_portal_shows() to authenticated;
