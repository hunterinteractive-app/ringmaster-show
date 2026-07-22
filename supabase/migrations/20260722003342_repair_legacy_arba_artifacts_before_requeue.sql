create or replace function public.requeue_closeout_artifacts(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_scope_key text,
  p_report_name public.report_type default null,
  p_artifact_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer := 0;
  v_effective_artifact_id uuid := p_artifact_id;
  v_target_section_id text;
begin
  if auth.uid() is not null
     and not public.user_can_finalize_show(p_show_id, auth.uid()) then
    raise exception 'Not authorized to manage closeout for this show';
  end if;

  if not exists (
    select 1
    from public.show_finalize_runs f
    where f.id = p_finalize_run_id
      and f.show_id = p_show_id
      and f.scope_key = p_scope_key
  ) then
    raise exception 'Finalize run does not match the requested show and scope';
  end if;

  if p_artifact_id is not null then
    select a.metadata ->> 'section_id'
    into v_target_section_id
    from public.show_report_artifacts a
    where a.id = p_artifact_id
      and a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true;
  end if;

  -- ARBA artifacts generated before canonical artifact scoping have no
  -- artifact_key and omit the canonical scope fields in metadata. Merely
  -- changing those rows to queued is insufficient: enqueue_report_render_tasks
  -- intentionally ignores them, leaving the UI stuck at "queued" forever.
  -- Feed only the requested legacy rows through the established repair path.
  update public.show_report_artifacts a
  set artifact_status = 'failed'::public.artifact_status,
      metadata = a.metadata || jsonb_build_object(
        'error_category', 'invalid_scope',
        'error_message', 'Legacy ARBA artifact requires canonical scope repair'
      )
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and a.report_name = 'arba_report'::public.report_type
    and (p_report_name is null or a.report_name = p_report_name)
    and (p_artifact_id is null or a.id = p_artifact_id)
    and (
      a.artifact_key is null
      or a.scope_key <> public.closeout_artifact_scope_key(
        a.show_id, a.report_name, a.section_ids, a.metadata
      )
      or a.metadata ->> 'scope_key' is distinct from a.scope_key
      or a.metadata -> 'section_ids' is distinct from to_jsonb(a.section_ids)
    );

  perform public.repair_closeout_artifact_scopes(
    p_show_id,
    p_finalize_run_id
  );

  -- Repair may reuse a pre-existing identity owner and supersede the legacy
  -- row. Continue with that canonical row while preserving single-section
  -- regeneration semantics.
  if p_artifact_id is not null and v_target_section_id is not null then
    select a.id
    into v_effective_artifact_id
    from public.show_report_artifacts a
    where a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true
      and a.report_name = 'arba_report'::public.report_type
      and a.metadata ->> 'section_id' = v_target_section_id
      and a.scope_key = public.closeout_artifact_scope_key(
        a.show_id, a.report_name, a.section_ids, a.metadata
      )
    order by a.created_at, a.id
    limit 1;
  end if;

  update public.show_report_artifacts a
  set artifact_status = 'queued'::public.artifact_status,
      storage_bucket = 'show-files',
      storage_path = format(
        'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
        a.show_id, a.finalize_run_id, a.id, a.generation + 1
      ),
      file_name = null,
      mime_type = null,
      file_size_bytes = null,
      file_hash_sha256 = null,
      generated_at = null,
      error_count = 0,
      generation = a.generation + 1,
      metadata = a.metadata - 'error_category' - 'error_message'
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and (p_report_name is null or a.report_name = p_report_name)
    and (v_effective_artifact_id is null or a.id = v_effective_artifact_id)
    and a.scope_key = public.closeout_artifact_scope_key(
      a.show_id, a.report_name, a.section_ids, a.metadata
    );

  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'No canonical artifact matched the requested finalize run and scope';
  end if;

  update public.show_task_queue q
  set task_status = 'queued'::public.show_task_status,
      scope_key = a.scope_key,
      available_at = now(),
      started_at = null,
      completed_at = null,
      failed_at = null,
      worker_id = null,
      claimed_by = null,
      claimed_at = null,
      last_error = null,
      error_message = null,
      error_category = null,
      heartbeat_at = null,
      lease_expires_at = null,
      attempt_count = 0,
      payload = jsonb_build_object(
        'artifact_id', a.id,
        'report_name', a.report_name,
        'scope_key', a.scope_key,
        'section_ids', to_jsonb(a.section_ids),
        'generation', a.generation,
        'metadata', a.metadata
      )
  from public.show_report_artifacts a
  where q.report_artifact_id = a.id
    and a.is_current = true
    and a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and (p_report_name is null or a.report_name = p_report_name)
    and (v_effective_artifact_id is null or a.id = v_effective_artifact_id)
    and q.task_type = 'render_report'::public.show_task_type;

  perform public.enqueue_report_render_tasks(
    p_show_id,
    p_finalize_run_id,
    true
  );

  return jsonb_build_object(
    'queued_count', v_count,
    'scope_key', p_scope_key,
    'finalize_run_id', p_finalize_run_id,
    'artifact_id', v_effective_artifact_id
  );
end;
$function$;

revoke all on function public.requeue_closeout_artifacts(
  uuid,
  uuid,
  text,
  public.report_type,
  uuid
) from public, anon;

grant execute on function public.requeue_closeout_artifacts(
  uuid,
  uuid,
  text,
  public.report_type,
  uuid
) to authenticated, service_role;
