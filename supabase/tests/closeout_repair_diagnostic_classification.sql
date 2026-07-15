-- Transactional regression for legacy failed artifact classification and the
-- final report replacement/requeue workflow. No fixture rows persist.

create extension if not exists pgtap with schema extensions;

begin;
select plan(20);

-- The compact local compatibility baseline omits this production column; the
-- repair function intentionally preserves it on replacement artifacts.
alter table public.show_report_artifacts
  add column if not exists warning_count integer not null default 0;

insert into public.show_finalize_runs (
  id, show_id, run_status, scope_key, scope_label, section_ids, summary
) values (
  'f1000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'completed',
  'repair-trigger-fixture',
  'Repair trigger fixture',
  array[
    '21000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000005',
    '21000000-0000-0000-0000-000000000006',
    '21000000-0000-0000-0000-000000000007'
  ]::uuid[],
  '{}'::jsonb
);

-- These rows model artifacts created before canonical artifact scope existed.
-- Fixture setup alone bypasses triggers; the migration and repair execution do
-- not disable or bypass the production trigger.
set local session_replication_role = replica;

insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation, error_count
)
select
  format('a1000000-0000-0000-0000-%s', lpad(i::text, 12, '0'))::uuid,
  '20000000-0000-0000-0000-000000000004'::uuid,
  'f1000000-0000-0000-0000-000000000001'::uuid,
  'exhibitor_report'::public.report_type,
  'failed'::public.artifact_status,
  jsonb_build_object(
    'exhibitor_id',
      format('e1000000-0000-0000-0000-%s', lpad(i::text, 12, '0')),
    'exhibitor_name', format('Obsolete Exhibitor %s', i),
    'error_category', 'invalid_scope',
    'error_message',
      'The report artifact has incomplete structured scope metadata.'
  ),
  true,
  'legacy-run-wide-scope',
  null,
  format('legacy-exhibitor-%s', i),
  1,
  1
from generate_series(1, 7) i;

insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation, error_count
) values
(
  'a1000000-0000-0000-0000-000000000008',
  '20000000-0000-0000-0000-000000000004',
  'f1000000-0000-0000-0000-000000000001',
  'payback_report',
  'failed',
  jsonb_build_object(
    'run_scope_key', 'repair-trigger-fixture',
    'section_ids', to_jsonb(array[
      '21000000-0000-0000-0000-000000000004',
      '21000000-0000-0000-0000-000000000005',
      '21000000-0000-0000-0000-000000000006',
      '21000000-0000-0000-0000-000000000007'
    ]::uuid[]),
    'error_category', 'statement_timeout'
  ),
  true,
  'legacy-run-wide-scope',
  array[
    '21000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000005',
    '21000000-0000-0000-0000-000000000006',
    '21000000-0000-0000-0000-000000000007'
  ]::uuid[],
  'legacy-payback',
  1,
  1
),
(
  'a1000000-0000-0000-0000-000000000009',
  '20000000-0000-0000-0000-000000000004',
  'f1000000-0000-0000-0000-000000000001',
  'unpaid_balances_report',
  'failed',
  jsonb_build_object(
    'run_scope_key', 'repair-trigger-fixture',
    'section_ids', to_jsonb(array[
      '21000000-0000-0000-0000-000000000004',
      '21000000-0000-0000-0000-000000000005',
      '21000000-0000-0000-0000-000000000006',
      '21000000-0000-0000-0000-000000000007'
    ]::uuid[]),
    'error_category', 'read_only_violation'
  ),
  true,
  'legacy-run-wide-scope',
  array[
    '21000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000005',
    '21000000-0000-0000-0000-000000000006',
    '21000000-0000-0000-0000-000000000007'
  ]::uuid[],
  'legacy-unpaid-balances',
  1,
  1
);

insert into public.show_task_queue (
  show_id, finalize_run_id, scope_key, task_type, task_status,
  report_artifact_id, payload, attempt_count, max_attempts, failed_at,
  error_category, error_message
)
select
  a.show_id,
  a.finalize_run_id,
  a.scope_key,
  'render_report'::public.show_task_type,
  'failed'::public.show_task_status,
  a.id,
  jsonb_build_object('artifact_id', a.id),
  3,
  3,
  now(),
  'worker_lease_expired',
  'Historical failed task'
from public.show_report_artifacts a
where a.finalize_run_id = 'f1000000-0000-0000-0000-000000000001';

set local session_replication_role = origin;

update public.show_report_artifacts
set metadata = metadata || jsonb_build_object(
  'error_message', 'Diagnostic-only update succeeded.'
)
where id = 'a1000000-0000-0000-0000-000000000001';

select is(
  (select metadata ->> 'error_message'
   from public.show_report_artifacts
   where id = 'a1000000-0000-0000-0000-000000000001'),
  'Diagnostic-only update succeeded.',
  'diagnostic-only update succeeds without canonical derivation'
);
select is(
  (select scope_key from public.show_report_artifacts
   where id = 'a1000000-0000-0000-0000-000000000001'),
  'legacy-run-wide-scope',
  'diagnostic-only update preserves legacy scope fields'
);

do $$
begin
  begin
    update public.show_report_artifacts
    set metadata = metadata || jsonb_build_object(
      'exhibitor_id', 'e2000000-0000-0000-0000-000000000001'
    )
    where id = 'a1000000-0000-0000-0000-000000000001';
    raise exception 'identity metadata update bypassed canonical validation';
  exception
    when raise_exception then
      if sqlerrm not like 'Cannot derive canonical closeout artifact scope:%' then
        raise;
      end if;
  end;
end $$;
select pass('identity metadata changes still invoke canonical validation');

do $$
begin
  begin
    update public.show_report_artifacts
    set artifact_status = 'queued'::public.artifact_status
    where id = 'a1000000-0000-0000-0000-000000000001';
    raise exception 'queued transition bypassed canonical validation';
  exception
    when raise_exception then
      if sqlerrm not like 'Cannot derive canonical closeout artifact scope:%' then
        raise;
      end if;
  end;
end $$;
select pass('failed-to-queued transition still invokes canonical validation');

do $$
begin
  begin
    update public.show_report_artifacts
    set scope_key = 'changed-legacy-scope'
    where id = 'a1000000-0000-0000-0000-000000000001';
    raise exception 'scope key update bypassed canonical validation';
  exception
    when raise_exception then
      if sqlerrm not like 'Cannot derive canonical closeout artifact scope:%' then
        raise;
      end if;
  end;
end $$;
select pass('scope-key changes still invoke canonical validation');

create temporary table repair_results (mode text primary key, result jsonb);
insert into repair_results values (
  'dry_run',
  public.repair_final_closeout_report_failures(
    '20000000-0000-0000-0000-000000000004',
    'f1000000-0000-0000-0000-000000000001',
    true
  )
);

select is((select (result ->> 'obsolete_exhibitor_reports')::integer
           from repair_results where mode = 'dry_run'), 7,
          'dry run finds seven obsolete exhibitor reports');
select is((select (result ->> 'repairable_exhibitor_reports')::integer
           from repair_results where mode = 'dry_run'), 0,
          'dry run finds no repairable exhibitor reports');
select is((select (result ->> 'render_reports_to_requeue')::integer
           from repair_results where mode = 'dry_run'), 2,
          'dry run finds two renderer-fixed reports');
select is((select (result ->> 'queued_tasks')::integer
           from repair_results where mode = 'dry_run'), 0,
          'dry run queues no tasks');

insert into repair_results values (
  'write',
  public.repair_final_closeout_report_failures(
    '20000000-0000-0000-0000-000000000004',
    'f1000000-0000-0000-0000-000000000001',
    false
  )
);

select is((select (result ->> 'obsolete_exhibitor_reports')::integer
           from repair_results where mode = 'write'), 7,
          'write repair classifies seven obsolete exhibitor reports');
select is((select (result ->> 'repairable_exhibitor_reports')::integer
           from repair_results where mode = 'write'), 0,
          'write repair replaces no exhibitor reports');
select is((select (result ->> 'render_reports_to_requeue')::integer
           from repair_results where mode = 'write'), 2,
          'write repair replaces two renderer-fixed reports');
select is((select (result ->> 'queued_tasks')::integer
           from repair_results where mode = 'write'), 2,
          'write repair queues exactly two replacement tasks');

select is(
  (select count(*)::integer
   from public.show_report_artifacts
   where finalize_run_id = 'f1000000-0000-0000-0000-000000000001'
     and report_name = 'exhibitor_report'
     and is_current
     and artifact_status = 'failed'
     and metadata ->> 'error_category' = 'missing_exhibitor_entries'
     and metadata ->> 'retryable' = 'false'),
  7,
  'obsolete exhibitor artifacts remain current failed and non-retryable'
);
select is(
  (select count(*)::integer
   from public.show_report_artifacts
   where finalize_run_id = 'f1000000-0000-0000-0000-000000000001'
     and report_name in ('payback_report', 'unpaid_balances_report')
     and is_current
     and artifact_status = 'queued'
     and scope_key = public.closeout_artifact_scope_key(
       show_id, report_name, section_ids, metadata
     )
     and metadata ->> 'scope_key' = scope_key
     and metadata -> 'section_ids' = to_jsonb(section_ids)),
  2,
  'Paybacks and Unpaid Balances have canonical current replacements'
);
select is(
  (select count(*)::integer
   from public.show_report_artifacts
   where id in (
     'a1000000-0000-0000-0000-000000000008',
     'a1000000-0000-0000-0000-000000000009'
   ) and not is_current),
  2,
  'old renderer-failed artifacts are preserved as superseded history'
);
select is(
  (select count(*)::integer
   from public.show_task_queue q
   join public.show_report_artifacts a on a.id = q.report_artifact_id
   where a.finalize_run_id = 'f1000000-0000-0000-0000-000000000001'
     and a.is_current
     and q.task_status in ('queued', 'running')),
  2,
  'only two replacement tasks are active'
);
select is(
  (select count(*)::integer
   from (
     select q.report_artifact_id, q.task_type
     from public.show_task_queue q
     join public.show_report_artifacts a on a.id = q.report_artifact_id
     where a.finalize_run_id = 'f1000000-0000-0000-0000-000000000001'
       and q.task_status in ('queued', 'running')
     group by q.report_artifact_id, q.task_type
     having count(*) > 1
   ) duplicates),
  0,
  'no artifact has duplicate active render tasks'
);
select is(
  (select count(*)::integer
   from public.show_task_queue q
   where q.report_artifact_id in (
     select a.id from public.show_report_artifacts a
     where a.finalize_run_id = 'f1000000-0000-0000-0000-000000000001'
       and a.report_name = 'exhibitor_report'
       and a.is_current
   ) and q.task_status in ('queued', 'running')),
  0,
  'obsolete exhibitor artifacts are not requeued'
);
select is(
  (select count(*)::integer
   from public.show_task_queue
   where finalize_run_id = 'f1000000-0000-0000-0000-000000000001'
     and task_status = 'failed'),
  9,
  'all original failed task history remains available'
);

select * from finish();
rollback;
