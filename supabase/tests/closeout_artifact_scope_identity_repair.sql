-- Transactional regression for canonical artifact identity reuse during scope
-- repair. No fixture rows persist.

create extension if not exists pgtap with schema extensions;

begin;
select plan(19);

alter table public.show_report_artifacts
  add column if not exists warning_count integer not null default 0;

insert into public.show_finalize_runs (
  id, show_id, run_status, scope_key, scope_label, section_ids, summary
) values
(
  'f3000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004', 'completed',
  'identity-self', 'Identity self',
  array['21000000-0000-0000-0000-000000000004']::uuid[], '{}'::jsonb
),
(
  'f3000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000004', 'completed',
  'identity-owner', 'Identity owner',
  array['21000000-0000-0000-0000-000000000004']::uuid[], '{}'::jsonb
),
(
  'f3000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000004', 'completed',
  'identity-new', 'Identity new',
  array['21000000-0000-0000-0000-000000000004']::uuid[], '{}'::jsonb
),
(
  'f3000000-0000-0000-0000-000000000004',
  '20000000-0000-0000-0000-000000000004', 'completed',
  'identity-regenerate', 'Identity regenerate',
  array['21000000-0000-0000-0000-000000000004']::uuid[], '{}'::jsonb
);

create temporary table resolved_scopes as
select f.id finalize_run_id, r.*
from public.show_finalize_runs f
cross join lateral public.resolve_closeout_artifact_scope(
  f.show_id,
  f.id,
  'judge_report'::public.report_type,
  jsonb_build_object(
    'run_scope_key', f.scope_key,
    'error_category', 'invalid_scope',
    'error_message', 'legacy invalid scope'
  )
) r
where f.id in (
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000002',
  'f3000000-0000-0000-0000-000000000003',
  'f3000000-0000-0000-0000-000000000004'
);

select ok(bool_and(is_repairable), 'all identity repair fixtures resolve canonically')
from resolved_scopes;

set local session_replication_role = replica;

-- The failed source already owns its resolved artifact key.
insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation, error_count,
  storage_bucket, storage_path, file_name, mime_type, file_size_bytes,
  file_hash_sha256, generated_at
)
select
  'a3000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004', finalize_run_id,
  'judge_report', 'failed',
  metadata || jsonb_build_object(
    'error_category', 'invalid_scope', 'error_message', 'legacy invalid scope'
  ),
  true, 'legacy-self-scope', null, artifact_key, 2, 1,
  'legacy-bucket', 'legacy/self.pdf', 'self.pdf', 'application/pdf', 100,
  'self-hash', now()
from resolved_scopes
where finalize_run_id = 'f3000000-0000-0000-0000-000000000001';

-- A non-current row already owns the resolved key.
insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, superseded_at, scope_key, section_ids, artifact_key, generation,
  error_count, storage_path, file_name
)
select
  'a3000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000004', finalize_run_id,
  'judge_report', 'generated', metadata, false, now(), scope_key, section_ids,
  artifact_key, 4, 0, 'legacy/owner.pdf', 'owner.pdf'
from resolved_scopes
where finalize_run_id = 'f3000000-0000-0000-0000-000000000002';

insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation, error_count
)
select
  'a3000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000004', finalize_run_id,
  'judge_report', 'failed',
  metadata || jsonb_build_object(
    'error_category', 'invalid_scope', 'error_message', 'legacy invalid scope'
  ),
  true, 'legacy-owner-source', null, 'legacy-owner-source', 1, 1
from resolved_scopes
where finalize_run_id = 'f3000000-0000-0000-0000-000000000002';

-- No row owns the resolved key, so this source requires a replacement.
insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation, error_count
)
select
  'a3000000-0000-0000-0000-000000000004',
  '20000000-0000-0000-0000-000000000004', finalize_run_id,
  'judge_report', 'failed',
  metadata || jsonb_build_object(
    'error_category', 'invalid_scope', 'error_message', 'legacy invalid scope'
  ),
  true, 'legacy-new-source', null, 'legacy-new-source', 3, 1
from resolved_scopes
where finalize_run_id = 'f3000000-0000-0000-0000-000000000003';

-- Regenerate All must execute the same-key repair without a unique violation.
insert into public.show_report_artifacts (
  id, show_id, finalize_run_id, report_name, artifact_status, metadata,
  is_current, scope_key, section_ids, artifact_key, generation, error_count
)
select
  'a3000000-0000-0000-0000-000000000005',
  '20000000-0000-0000-0000-000000000004', finalize_run_id,
  'judge_report', 'failed',
  metadata || jsonb_build_object(
    'error_category', 'invalid_scope', 'error_message', 'legacy invalid scope'
  ),
  true, 'legacy-regenerate-scope', null, artifact_key, 1, 1
from resolved_scopes
where finalize_run_id = 'f3000000-0000-0000-0000-000000000004';

set local session_replication_role = origin;

create temporary table repair_results (finalize_run_id uuid primary key, result jsonb);
insert into repair_results
select id, public.repair_closeout_artifact_scopes(show_id, id)
from public.show_finalize_runs
where id in (
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000002',
  'f3000000-0000-0000-0000-000000000003'
)
order by id;

select is((select count(*)::integer from public.show_report_artifacts
           where finalize_run_id = 'f3000000-0000-0000-0000-000000000001'),
          1, 'same-key repair does not insert a replacement');
select is((select artifact_status::text from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000001'),
          'queued', 'same-key repair queues the failed source in place');
select is((select generation from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000001'),
          3, 'same-key repair advances generation once');
select ok((select is_current and error_count = 0 and generated_at is null
                  and file_name is null and mime_type is null
                  and file_size_bytes is null and file_hash_sha256 is null
                  and not (metadata ? 'error_category')
                  and not (metadata ? 'error_message')
           from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000001'),
          'same-key repair resets render output and diagnostic fields');
select is((select (result ->> 'repaired_count')::integer from repair_results
           where finalize_run_id = 'f3000000-0000-0000-0000-000000000001'),
          1, 'same-key repair increments repaired count');

select is((select count(*)::integer from public.show_report_artifacts
           where finalize_run_id = 'f3000000-0000-0000-0000-000000000002'),
          2, 'non-current owner repair does not insert a duplicate');
select ok((select is_current and artifact_status = 'queued' and generation = 5
                  and superseded_at is null and file_name is null
           from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000002'),
          'non-current identity owner is deterministically reactivated and reset');
select ok((select not is_current and superseded_at is not null
           from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000003'),
          'failed source is superseded when another row owns the identity');
select is((select count(*)::integer from public.show_report_artifacts a
           join resolved_scopes r on r.finalize_run_id = a.finalize_run_id
                                 and r.artifact_key = a.artifact_key
           where a.finalize_run_id = 'f3000000-0000-0000-0000-000000000002'),
          1, 'non-current owner branch preserves one row per run identity');

select is((select count(*)::integer from public.show_report_artifacts
           where finalize_run_id = 'f3000000-0000-0000-0000-000000000003'),
          2, 'unowned resolved key inserts exactly one replacement');
select ok((select not is_current from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000004'),
          'new-key replacement supersedes the failed source');
select is((select count(*)::integer from public.show_report_artifacts a
           join resolved_scopes r on r.finalize_run_id = a.finalize_run_id
                                 and r.artifact_key = a.artifact_key
           where a.finalize_run_id = 'f3000000-0000-0000-0000-000000000003'
             and a.is_current and a.artifact_status = 'queued'),
          1, 'new-key replacement is the queued current artifact');

create temporary table regenerate_result as
select public.requeue_closeout_render_tasks(
  '20000000-0000-0000-0000-000000000004',
  'f3000000-0000-0000-0000-000000000004',
  'identity-regenerate',
  true
) result;

select pass('regenerate_all completes without duplicate-key failure');
select is((select count(*)::integer from public.show_report_artifacts
           where finalize_run_id = 'f3000000-0000-0000-0000-000000000004'),
          1, 'regenerate_all same-key repair keeps one artifact');
select is((select artifact_status::text from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000005'),
          'queued', 'regenerate_all leaves the repaired artifact queued');
select is((select generation from public.show_report_artifacts
           where id = 'a3000000-0000-0000-0000-000000000005'),
          3, 'regenerate_all advances repair and regeneration generations');
select is((select count(*)::integer from public.show_task_queue
           where report_artifact_id = 'a3000000-0000-0000-0000-000000000005'
             and task_status = 'queued'),
          1, 'regenerate_all has exactly one queued render task');
select is((select (result ->> 'repaired_count')::integer from regenerate_result),
          1, 'regenerate_all reports the repaired artifact');

select * from finish();
rollback;
