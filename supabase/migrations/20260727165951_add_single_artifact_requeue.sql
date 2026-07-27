create or replace function public.requeue_single_closeout_artifact(
  p_show_id uuid, p_finalize_run_id uuid, p_scope_key text, p_artifact_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_artifact public.show_report_artifacts%rowtype;
begin
  if auth.uid() is not null and not public.user_can_finalize_show(p_show_id, auth.uid()) then
    raise exception 'Not authorized to manage closeout for this show';
  end if;

  update public.show_report_artifacts a
  set artifact_status = 'queued'::public.artifact_status,
      storage_bucket = 'show-files',
      storage_path = format('shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf', a.show_id, a.finalize_run_id, a.id, a.generation + 1),
      file_name = null, mime_type = null, file_size_bytes = null,
      file_hash_sha256 = null, generated_at = null, error_count = 0,
      generation = a.generation + 1,
      metadata = a.metadata - 'error_category' - 'error_message'
  where a.id = p_artifact_id and a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id and a.scope_key = p_scope_key
    and a.is_current = true
  returning a.* into v_artifact;
  if v_artifact.id is null then
    raise exception 'The selected report artifact does not match this closeout scope';
  end if;

  update public.show_task_queue q
  set task_status = 'queued'::public.show_task_status,
      scope_key = v_artifact.scope_key,
      available_at = now(), started_at = null, completed_at = null,
      failed_at = null, worker_id = null, claimed_by = null, claimed_at = null,
      last_error = null, error_message = null, error_category = null,
      heartbeat_at = null, lease_expires_at = null, attempt_count = 0,
      payload = jsonb_build_object('artifact_id', v_artifact.id, 'report_name', v_artifact.report_name, 'scope_key', v_artifact.scope_key, 'section_ids', to_jsonb(v_artifact.section_ids), 'generation', v_artifact.generation, 'metadata', v_artifact.metadata)
  where q.report_artifact_id = v_artifact.id
    and q.task_type = 'render_report'::public.show_task_type;
  if not found then
    insert into public.show_task_queue (show_id, finalize_run_id, scope_key, task_type, task_status, report_artifact_id, payload, priority, available_at)
    values (v_artifact.show_id, v_artifact.finalize_run_id, v_artifact.scope_key, 'render_report'::public.show_task_type, 'queued'::public.show_task_status, v_artifact.id,
      jsonb_build_object('artifact_id', v_artifact.id, 'report_name', v_artifact.report_name, 'scope_key', v_artifact.scope_key, 'section_ids', to_jsonb(v_artifact.section_ids), 'generation', v_artifact.generation, 'metadata', v_artifact.metadata), 100, now());
  end if;
  return jsonb_build_object('artifact_id', v_artifact.id, 'queued_count', 1);
end;
$function$;

revoke all on function public.requeue_single_closeout_artifact(uuid, uuid, text, uuid) from public, anon;
grant execute on function public.requeue_single_closeout_artifact(uuid, uuid, text, uuid) to authenticated, service_role;
