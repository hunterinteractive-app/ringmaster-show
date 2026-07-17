-- ARBA reports depend on the persisted exhibitor and club report sent dates.
-- Keep their artifacts visible but deferred during automatic generation, and
-- allow the explicit single-report command to opt in after delivery.

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

create or replace function public.enqueue_report_render_tasks(
  p_show_id uuid,
  p_finalize_run_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
begin
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

  select public.enqueue_report_render_tasks(
    p_show_id, p_finalize_run_id, false
  ) into v_inserted;
  return v_inserted;
end;
$function$;

do $block$
declare
  v_definition text;
  v_updated text;
  v_needle text := 'and a.is_current = true';
  v_replacement text := 'and a.is_current = true' || chr(10) ||
    '    and a.report_name <> ''arba_report''::public.report_type';
  v_occurrences integer;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'requeue_closeout_render_tasks'
    and p.proargtypes = '2950 2950 25 16'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception 'public.requeue_closeout_render_tasks is required';
  end if;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_needle, ''))
  ) / length(v_needle);
  if v_occurrences <> 2 then
    raise exception 'Expected two bulk artifact predicates, found %',
      v_occurrences;
  end if;

  v_updated := replace(v_definition, v_needle, v_replacement);
  execute v_updated;
end;
$block$;

do $block$
declare
  v_definition text;
  v_updated text;
  v_old text :=
    'perform public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id);';
  v_new text :=
    'perform public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id, true);';
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'requeue_closeout_artifacts'
    and p.pronargs = 5;

  if v_definition is null then
    raise exception 'public.requeue_closeout_artifacts is required';
  end if;
  if strpos(v_definition, v_old) = 0 then
    raise exception 'Single-report enqueue call was not found';
  end if;

  v_updated := replace(v_definition, v_old, v_new);
  execute v_updated;
end;
$block$;

update public.show_task_queue q
set task_status = 'cancelled'::public.show_task_status,
    completed_at = now(),
    last_error = null,
    error_message = null,
    error_category = null,
    worker_id = null,
    claimed_by = null,
    claimed_at = null,
    heartbeat_at = null,
    lease_expires_at = null
from public.show_report_artifacts a
where q.report_artifact_id = a.id
  and q.task_type = 'render_report'::public.show_task_type
  and q.task_status in (
    'queued'::public.show_task_status,
    'failed'::public.show_task_status
  )
  and a.report_name = 'arba_report'::public.report_type;

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
  );
