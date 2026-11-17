-- Internal reports are available on demand, independently of closeout.
begin;
do $migration$
declare
  definition text;
  block_start integer;
  block_end integer;
begin
  definition := pg_get_functiondef('public.finalize_show_scoped(uuid,uuid[],text,text)'::regprocedure);
  block_start := strpos(definition, '    -- Show-level builders are represented once per immutable scoped run.');
  block_end := strpos(substr(definition, block_start), '    select public.enqueue_report_render_tasks(p_show_id, v_finalize_run_id)');
  if block_start = 0 or block_end = 0 then
    raise exception 'Expected internal report manifest block was not found';
  end if;
  definition := substr(definition, 1, block_start - 1)
    || '    -- Internal operational reports are generated only on demand.' || chr(10)
    || substr(definition, block_start + block_end - 1);
  execute definition;

  definition := pg_get_functiondef('public.enqueue_report_render_tasks(uuid,uuid,boolean)'::regprocedure);
  if strpos(definition, $$and a.report_name <> 'checkin_sheet'::public.report_type$$) = 0 then
    raise exception 'Expected closeout queue exclusion was not found';
  end if;
  definition := replace(definition,
    $$and a.report_name <> 'checkin_sheet'::public.report_type$$,
    $$and a.report_name not in (
      'checkin_sheet', 'unpaid_balances_report', 'paid_exhibitor_report',
      'entered_exhibitors_contact_report', 'ribbon_payout_report',
      'payback_report', 'judge_report', 'breed_judged_totals_report'
    )$$);
  execute definition;
end;
$migration$;

-- Keep existing PDFs and diagnostic history, but remove these artifacts from
-- current closeout counts, delivery requirements and regeneration selections.
update public.show_report_artifacts
set is_current = false,
    superseded_at = coalesce(superseded_at, now()),
    metadata = metadata || jsonb_build_object(
      'closeout_exclusion_reason', 'Internal reports are generated on demand.'
    )
where report_name in ('unpaid_balances_report','paid_exhibitor_report','entered_exhibitors_contact_report','ribbon_payout_report','payback_report','judge_report','breed_judged_totals_report')
  and finalize_run_id is not null
  and is_current = true;

-- Completed tasks retain their status. Cancel unfinished work, including
-- older superseded tasks, so a worker cannot retry unnecessary internal reports.
update public.show_task_queue task
set task_status = 'cancelled'::public.show_task_status,
    lease_expires_at = null
from public.show_report_artifacts artifact
where task.report_artifact_id = artifact.id
  and artifact.report_name in ('unpaid_balances_report','paid_exhibitor_report','entered_exhibitors_contact_report','ribbon_payout_report','payback_report','judge_report','breed_judged_totals_report')
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
    and artifact.report_name in ('unpaid_balances_report','paid_exhibitor_report','entered_exhibitors_contact_report','ribbon_payout_report','payback_report','judge_report','breed_judged_totals_report')
    and artifact.finalize_run_id is not null
);

commit;
