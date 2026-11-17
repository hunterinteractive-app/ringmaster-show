-- Check-in sheets belong to pre-show check-in, not the closeout manifest.
-- Preserve the current function bodies, configuration and EXECUTE grants.
begin;

do $migration$
declare
  definition text;
  old_manifest constant text := $$array['exhibitor_report','checkin_sheet']::public.report_type[]$$;
begin
  definition := pg_get_functiondef(
    'public.finalize_show_scoped(uuid,uuid[],text,text)'::regprocedure
  );
  if strpos(definition, old_manifest) = 0 then
    raise exception 'Expected closeout exhibitor manifest was not found';
  end if;
  definition := replace(definition, old_manifest,
    $$array['exhibitor_report']::public.report_type[]$$);
  -- A reused run can contain retired historical artifacts; report current ones.
  definition := replace(definition,
    'from public.show_report_artifacts a where a.finalize_run_id = v_finalize_run_id',
    'from public.show_report_artifacts a where a.finalize_run_id = v_finalize_run_id and a.is_current = true');
  execute definition;

  definition := pg_get_functiondef(
    'public.enqueue_report_render_tasks(uuid,uuid,boolean)'::regprocedure
  );
  if strpos(definition,
    $$and (p_include_arba or a.report_name <> 'arba_report'::public.report_type)$$) = 0 then
    raise exception 'Expected closeout render queue filter was not found';
  end if;
  definition := replace(definition,
    $$and (p_include_arba or a.report_name <> 'arba_report'::public.report_type)$$,
    $$and a.report_name <> 'checkin_sheet'::public.report_type
    and (p_include_arba or a.report_name <> 'arba_report'::public.report_type)$$);
  execute definition;
end;
$migration$;

-- Keep existing PDFs and diagnostic history, but remove these artifacts from
-- current closeout counts, delivery requirements and regeneration selections.
update public.show_report_artifacts
set is_current = false,
    superseded_at = coalesce(superseded_at, now()),
    metadata = metadata || jsonb_build_object(
      'closeout_exclusion_reason', 'Check-in sheets are generated before the show.'
    )
where report_name = 'checkin_sheet'::public.report_type
  and finalize_run_id is not null
  and is_current = true;

-- Completed tasks retain their status. Cancel unfinished work, including
-- older superseded tasks, so a worker cannot retry unnecessary sheets.
update public.show_task_queue task
set task_status = 'cancelled'::public.show_task_status,
    lease_expires_at = null
from public.show_report_artifacts artifact
where task.report_artifact_id = artifact.id
  and artifact.report_name = 'checkin_sheet'::public.report_type
  and artifact.finalize_run_id is not null
  and task.task_type = 'render_report'::public.show_task_type
  and task.task_status in ('queued', 'running', 'failed');

-- Refresh the cached count only; do not declare unrelated reports or points
-- current, and do not change report generation timestamps.
update public.show_closeout_state state
set reports_generated_count = (
  select count(*) from public.show_report_artifacts artifact
  where artifact.show_id = state.show_id
    and artifact.is_current = true
    and artifact.artifact_status = 'generated'
)
where exists (
  select 1 from public.show_report_artifacts artifact
  where artifact.show_id = state.show_id
    and artifact.report_name = 'checkin_sheet'::public.report_type
    and artifact.finalize_run_id is not null
);

commit;
