-- Preserve the deployed dashboard implementation and enrich only its review
-- rows with source-specific artifact/task failure fields. This keeps all
-- existing dashboard selection, ordering, pagination, and retry semantics.

alter function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) rename to get_closeout_dashboard_scoped_without_error_sources;

create or replace function public.get_closeout_dashboard_scoped(
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
  v_review_reports jsonb := '[]'::jsonb;
begin
  v_dashboard := public.get_closeout_dashboard_scoped_without_error_sources(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );

  select coalesce(jsonb_agg(
    review.value || jsonb_build_object(
      'metadata', coalesce(a.metadata, '{}'::jsonb),
      'metadata_last_error', a.metadata ->> 'last_error',
      'metadata_error_message', a.metadata ->> 'error_message',
      'metadata_error_category', a.metadata ->> 'error_category',
      'missing_field', a.metadata ->> 'missing_field',
      'missing_label', a.metadata ->> 'missing_label',
      'exhibitor_name', coalesce(
        nullif(a.metadata ->> 'exhibitor_name', ''),
        review.value ->> 'exhibitor_name'
      ),
      'task_error_message', task.error_message,
      'task_last_error', task.last_error
    )
    order by review.ordinality
  ), '[]'::jsonb)
  into v_review_reports
  from jsonb_array_elements(
    coalesce(v_dashboard -> 'review_reports', '[]'::jsonb)
  ) with ordinality review(value, ordinality)
  left join public.show_report_artifacts a
    on a.id = (review.value ->> 'artifact_id')::uuid
  left join lateral (
    select q.error_message, q.last_error
    from public.show_task_queue q
    where q.report_artifact_id = a.id
      and q.task_type = 'render_report'::public.show_task_type
    order by coalesce(
      q.failed_at,
      q.completed_at,
      q.heartbeat_at,
      q.started_at,
      q.claimed_at,
      q.created_at
    ) desc nulls last,
    q.created_at desc,
    q.id desc
    limit 1
  ) task on true;

  return jsonb_set(
    v_dashboard,
    '{review_reports}',
    v_review_reports,
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

comment on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
)
is 'Returns the scoped Closeout dashboard with full artifact metadata and source-specific artifact/task errors on review rows.';
