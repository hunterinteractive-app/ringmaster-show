-- These two legacy Pennsylvania State RBA Youth A artifacts predate
-- species-scoped closeout artifacts.  Youth A contains both rabbits and
-- cavies, so the scope resolver cannot infer a species from entries.
-- The sanctioned club is a rabbit club; record that fact explicitly and
-- rebuild each artifact's canonical metadata, section IDs, scope key, and
-- identity.
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
  where a.id in (
    '3765a970-8d9f-4a2c-979c-1d55d3212b7a'::uuid,
    'd1184af2-a1de-430b-8704-b95ec97adfa2'::uuid
  )
    and a.show_id = 'c5d96a62-ab5a-4775-9e32-aa60ad383e7c'::uuid
    and a.is_current = true
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
