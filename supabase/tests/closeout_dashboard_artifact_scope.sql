-- The scoped dashboard must follow the selected finalize run while artifacts
-- retain their canonical artifact-specific scope keys. Fixture rows roll back.

create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

insert into public.show_finalize_runs (
  id, show_id, run_status, scope_key, scope_label, section_ids, summary,
  started_at, completed_at
) values (
  'f2000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'completed',
  'dashboard-selected-run',
  'Rabbit Open A',
  array['21000000-0000-0000-0000-000000000004']::uuid[],
  '{}'::jsonb,
  '2026-07-16 01:00:00+00',
  '2026-07-16 01:01:00+00'
), (
  'f2000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000004',
  'completed',
  'dashboard-other-run',
  'Cavy Open B',
  array['21000000-0000-0000-0000-000000000006']::uuid[],
  '{}'::jsonb,
  '2026-07-16 00:00:00+00',
  '2026-07-16 00:01:00+00'
);

set local session_replication_role = replica;

insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation,
  storage_bucket, storage_path, file_name, generated_at, created_at
)
select
  format('a2000000-0000-0000-0000-%s', lpad(i::text, 12, '0'))::uuid,
  '20000000-0000-0000-0000-000000000004'::uuid,
  'f2000000-0000-0000-0000-000000000001'::uuid,
  'judge_report'::public.report_type,
  case when i = 1 then 'failed'::public.artifact_status
       else 'generated'::public.artifact_status end,
  jsonb_build_object(
    'run_scope_key', 'dashboard-selected-run',
    'section_id', '21000000-0000-0000-0000-000000000004',
    'section_ids', jsonb_build_array(
      '21000000-0000-0000-0000-000000000004'
    ),
    'scope', 'OPEN',
    'show_letter', 'A',
    'judge_id', format('judge-%s', i)
  ) || case when i = 1 then jsonb_build_object(
    'error_category', 'render_error',
    'error_message', 'The report could not be rendered.',
    'last_error',
      'Exception: ARBA report is blocked until required closeout data is complete: Best In Show Rabbit owner city/state.'
  ) else '{}'::jsonb end,
  true,
  format('artifact-specific-scope-%s', i),
  array['21000000-0000-0000-0000-000000000004']::uuid[],
  format('dashboard-artifact-%s', i),
  1,
  'reports',
  format('dashboard/%s.pdf', i),
  format('judge-%s.pdf', i),
  '2026-07-16 01:02:00+00'::timestamptz + i * interval '1 second',
  '2026-07-16 01:01:00+00'::timestamptz + i * interval '1 second'
from generate_series(1, 205) i;

insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation
) values (
  'a2000000-0000-0000-0000-000000000999',
  '20000000-0000-0000-0000-000000000004',
  'f2000000-0000-0000-0000-000000000002',
  'judge_report',
  'failed',
  '{"run_scope_key":"dashboard-other-run"}'::jsonb,
  true,
  'other-artifact-scope',
  array['21000000-0000-0000-0000-000000000006']::uuid[],
  'dashboard-other-artifact',
  1
);

insert into public.show_task_queue (
  show_id, finalize_run_id, scope_key, task_type, task_status,
  report_artifact_id, payload, attempt_count, max_attempts, completed_at
)
select
  a.show_id,
  a.finalize_run_id,
  a.scope_key,
  'render_report'::public.show_task_type,
  'completed'::public.show_task_status,
  a.id,
  jsonb_build_object('artifact_id', a.id),
  1,
  3,
  now()
from public.show_report_artifacts a
where a.id in (
  'a2000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000002'
);

set local session_replication_role = origin;

create temporary table dashboard_pages (page integer primary key, payload jsonb);
insert into dashboard_pages values (
  1,
  public.get_closeout_dashboard_scoped(
    '20000000-0000-0000-0000-000000000004',
    'dashboard-selected-run',
    array['21000000-0000-0000-0000-000000000004']::uuid[],
    200,
    0,
    null
  )
), (
  2,
  public.get_closeout_dashboard_scoped(
    '20000000-0000-0000-0000-000000000004',
    'dashboard-selected-run',
    array['21000000-0000-0000-0000-000000000004']::uuid[],
    200,
    200,
    null
  )
);

select is(
  (select payload #>> '{latest_finalize,id}' from dashboard_pages where page = 1),
  'f2000000-0000-0000-0000-000000000001',
  'dashboard selects the exact finalize run'
);
select is(
  (select jsonb_array_length(payload -> 'reports') from dashboard_pages where page = 1),
  200,
  'first bounded artifact page is full'
);
select ok(
  (select (payload #>> '{artifact_page,has_more}')::boolean from dashboard_pages where page = 1),
  'first page advertises additional artifact-specific rows'
);
select is(
  (select jsonb_array_length(payload -> 'reports') from dashboard_pages where page = 2),
  5,
  'second page returns the remaining artifacts'
);
select is(
  (select (payload #>> '{artifact_counts,total}')::integer from dashboard_pages where page = 1),
  205,
  'artifact counts exclude other finalize runs'
);
select is(
  (select (payload #>> '{task_counts,completed}')::integer from dashboard_pages where page = 1),
  2,
  'task counts follow the selected finalize run despite artifact scope keys'
);
select ok(
  (select (payload -> 'reports' -> 0) ?& array[
    'id', 'show_id', 'finalize_run_id', 'report_name', 'artifact_status',
    'generated_at', 'is_current', 'scope_key', 'section_ids', 'metadata',
    'storage_bucket', 'storage_path', 'file_name', 'error_count',
    'generation', 'created_at'
  ] from dashboard_pages where page = 1),
  'report payload contains complete identity, scope, status, ordering, and storage fields'
);
select is(
  (select count(*)::integer
   from dashboard_pages p
   cross join lateral jsonb_array_elements(p.payload -> 'reports') report
   where report ->> 'scope_key' = 'other-artifact-scope'),
  0,
  'other-run artifacts never leak into either page'
);

select is(
  (select payload #>> '{review_reports,0,metadata_last_error}'
   from dashboard_pages where page = 1),
  'Exception: ARBA report is blocked until required closeout data is complete: Best In Show Rabbit owner city/state.',
  'review payload exposes metadata last_error separately'
);
select is(
  (select payload #>> '{review_reports,0,metadata_error_message}'
   from dashboard_pages where page = 1),
  'The report could not be rendered.',
  'review payload exposes metadata error_message separately'
);

select * from finish();
rollback;
