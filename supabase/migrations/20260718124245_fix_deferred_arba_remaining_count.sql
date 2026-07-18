-- ARBA artifacts use section-level canonical scope keys. Count every ARBA
-- artifact in the selected finalize run when removing deferred/manual ARBA
-- work from bulk generation progress; filtering by the run-level scope key
-- leaves one warning artifact behind as a phantom remaining report.

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
  v_run_id uuid;
  v_arba_total integer := 0;
  v_arba_generated integer := 0;
  v_arba_queued integer := 0;
  v_arba_failed integer := 0;
  v_arba_remaining integer := 0;
  v_review_reports jsonb := '[]'::jsonb;
begin
  v_dashboard := public.get_closeout_dashboard_scoped_with_deferred_arba(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );

  v_run_id := nullif(v_dashboard -> 'latest_finalize' ->> 'id', '')::uuid;

  if v_run_id is not null then
    select
      count(*)::integer,
      count(*) filter (where a.artifact_status = 'generated')::integer,
      count(*) filter (where a.artifact_status = 'queued')::integer,
      count(*) filter (where a.artifact_status = 'failed')::integer,
      count(*) filter (
        where a.artifact_status in (
          'queued'::public.artifact_status,
          'failed'::public.artifact_status
        )
        and not exists (
          select 1
          from public.show_task_queue q
          where q.report_artifact_id = a.id
            and q.task_type = 'render_report'::public.show_task_type
            and q.task_status in (
              'queued'::public.show_task_status,
              'running'::public.show_task_status,
              'failed'::public.show_task_status
            )
        )
      )::integer
    into
      v_arba_total,
      v_arba_generated,
      v_arba_queued,
      v_arba_failed,
      v_arba_remaining
    from public.show_report_artifacts a
    where a.show_id = p_show_id
      and a.finalize_run_id = v_run_id
      and a.is_current = true
      and a.report_name = 'arba_report'::public.report_type;
  end if;

  select coalesce(jsonb_agg(review.value order by review.ordinality), '[]'::jsonb)
  into v_review_reports
  from jsonb_array_elements(
    coalesce(v_dashboard -> 'review_reports', '[]'::jsonb)
  ) with ordinality review(value, ordinality)
  where review.value ->> 'report_name' <> 'arba_report';

  v_dashboard := jsonb_set(
    v_dashboard #- '{artifact_counts,by_report,arba_report}',
    '{artifact_counts}',
    (coalesce(v_dashboard -> 'artifact_counts', '{}'::jsonb)
      #- '{by_report,arba_report}') ||
      jsonb_build_object(
        'total', greatest(
          coalesce((v_dashboard -> 'artifact_counts' ->> 'total')::integer, 0)
            - v_arba_total,
          0
        ),
        'generated', greatest(
          coalesce((v_dashboard -> 'artifact_counts' ->> 'generated')::integer, 0)
            - v_arba_generated,
          0
        ),
        'queued', greatest(
          coalesce((v_dashboard -> 'artifact_counts' ->> 'queued')::integer, 0)
            - v_arba_queued,
          0
        ),
        'failed', greatest(
          coalesce((v_dashboard -> 'artifact_counts' ->> 'failed')::integer, 0)
            - v_arba_failed,
          0
        )
      ),
    true
  );

  v_dashboard := jsonb_set(
    v_dashboard,
    '{task_counts,remaining}',
    to_jsonb(greatest(
      coalesce((v_dashboard -> 'task_counts' ->> 'remaining')::integer, 0)
        - v_arba_remaining,
      0
    )),
    true
  );

  v_dashboard := jsonb_set(
    v_dashboard,
    '{dashboard,closeout,reports_generated_count}',
    to_jsonb(greatest(
      coalesce((v_dashboard -> 'dashboard' -> 'closeout' ->> 'reports_generated_count')::integer, 0)
        - v_arba_generated,
      0
    )),
    true
  );

  v_dashboard := jsonb_set(
    v_dashboard,
    '{dashboard,closeout,is_reports_stale}',
    to_jsonb(
      coalesce((v_dashboard -> 'artifact_counts' ->> 'queued')::integer, 0) +
      coalesce((v_dashboard -> 'artifact_counts' ->> 'failed')::integer, 0) > 0
    ),
    true
  );

  return jsonb_set(v_dashboard, '{review_reports}', v_review_reports, true);
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
is 'Returns scoped Closeout progress with every ARBA artifact in the selected finalize run excluded from automatic bulk-generation counters.';
