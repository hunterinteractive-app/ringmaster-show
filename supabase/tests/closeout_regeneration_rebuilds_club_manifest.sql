-- Regenerate All must reconcile club artifacts with sanctions added after the
-- original finalize run. All fixture changes are rolled back.

create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

insert into public.show_finalize_runs (
  id,
  show_id,
  run_status,
  results_version,
  scope_key,
  scope_label,
  section_ids,
  summary,
  started_at,
  completed_at
) values (
  'f5000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'completed',
  1,
  '20000000-0000-0000-0000-000000000004:21000000-0000-0000-0000-000000000004,21000000-0000-0000-0000-000000000005',
  'Rabbit Open A + Youth A',
  array[
    '21000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000005'
  ]::uuid[],
  jsonb_build_object('manifest_version', 2),
  now(),
  now()
);

-- Build the manifest as it existed when only Mini Rex was sanctioned.
select public.rebuild_closeout_club_report_manifest(
  '20000000-0000-0000-0000-000000000004',
  'f5000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004:21000000-0000-0000-0000-000000000004,21000000-0000-0000-0000-000000000005',
  'rabbit'
);

select is(
  (
    select count(*)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000001'
      and artifact.is_current = true
      and artifact.metadata ->> 'club_name' = 'Synthetic Mini Rex Club'
  ),
  2,
  'initial finalized manifest contains two Mini Rex club reports'
);

-- Simulate sanction metadata changing and a second sanctioned club being
-- added after finalization.
update public.show_sanctions
set sanction_number = 'MR-UPDATED',
    sweepstakes_email = 'updated-club@example.test',
    updated_at = now()
where show_id = '20000000-0000-0000-0000-000000000004'
  and section_id = '21000000-0000-0000-0000-000000000004'
  and club_name = 'Synthetic Mini Rex Club';

insert into public.show_sanctions (
  show_id,
  section_id,
  breed_name,
  club_name,
  sanction_number,
  sanctioning_body,
  sweepstakes_email,
  request_status
) values (
  '20000000-0000-0000-0000-000000000004',
  '21000000-0000-0000-0000-000000000005',
  'Jersey Wooly',
  'Synthetic Jersey Wooly Club',
  'JW-NEW',
  'NATIONAL CLUB',
  'jersey-club@example.test',
  'received'
);

-- Add an artifact whose sanction no longer exists. It must become historical
-- rather than remain sendable.
with resolved as (
  select *
  from public.resolve_closeout_artifact_scope(
    '20000000-0000-0000-0000-000000000004',
    'f5000000-0000-0000-0000-000000000001',
    'sweepstakes_report'::public.report_type,
    jsonb_build_object(
      'section_id', '21000000-0000-0000-0000-000000000004',
      'scope', 'OPEN',
      'show_letter', 'A',
      'breed_name', 'Mini Rex',
      'club_name', 'Removed Rabbit Club',
      'species', 'rabbit',
      'sweepstakes_email', 'removed@example.test',
      'sanctioning_body', 'NATIONAL CLUB',
      'delivery_type', 'club'
    )
  )
insert into public.show_report_artifacts (
  id,
  show_id,
  finalize_run_id,
  report_name,
  artifact_status,
  metadata,
  is_current,
  scope_key,
  section_ids,
  artifact_key
)
select
  'a5000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'f5000000-0000-0000-0000-000000000001',
  'sweepstakes_report',
  'generated',
  metadata,
  true,
  scope_key,
  section_ids,
  artifact_key
from resolved;

create temporary table regeneration_results(payload jsonb);
insert into regeneration_results
select public.requeue_closeout_render_tasks_for_species(
  '20000000-0000-0000-0000-000000000004',
  'f5000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004:21000000-0000-0000-0000-000000000004,21000000-0000-0000-0000-000000000005',
  true,
  'rabbit'
);

select is(
  (select (payload #>> '{club_manifest,expected_count}')::integer
   from regeneration_results),
  4,
  'Regenerate All discovers four reports across both current sanctions'
);
select is(
  (select (payload #>> '{club_manifest,inserted_count}')::integer
   from regeneration_results),
  2,
  'two reports are inserted for the post-finalization sanction'
);
select is(
  (
    select count(*)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000001'
      and artifact.is_current = true
      and artifact.metadata ->> 'delivery_type' = 'club'
  ),
  4,
  'only the four reports implied by current sanctions remain current'
);
select is(
  (
    select count(*)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000001'
      and artifact.is_current = true
      and artifact.metadata ->> 'club_name' =
        'Synthetic Jersey Wooly Club'
  ),
  2,
  'the newly sanctioned Jersey Wooly club receives both required reports'
);
select is(
  (
    select min(artifact.metadata ->> 'sweepstakes_email')
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000001'
      and artifact.is_current = true
      and artifact.metadata ->> 'club_name' = 'Synthetic Mini Rex Club'
  ),
  'updated-club@example.test',
  'existing club artifacts receive the current recipient email'
);
select is(
  (
    select min(artifact.metadata ->> 'sanction_number')
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000001'
      and artifact.is_current = true
      and artifact.metadata ->> 'club_name' = 'Synthetic Mini Rex Club'
  ),
  'MR-UPDATED',
  'existing club artifacts receive the current sanction number'
);
select ok(
  not (
    select artifact.is_current
    from public.show_report_artifacts artifact
    where artifact.id = 'a5000000-0000-0000-0000-000000000001'
  ),
  'an artifact with no current sanction is retained only as history'
);
select is(
  (
    select count(*)::integer
    from public.show_task_queue task
    join public.show_report_artifacts artifact
      on artifact.id = task.report_artifact_id
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000001'
      and artifact.is_current = true
      and artifact.metadata ->> 'delivery_type' = 'club'
      and task.task_status = 'queued'
  ),
  4,
  'all rebuilt current club reports are queued for rendering'
);

-- A second regeneration must refresh, not duplicate, the rebuilt manifest.
truncate regeneration_results;
insert into regeneration_results
select public.requeue_closeout_render_tasks_for_species(
  '20000000-0000-0000-0000-000000000004',
  'f5000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004:21000000-0000-0000-0000-000000000004,21000000-0000-0000-0000-000000000005',
  true,
  'rabbit'
);

select is(
  (select (payload #>> '{club_manifest,inserted_count}')::integer
   from regeneration_results),
  0,
  'rebuilding the same current sanctions is idempotent'
);
select is(
  (
    select count(*)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000001'
      and artifact.is_current = true
      and artifact.metadata ->> 'delivery_type' = 'club'
  ),
  4,
  'a repeated regeneration does not duplicate current club artifacts'
);

select * from finish();
rollback;
