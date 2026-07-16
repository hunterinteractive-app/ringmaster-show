-- Artifact scope keys are intentionally artifact-specific. The dashboard is
-- selected by the finalize run's run-wide scope, so artifacts and tasks must
-- be joined through that finalize_run_id rather than compared to p_scope_key.
create or replace function public.get_closeout_dashboard_scoped_without_activity(
  p_show_id uuid,
  p_scope_key text,
  p_section_ids uuid[],
  p_artifact_limit integer default 100,
  p_artifact_offset integer default 0,
  p_report_name public.report_type default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  with requested as (
    select
      greatest(1, least(coalesce(p_artifact_limit, 100), 200)) page_limit,
      greatest(0, coalesce(p_artifact_offset, 0)) page_offset
  ),
  show_row as (
    select s.id, s.name, s.results_version, s.results_last_changed_at
    from public.shows s where s.id = p_show_id
  ),
  state_row as (
    select cs.* from public.show_closeout_state cs where cs.show_id = p_show_id
  ),
  selected_run as (
    select f.id, f.run_status, f.started_at, f.completed_at, f.scope_key,
           f.scope_label, f.section_ids
    from public.show_finalize_runs f
    where f.show_id = p_show_id
      and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  current_artifacts as (
    select a.*
    from public.show_report_artifacts a
    join selected_run r on r.id = a.finalize_run_id
    where a.show_id = p_show_id
      and a.is_current = true
  ),
  artifact_counts as (
    select
      count(*)::integer total,
      count(*) filter (where a.artifact_status = 'generated')::integer generated,
      count(*) filter (where a.artifact_status = 'queued')::integer queued,
      count(*) filter (where a.artifact_status = 'failed')::integer failed,
      coalesce(
        (select jsonb_object_agg(counts.report_name, counts.report_count)
         from (
           select report_name, count(*)::integer report_count
           from current_artifacts
           group by report_name
         ) counts),
        '{}'::jsonb
      ) by_report
    from current_artifacts a
  ),
  task_counts as (
    select
      count(*) filter (where q.task_status = 'queued')::integer queued,
      count(*) filter (where q.task_status = 'running')::integer running,
      count(*) filter (where q.task_status = 'failed')::integer failed,
      count(*) filter (where q.task_status = 'completed')::integer completed,
      (
        count(*) filter (
          where q.task_status = 'failed'
            and q.task_type = 'render_report'
            and q.attempt_count < q.max_attempts
        ) +
        (select count(*)
         from current_artifacts a
         where a.artifact_status in ('queued', 'failed')
           and not exists (
             select 1 from public.show_task_queue missing_q
             where missing_q.report_artifact_id = a.id
               and missing_q.task_type = 'render_report'
           ))
      )::integer remaining
    from public.show_task_queue q
    join selected_run r on r.id = q.finalize_run_id
    join current_artifacts a on a.id = q.report_artifact_id
    where q.show_id = p_show_id
      and q.task_type = 'render_report'::public.show_task_type
  ),
  filtered_artifact_count as (
    select count(*)::integer total
    from current_artifacts a
    where p_report_name is null or a.report_name = p_report_name
  ),
  artifact_page as (
    select a.*
    from current_artifacts a
    cross join requested req
    where p_report_name is null or a.report_name = p_report_name
    order by a.report_name, a.created_at, a.id
    limit (select page_limit from requested)
    offset (select page_offset from requested)
  )
  select jsonb_build_object(
    'dashboard', jsonb_build_object(
      'show_id', s.id,
      'show_name', s.name,
      'results_version', coalesce(s.results_version, 0),
      'results_last_changed_at', s.results_last_changed_at,
      'closeout', jsonb_build_object(
        'sync_status', coalesce(cs.sync_status::text, 'not_ready'),
        'is_points_stale', coalesce(cs.is_points_stale, true),
        'is_reports_stale', coalesce(ac.queued + ac.failed > 0, true),
        'has_warnings', coalesce(cs.has_warnings, false),
        'has_blocking_errors', coalesce(cs.has_blocking_errors, false),
        'is_archived', coalesce(cs.is_archived, false),
        'warning_count', coalesce(cs.warning_count, 0),
        'error_count', coalesce(cs.error_count, 0),
        'blocking_error_count', coalesce(cs.blocking_error_count, 0),
        'reports_generated_count', coalesce(ac.generated, 0),
        'finalized_at', r.completed_at,
        'points_generated_at', cs.points_generated_at,
        'reports_generated_at', cs.reports_generated_at,
        'validation_checked_at', cs.validation_checked_at,
        'last_finalize_message', cs.last_finalize_message
      )
    ),
    'results_readiness', jsonb_build_object(
      'ready', not coalesce(cs.has_blocking_errors, false),
      'missing_placement_count', 0,
      'missing_judge_count', 0,
      'duplicate_placement_group_count', 0,
      'missing_final_award_count', 0,
      'duplicate_final_award_count', 0
    ),
    'latest_finalize', coalesce(to_jsonb(r), '{}'::jsonb),
    'artifact_counts', jsonb_build_object(
      'total', coalesce(ac.total, 0),
      'generated', coalesce(ac.generated, 0),
      'queued', coalesce(ac.queued, 0),
      'failed', coalesce(ac.failed, 0),
      'by_report', coalesce(ac.by_report, '{}'::jsonb)
    ),
    'task_counts', jsonb_build_object(
      'queued', coalesce(tc.queued, 0),
      'running', coalesce(tc.running, 0),
      'failed', coalesce(tc.failed, 0),
      'completed', coalesce(tc.completed, 0),
      'remaining', coalesce(tc.remaining, 0)
    ),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'show_id', a.show_id,
        'finalize_run_id', a.finalize_run_id,
        'report_name', a.report_name,
        'artifact_status', a.artifact_status,
        'generated_at', a.generated_at,
        'is_current', a.is_current,
        'scope_key', a.scope_key,
        'section_ids', to_jsonb(a.section_ids),
        'metadata', a.metadata,
        'storage_bucket', a.storage_bucket,
        'storage_path', a.storage_path,
        'file_name', a.file_name,
        'error_count', a.error_count,
        'generation', a.generation,
        'created_at', a.created_at
      ) order by a.report_name, a.created_at, a.id)
      from artifact_page a
    ), '[]'::jsonb),
    'artifact_page', jsonb_build_object(
      'limit', (select page_limit from requested),
      'offset', (select page_offset from requested),
      'has_more', coalesce(fc.total, 0) >
        (select page_limit + page_offset from requested)
    ),
    'deliveries', '[]'::jsonb,
    'latest_archive', '{}'::jsonb
  )
  from show_row s
  left join state_row cs on true
  left join selected_run r on true
  cross join artifact_counts ac
  cross join task_counts tc
  cross join filtered_artifact_count fc;
$function$;

revoke all on function public.get_closeout_dashboard_scoped_without_activity(
  uuid, text, uuid[], integer, integer, public.report_type
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped_without_activity(
  uuid, text, uuid[], integer, integer, public.report_type
) to authenticated, service_role;
