-- ARBA artifacts are manual-only because their PDFs depend on exhibitor and
-- club report delivery timestamps. Mark them deferred whenever an automatic
-- enqueue excludes ARBA, and remove deferred ARBA from bulk progress/review.

create or replace function public.enqueue_report_render_tasks(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_include_arba boolean
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
begin
  if not p_include_arba then
    update public.show_report_artifacts a
    set artifact_status = 'warning'::public.artifact_status,
        metadata = a.metadata || jsonb_build_object(
          'deferred_until_report_delivery', true,
          'deferred_reason',
          'Generate ARBA after exhibitor and club reports are sent.'
        )
    where a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true
      and a.report_name = 'arba_report'::public.report_type
      and a.artifact_status in (
        'queued'::public.artifact_status,
        'failed'::public.artifact_status
      );
  end if;

  insert into public.show_task_queue (
    show_id, finalize_run_id, scope_key, task_type, task_status,
    report_artifact_id, payload, priority, available_at
  )
  select
    a.show_id, a.finalize_run_id, a.scope_key,
    'render_report'::public.show_task_type,
    'queued'::public.show_task_status,
    a.id,
    jsonb_build_object(
      'artifact_id', a.id,
      'report_name', a.report_name,
      'scope_key', a.scope_key,
      'section_ids', to_jsonb(a.section_ids),
      'generation', a.generation,
      'metadata', a.metadata
    ),
    case
      when a.report_name = 'arba_report'::public.report_type then 10
      when a.report_name = 'details_by_breed'::public.report_type then 20
      when a.report_name = 'judge_report'::public.report_type then 30
      else 100
    end,
    now()
  from public.show_report_artifacts a
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and (p_include_arba or a.report_name <> 'arba_report'::public.report_type)
    and a.artifact_status in (
      'queued'::public.artifact_status,
      'failed'::public.artifact_status
    )
  on conflict (report_artifact_id, task_type)
    where report_artifact_id is not null
  do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

alter function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) rename to get_closeout_dashboard_scoped_with_deferred_arba;

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
      and a.scope_key = p_scope_key
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

update public.show_report_artifacts a
set artifact_status = 'warning'::public.artifact_status,
    metadata = a.metadata || jsonb_build_object(
      'deferred_until_report_delivery', true,
      'deferred_reason',
      'Generate ARBA after exhibitor and club reports are sent.'
    )
where a.is_current = true
  and a.report_name = 'arba_report'::public.report_type
  and a.artifact_status in (
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
        'running'::public.show_task_status
      )
  );
