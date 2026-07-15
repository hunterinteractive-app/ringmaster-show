-- Correct repair function for schemas where show_report_artifacts has no updated_at column.

create or replace function public.repair_final_closeout_report_failures(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_artifact public.show_report_artifacts%rowtype;
  v_scope record;
  v_metadata jsonb;
  v_scope_key text;
  v_artifact_key text;
  v_replacement_id uuid;
  v_repairable_exhibitors integer := 0;
  v_obsolete_exhibitors integer := 0;
  v_render_fixes integer := 0;
  v_queued integer := 0;
  v_obsolete_names jsonb := '[]'::jsonb;
begin
  if p_show_id is null or p_finalize_run_id is null then
    raise exception 'show_id and finalize_run_id are required'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.show_finalize_runs f
    where f.id = p_finalize_run_id
      and f.show_id = p_show_id
  ) then
    raise exception 'Finalize run does not belong to the requested show'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_show_id::text || ':' || p_finalize_run_id::text ||
      ':final-closeout-report-repair',
    0
  ));

  for v_artifact in
    select a.*
    from public.show_report_artifacts a
    where a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true
      and a.artifact_status = 'failed'::public.artifact_status
      and (
        (
          a.report_name = 'exhibitor_report'::public.report_type
          and a.metadata ->> 'error_category' in (
            'invalid_scope', 'missing_exhibitor_entries'
          )
        )
        or a.report_name in (
          'payback_report'::public.report_type,
          'unpaid_balances_report'::public.report_type
        )
      )
    order by a.created_at, a.id
    for update
  loop
    if v_artifact.report_name = 'exhibitor_report'::public.report_type then
      select * into v_scope
      from public.resolve_closeout_artifact_scope(
        v_artifact.show_id,
        v_artifact.finalize_run_id,
        v_artifact.report_name,
        v_artifact.metadata
      );

      if not coalesce(v_scope.is_repairable, false) then
        v_obsolete_exhibitors := v_obsolete_exhibitors + 1;
        v_obsolete_names := v_obsolete_names || jsonb_build_array(
          coalesce(
            nullif(btrim(v_artifact.metadata ->> 'exhibitor_name'), ''),
            v_artifact.metadata ->> 'exhibitor_id',
            v_artifact.id::text
          )
        );
        if not p_dry_run then
          update public.show_report_artifacts a
          set metadata = a.metadata || jsonb_build_object(
                'error_category', 'missing_exhibitor_entries',
                'error_message',
                  'This exhibitor has no qualifying shown entries in the selected Closeout scope.'
              ),
              error_count = greatest(a.error_count, 1)
          where a.id = v_artifact.id;
        end if;
        continue;
      end if;

      v_repairable_exhibitors := v_repairable_exhibitors + 1;
      if p_dry_run then
        continue;
      end if;

      v_metadata := (
        v_scope.metadata - 'error_category' - 'error_message'
      ) || jsonb_build_object(
        'repair_of_artifact_id', v_artifact.id,
        'report_scope', 'repair:' || v_artifact.id::text
      );
    else
      v_render_fixes := v_render_fixes + 1;
      if p_dry_run then
        continue;
      end if;

      v_metadata := (
        v_artifact.metadata - 'error_category' - 'error_message'
      ) || jsonb_build_object(
        'repair_of_artifact_id', v_artifact.id,
        'report_scope', 'repair:' || v_artifact.id::text
      );
    end if;

    v_artifact_key := public.closeout_artifact_identity(
      v_artifact.report_name,
      v_metadata
    );
    v_scope_key := public.closeout_artifact_scope_key(
      v_artifact.show_id,
      v_artifact.report_name,
      case
        when v_artifact.report_name = 'exhibitor_report'::public.report_type
          then v_scope.section_ids
        else v_artifact.section_ids
      end,
      v_metadata
    );
    v_metadata := v_metadata || jsonb_build_object(
      'scope_key', v_scope_key,
      'section_ids', to_jsonb(case
        when v_artifact.report_name = 'exhibitor_report'::public.report_type
          then v_scope.section_ids
        else v_artifact.section_ids
      end)
    );

    select a.id into v_replacement_id
    from public.show_report_artifacts a
    where a.finalize_run_id = v_artifact.finalize_run_id
      and a.artifact_key = v_artifact_key
      and a.is_current = true
    limit 1;

    if v_replacement_id is null then
      update public.show_report_artifacts a
      set is_current = false,
          superseded_at = coalesce(a.superseded_at, now())
      where a.id = v_artifact.id;

      insert into public.show_report_artifacts (
        show_id,
        finalize_run_id,
        report_name,
        artifact_status,
        metadata,
        warning_count,
        error_count,
        is_current,
        generation,
        scope_key,
        section_ids,
        artifact_key
      ) values (
        v_artifact.show_id,
        v_artifact.finalize_run_id,
        v_artifact.report_name,
        'queued'::public.artifact_status,
        v_metadata,
        v_artifact.warning_count,
        0,
        true,
        v_artifact.generation + 1,
        v_scope_key,
        case
          when v_artifact.report_name = 'exhibitor_report'::public.report_type
            then v_scope.section_ids
          else v_artifact.section_ids
        end,
        v_artifact_key
      ) returning id into v_replacement_id;
    end if;
  end loop;

  if not p_dry_run then
    select public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id)
    into v_queued;
  end if;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'show_id', p_show_id,
    'finalize_run_id', p_finalize_run_id,
    'repairable_exhibitor_reports', v_repairable_exhibitors,
    'obsolete_exhibitor_reports', v_obsolete_exhibitors,
    'obsolete_exhibitor_names', v_obsolete_names,
    'render_reports_to_requeue', v_render_fixes,
    'queued_tasks', v_queued
  );
end;
$function$;

revoke all on function public.repair_final_closeout_report_failures(
  uuid, uuid, boolean
) from public, anon, authenticated;
grant execute on function public.repair_final_closeout_report_failures(
  uuid, uuid, boolean
) to service_role;
