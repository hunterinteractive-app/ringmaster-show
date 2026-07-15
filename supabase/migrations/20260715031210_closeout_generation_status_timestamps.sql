-- Keep the Closeout UI on one scoped dashboard response while adding the
-- server-authoritative timestamps needed for completion and stalled warnings.

alter function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) rename to get_closeout_dashboard_scoped_without_activity;

create function public.get_closeout_dashboard_scoped(
  p_show_id uuid,
  p_scope_key text,
  p_section_ids uuid[],
  p_artifact_limit integer default 100,
  p_artifact_offset integer default 0,
  p_report_name public.report_type default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_dashboard jsonb;
  v_last_activity_at timestamptz;
  v_completed_at timestamptz;
  v_active_count integer := 0;
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

  return jsonb_set(
    v_dashboard,
    '{task_counts}',
    coalesce(v_dashboard -> 'task_counts', '{}'::jsonb) ||
      jsonb_build_object(
        'last_activity_at', v_last_activity_at,
        'completed_at', case when v_active_count = 0 then v_completed_at end
    ),
    true
  );
end;
$function$;

revoke all on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) to authenticated, service_role;

-- The wrapper runs as the caller, so authenticated users retain only the same
-- RLS-filtered access the original dashboard function already provided.
revoke all on function public.get_closeout_dashboard_scoped_without_activity(
  uuid, text, uuid[], integer, integer, public.report_type
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped_without_activity(
  uuid, text, uuid[], integer, integer, public.report_type
) to authenticated, service_role;
