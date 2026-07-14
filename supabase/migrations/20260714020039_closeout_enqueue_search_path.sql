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
  insert into public.show_task_queue (
    show_id,
    finalize_run_id,
    task_type,
    task_status,
    report_artifact_id,
    payload,
    priority
  )
  select
    sra.show_id,
    sra.finalize_run_id,
    'render_report'::public.show_task_type,
    'queued'::public.show_task_status,
    sra.id,
    jsonb_build_object(
      'report_name', sra.report_name,
      'file_name', sra.file_name,
      'mime_type', sra.mime_type
    ),
    case
      when sra.report_name = 'arba_report'::public.report_type then 10
      when sra.report_name = 'details_by_breed'::public.report_type then 20
      when sra.report_name = 'judge_report'::public.report_type then 30
      when sra.report_name = 'newsletter_show_report'::public.report_type then 40
      else 100
    end
  from public.show_report_artifacts sra
  where sra.show_id = p_show_id
    and sra.finalize_run_id = p_finalize_run_id
    and sra.is_current = true
    and sra.artifact_status = 'queued'::public.artifact_status;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;
