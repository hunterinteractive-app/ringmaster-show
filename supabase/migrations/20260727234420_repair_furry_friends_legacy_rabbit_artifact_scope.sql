-- Legacy State RBA artifacts predate species-scoped closeout artifacts.
-- In combined rabbit/cavy sections the scope resolver cannot infer the
-- species from entries. State RBA is an explicit rabbit-club designation;
-- record that fact and rebuild each affected artifact's canonical metadata,
-- section IDs, scope key, and identity. This deliberately excludes clubs
-- whose names indicate both rabbits and cavies.
with repaired as (
  select
    a.id,
    scope.scope_key,
    scope.section_ids,
    scope.metadata,
    scope.artifact_key
  from public.show_report_artifacts a
  cross join lateral public.resolve_closeout_artifact_scope(
    a.show_id,
    a.finalize_run_id,
    a.report_name,
    a.metadata || jsonb_build_object('species', 'rabbit')
  ) scope
  where a.is_current = true
    and a.report_name in (
      'details_by_breed'::public.report_type,
      'exh_by_breed'::public.report_type,
      'best_display_report'::public.report_type
    )
    and upper(coalesce(a.metadata ->> 'sanctioning_body', '')) = 'STATE CLUB'
    and upper(coalesce(a.metadata ->> 'club_name', '')) like '% RBA%'
    and upper(coalesce(a.metadata ->> 'club_name', '')) not like '%CAVY%'
    and nullif(btrim(a.metadata ->> 'species'), '') is null
    and scope.is_repairable
)
update public.show_report_artifacts a
set
  scope_key = repaired.scope_key,
  section_ids = repaired.section_ids,
  metadata = repaired.metadata,
  artifact_key = repaired.artifact_key
from repaired
where a.id = repaired.id;
