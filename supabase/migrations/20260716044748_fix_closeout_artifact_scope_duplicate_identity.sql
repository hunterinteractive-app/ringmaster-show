-- Preserve the finalize-run artifact identity unique index while repairing
-- legacy invalid-scope failures. Reuse an existing identity owner, including a
-- non-current owner, and insert only when the canonical identity is unowned.

create or replace function public.repair_closeout_artifact_scopes(
  p_show_id uuid,
  p_finalize_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_artifact public.show_report_artifacts%rowtype;
  v_scope record;
  v_replacement_id uuid;
  v_repaired integer := 0;
  v_unrepairable integer := 0;
  v_queued integer := 0;
  v_reasons jsonb := '{}'::jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    p_show_id::text || ':' || p_finalize_run_id::text || ':artifact-scope-repair', 0
  ));
  for v_artifact in
    select a.* from public.show_report_artifacts a
    where a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true and a.artifact_status = 'failed'
      and coalesce(a.metadata ->> 'error_category', '') = 'invalid_scope'
    order by a.created_at, a.id
    for update
  loop
    select * into v_scope
    from public.resolve_closeout_artifact_scope(
      v_artifact.show_id, v_artifact.finalize_run_id,
      v_artifact.report_name, v_artifact.metadata
    );
    if not coalesce(v_scope.is_repairable, false) then
      v_unrepairable := v_unrepairable + 1;
      v_reasons := jsonb_set(
        v_reasons,
        array[coalesce(v_scope.failure_reason, 'unknown_scope')],
        to_jsonb(coalesce((v_reasons ->> coalesce(v_scope.failure_reason, 'unknown_scope'))::integer, 0) + 1),
        true
      );
      continue;
    end if;

    if v_artifact.artifact_key = v_scope.artifact_key then
      update public.show_report_artifacts a
      set artifact_status = 'queued'::public.artifact_status,
          metadata = v_scope.metadata - 'error_category' - 'error_message',
          scope_key = v_scope.scope_key,
          section_ids = v_scope.section_ids,
          error_count = 0,
          generated_at = null,
          generation = a.generation + 1,
          storage_bucket = 'show-files',
          storage_path = format(
            'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
            a.show_id, a.finalize_run_id, a.id, a.generation + 1
          ),
          file_name = null,
          mime_type = null,
          file_size_bytes = null,
          file_hash_sha256 = null,
          is_current = true,
          superseded_at = null
      where a.id = v_artifact.id;
      v_repaired := v_repaired + 1;
      continue;
    end if;

    v_replacement_id := null;
    select a.id into v_replacement_id
    from public.show_report_artifacts a
    where a.finalize_run_id = v_artifact.finalize_run_id
      and a.artifact_key = v_scope.artifact_key
      and a.id <> v_artifact.id
    order by a.is_current desc, a.created_at, a.id
    limit 1
    for update;

    if v_replacement_id is not null then
      update public.show_report_artifacts a
      set artifact_status = 'queued'::public.artifact_status,
          metadata = v_scope.metadata - 'error_category' - 'error_message',
          scope_key = v_scope.scope_key,
          section_ids = v_scope.section_ids,
          error_count = 0,
          generated_at = null,
          generation = a.generation + 1,
          storage_bucket = 'show-files',
          storage_path = format(
            'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
            a.show_id, a.finalize_run_id, a.id, a.generation + 1
          ),
          file_name = null,
          mime_type = null,
          file_size_bytes = null,
          file_hash_sha256 = null,
          is_current = true,
          superseded_at = null
      where a.id = v_replacement_id;
    else
      insert into public.show_report_artifacts (
        show_id, finalize_run_id, report_name, artifact_status, metadata,
        warning_count, error_count, is_current, generation,
        scope_key, section_ids, artifact_key
      ) values (
        v_artifact.show_id, v_artifact.finalize_run_id,
        v_artifact.report_name, 'queued'::public.artifact_status,
        v_scope.metadata - 'error_category' - 'error_message',
        v_artifact.warning_count, 0, true,
        v_artifact.generation + 1, v_scope.scope_key,
        v_scope.section_ids, v_scope.artifact_key
      ) returning id into v_replacement_id;
    end if;

    update public.show_report_artifacts
    set is_current = false, superseded_at = coalesce(superseded_at, now())
    where id = v_artifact.id;
    v_repaired := v_repaired + 1;
  end loop;

  select public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id)
  into v_queued;
  return jsonb_build_object(
    'repaired_count', v_repaired,
    'queued_count', v_queued,
    'unrepairable_count', v_unrepairable,
    'unrepairable_reasons', v_reasons
  );
end;
$function$;

revoke all on function public.repair_closeout_artifact_scopes(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.repair_closeout_artifact_scopes(uuid, uuid)
  to service_role;

comment on function public.repair_closeout_artifact_scopes(uuid, uuid)
is 'Repairs invalid Closeout artifact scopes without duplicating finalize-run artifact identities; existing identity owners are deterministically reactivated and requeued.';
