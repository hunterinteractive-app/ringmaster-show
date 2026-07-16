create or replace function public.get_closeout_dashboard_scoped(
  p_show_id uuid,
  p_scope_key text,
  p_section_ids uuid[],
  p_artifact_limit integer default 100,
  p_artifact_offset integer default 0,
  p_report_name public.report_type default null::public.report_type
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_dashboard jsonb;
  v_last_activity_at timestamptz;
  v_completed_at timestamptz;
  v_active_count integer := 0;
  v_review_reports jsonb := '[]'::jsonb;
  v_skipped_count integer := 0;
  v_skipped_reports jsonb := '[]'::jsonb;
begin
  v_dashboard := public.get_closeout_dashboard_scoped_without_activity(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );

  with selected_run as (
    select f.id
    from public.show_finalize_runs f
    where f.show_id = p_show_id
      and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  current_tasks as (
    select q.*
    from public.show_task_queue q
    join public.show_report_artifacts a
      on a.id = q.report_artifact_id and a.is_current = true
    join selected_run r on r.id = q.finalize_run_id
    where q.show_id = p_show_id
      and q.task_type = 'render_report'::public.show_task_type
  )
  select
    max(greatest(
      q.created_at,
      q.claimed_at,
      q.started_at,
      q.heartbeat_at,
      q.completed_at,
      q.failed_at
    )),
    max(coalesce(q.completed_at, q.failed_at)),
    count(*) filter (
      where q.task_status in (
        'queued'::public.show_task_status,
        'running'::public.show_task_status
      )
    )::integer
  into v_last_activity_at, v_completed_at, v_active_count
  from current_tasks q;

  with selected_run as (
    select f.id
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
  review_rows as (
    select
      a.*,
      q.task_status,
      q.error_category task_error_category,
      q.error_message task_error_message,
      q.last_error,
      q.attempt_count,
      q.max_attempts,
      coalesce(
        q.failed_at,
        q.completed_at,
        q.heartbeat_at,
        q.started_at,
        q.claimed_at,
        q.created_at
      ) last_attempted_at,
      (
        coalesce(
          q.task_status = 'failed'::public.show_task_status
            and q.attempt_count < q.max_attempts,
          false
        )
        or coalesce(repair.is_repairable, false)
        or (
          a.report_name in (
            'payback_report'::public.report_type,
            'unpaid_balances_report'::public.report_type
          )
          and (
            coalesce(q.last_error, '') ilike '%code: 57014%'
            or coalesce(q.last_error, '') ilike '%code: 25006%'
          )
        )
      ) retryable
    from current_artifacts a
    left join lateral (
      select task.*
      from public.show_task_queue task
      where task.report_artifact_id = a.id
        and task.task_type = 'render_report'::public.show_task_type
      order by coalesce(
        task.failed_at,
        task.completed_at,
        task.heartbeat_at,
        task.started_at,
        task.claimed_at,
        task.created_at
      ) desc nulls last,
      task.created_at desc,
      task.id desc
      limit 1
    ) q on true
    left join lateral public.resolve_closeout_artifact_scope(
      a.show_id,
      a.finalize_run_id,
      a.report_name,
      a.metadata
    ) repair on a.artifact_status = 'failed'::public.artifact_status
      and a.metadata ->> 'error_category' = 'invalid_scope'
    where (
      a.artifact_status in (
        'queued'::public.artifact_status,
        'failed'::public.artifact_status
      )
      or q.task_status in (
        'queued'::public.show_task_status,
        'running'::public.show_task_status,
        'failed'::public.show_task_status
      )
    )
    and coalesce(a.metadata ->> 'error_category', '') <> 'missing_exhibitor_entries'
    and coalesce(a.metadata ->> 'non_retryable_reason', '') <> 'missing_exhibitor_entries'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'artifact_id', a.id,
    'finalize_run_id', a.finalize_run_id,
    'report_name', a.report_name,
    'artifact_status', a.artifact_status,
    'task_status', coalesce(a.task_status::text, 'missing'),
    'review_group', case
      when a.task_status in (
        'queued'::public.show_task_status,
        'running'::public.show_task_status
      ) then 'active'
      when a.artifact_status = 'failed'::public.artifact_status
        or a.task_status = 'failed'::public.show_task_status
        then case when a.retryable
          then 'retryable_failure'
          else 'non_retryable_failure'
        end
      else 'missing'
    end,
    'section_ids', to_jsonb(a.section_ids),
    'section_id', a.metadata ->> 'section_id',
    'section_label', a.metadata ->> 'section_label',
    'show_letter', a.metadata ->> 'show_letter',
    'scope', a.metadata ->> 'scope',
    'species', a.metadata ->> 'species',
    'exhibitor_name', a.metadata ->> 'exhibitor_name',
    'breed_name', a.metadata ->> 'breed_name',
    'club_name', a.metadata ->> 'club_name',
    'sanctioning_body', a.metadata ->> 'sanctioning_body',
    'error_category', case
      when a.metadata ->> 'error_category' = 'invalid_scope'
        then 'invalid_scope'
      when coalesce(a.last_error, '') ilike '%code: 57014%'
        then 'statement_timeout'
      when coalesce(a.last_error, '') ilike '%code: 25006%'
        then 'read_only_violation'
      else coalesce(
        a.metadata ->> 'error_category',
        a.task_error_category,
        'render_error'
      )
    end,
    'error_message', case
      when a.metadata ->> 'error_category' = 'invalid_scope'
        then coalesce(
          a.metadata ->> 'error_message',
          'The report artifact has incomplete structured scope metadata.'
        )
      when coalesce(a.last_error, '') ilike '%code: 57014%'
        then 'The Paybacks report query exceeded its database time limit.'
      when coalesce(a.last_error, '') ilike '%code: 25006%'
        then 'The balance report encountered an operation that is not allowed during read-only rendering.'
      else coalesce(
        a.metadata ->> 'error_message',
        a.task_error_message,
        'The report could not be rendered.'
      )
    end,
    'task_history_category', a.task_error_category,
    'task_history_message', a.task_error_message,
    'retryable', a.retryable,
    'attempt_count', coalesce(a.attempt_count, 0),
    'max_attempts', coalesce(a.max_attempts, 0),
    'last_attempted_at', a.last_attempted_at
  ) order by
    case
      when a.retryable then 1
      when a.artifact_status = 'failed'::public.artifact_status
        or a.task_status = 'failed'::public.show_task_status then 2
      when a.task_status is null then 3
      else 4
    end,
    a.report_name,
    a.created_at,
    a.id
  ), '[]'::jsonb)
  into v_review_reports
  from review_rows a;

  with selected_run as (
    select f.id
    from public.show_finalize_runs f
    where f.show_id = p_show_id
      and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  skipped as (
    select a.*
    from public.show_report_artifacts a
    join selected_run r on r.id = a.finalize_run_id
    where a.show_id = p_show_id
      and a.is_current = true
      and a.artifact_status = 'failed'::public.artifact_status
      and (
        a.metadata ->> 'error_category' = 'missing_exhibitor_entries'
        or a.metadata ->> 'non_retryable_reason' = 'missing_exhibitor_entries'
      )
  )
  select
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'artifact_id', s.id,
          'report_name', s.report_name,
          'exhibitor_id', s.metadata ->> 'exhibitor_id',
          'exhibitor_name', s.metadata ->> 'exhibitor_name',
          'reason', 'No qualifying shown entries'
        )
        order by s.metadata ->> 'exhibitor_name', s.id
      ),
      '[]'::jsonb
    )
  into v_skipped_count, v_skipped_reports
  from skipped s;

  v_dashboard := jsonb_set(
    v_dashboard,
    '{task_counts}',
    coalesce(v_dashboard -> 'task_counts', '{}'::jsonb) ||
      jsonb_build_object(
        'failed',
          greatest(
            coalesce((v_dashboard -> 'task_counts' ->> 'failed')::integer, 0)
              - v_skipped_count,
            0
          ),
        'remaining',
          greatest(
            coalesce((v_dashboard -> 'task_counts' ->> 'remaining')::integer, 0)
              - v_skipped_count,
            0
          ),
        'skipped_reports', v_skipped_count,
        'skipped_missing_exhibitor_entries', v_skipped_count,
        'last_activity_at', v_last_activity_at,
        'completed_at', case when v_active_count = 0 then v_completed_at end
      ),
    true
  );

  v_dashboard := jsonb_set(
    v_dashboard,
    '{skipped_reports}',
    v_skipped_reports,
    true
  );

  return jsonb_set(
    v_dashboard,
    '{review_reports}',
    v_review_reports,
    true
  );
end;
$function$;
