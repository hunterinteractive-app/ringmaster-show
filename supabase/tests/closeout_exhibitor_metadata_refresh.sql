-- Exhibitor corrections must replace stale delivery metadata during both
-- Requeue All (run-wide scope) and single-artifact regeneration.

create extension if not exists pgtap with schema extensions;

begin;
select plan(8);

insert into public.exhibitors (
  id, display_name, first_name, last_name, email
) values (
  'e8000000-0000-0000-0000-000000000001',
  'Madison Kohnen',
  'Madison',
  'Kohnen',
  'madison.kohnen@example.test'
);

insert into public.show_finalize_runs (
  id, show_id, run_status, results_version, scope_key, scope_label,
  section_ids, summary, started_at, completed_at
) values (
  'f8000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'completed',
  1,
  'finalize-run-scope',
  'Rabbit Open A',
  array['21000000-0000-0000-0000-000000000004']::uuid[],
  '{}'::jsonb,
  now(),
  now()
);

insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key
) values
(
  'a8000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'f8000000-0000-0000-0000-000000000001',
  'exhibitor_report',
  'generated',
  jsonb_build_object(
    'exhibitor_id', 'e8000000-0000-0000-0000-000000000001',
    'exhibitor_name', 'Madison Kennedy',
    'exhibitor_email', 'stale@example.test',
    'email', 'stale@example.test',
    'species', 'rabbit',
    'delivery_type', 'exhibitor'
  ),
  true,
  'artifact-specific-exhibitor-scope',
  array['21000000-0000-0000-0000-000000000004']::uuid[],
  'refresh-test-exhibitor-report'
),
(
  'a8000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000004',
  'f8000000-0000-0000-0000-000000000001',
  'legs',
  'generated',
  jsonb_build_object(
    'exhibitor_id', 'e8000000-0000-0000-0000-000000000001',
    'exhibitor_name', 'Madison Kennedy',
    'species', 'rabbit',
    'delivery_type', 'exhibitor'
  ),
  true,
  'artifact-specific-legs-scope',
  array['21000000-0000-0000-0000-000000000004']::uuid[],
  'refresh-test-legs'
),
(
  'a8000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000004',
  'f8000000-0000-0000-0000-000000000001',
  'checkin_sheet',
  'generated',
  jsonb_build_object(
    'exhibitor_id', 'e8000000-0000-0000-0000-000000000001',
    'exhibitor_name', 'Madison Kennedy',
    'species', 'rabbit',
    'delivery_type', 'exhibitor'
  ),
  true,
  'artifact-specific-checkin-scope',
  array['21000000-0000-0000-0000-000000000004']::uuid[],
  'refresh-test-checkin'
);

create temporary table refresh_results(payload jsonb);
insert into refresh_results
select public.refresh_closeout_exhibitor_artifact_metadata(
  '20000000-0000-0000-0000-000000000004',
  'f8000000-0000-0000-0000-000000000001',
  'finalize-run-scope',
  null
);

select is(
  (select (payload ->> 'refreshed_count')::integer from refresh_results),
  3,
  'Requeue All refreshes every exhibitor artifact despite individual scope keys'
);
select is(
  (select count(*)::integer from public.show_report_artifacts
   where finalize_run_id = 'f8000000-0000-0000-0000-000000000001'
     and metadata ->> 'exhibitor_name' = 'Madison Kohnen'),
  3,
  'all exhibitor artifact types receive the corrected name'
);
select is(
  (select count(*)::integer from public.show_report_artifacts
   where finalize_run_id = 'f8000000-0000-0000-0000-000000000001'
     and metadata ->> 'exhibitor_email' = 'madison.kohnen@example.test'),
  3,
  'all exhibitor artifact types receive the corrected email'
);
select is(
  (select count(*)::integer from public.show_report_artifacts
   where finalize_run_id = 'f8000000-0000-0000-0000-000000000001'
     and metadata ->> 'email' = 'madison.kohnen@example.test'),
  3,
  'the delivery email alias is refreshed with the corrected email'
);

update public.exhibitors
set display_name = 'Madison Kohnen Revised'
where id = 'e8000000-0000-0000-0000-000000000001';

truncate refresh_results;
insert into refresh_results
select public.refresh_closeout_exhibitor_artifact_metadata(
  '20000000-0000-0000-0000-000000000004',
  'f8000000-0000-0000-0000-000000000001',
  'artifact-specific-legs-scope',
  'a8000000-0000-0000-0000-000000000002'
);

select is(
  (select (payload ->> 'refreshed_count')::integer from refresh_results),
  1,
  'single-report regeneration refreshes exactly the requested artifact'
);
select is(
  (select metadata ->> 'exhibitor_name' from public.show_report_artifacts
   where id = 'a8000000-0000-0000-0000-000000000002'),
  'Madison Kohnen Revised',
  'single-report regeneration uses the latest exhibitor name'
);
select is(
  (select metadata ->> 'exhibitor_name' from public.show_report_artifacts
   where id = 'a8000000-0000-0000-0000-000000000001'),
  'Madison Kohnen',
  'single-report regeneration leaves other artifacts unchanged'
);
select is(
  (public.refresh_closeout_exhibitor_artifact_metadata(
    '20000000-0000-0000-0000-000000000004',
    'f8000000-0000-0000-0000-000000000001',
    'wrong-finalize-run-scope',
    null
  ) ->> 'refreshed_count')::integer,
  0,
  'Requeue All refuses an unvalidated finalize-run scope'
);

select * from finish();
rollback;
