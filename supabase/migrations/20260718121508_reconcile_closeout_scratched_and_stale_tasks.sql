-- Keep the render manifest aligned with entry changes made after finalization,
-- and recover legacy running tasks that never received a lease timestamp.

create or replace function public.recover_stale_report_render_tasks(
  p_limit integer default 25
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_obsolete integer := 0;
  v_recovered integer := 0;
begin
  with obsolete as (
    select a.id
    from public.show_report_artifacts a
    where a.is_current = true
      and a.report_name = 'exhibitor_report'::public.report_type
      and coalesce(a.metadata ->> 'exhibitor_id', '') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and not exists (
        select 1
        from public.entries e
        where e.show_id = a.show_id
          and e.exhibitor_id = (a.metadata ->> 'exhibitor_id')::uuid
          and e.section_id = any(coalesce(a.section_ids, '{}'::uuid[]))
          and e.is_shown = true
          and e.scratched_at is null
          and lower(btrim(coalesce(e.status, ''))) not in (
            'scratch', 'scratched', 'cancelled', 'canceled', 'deleted'
          )
      )
    for update skip locked
  ), cancelled_tasks as (
    update public.show_task_queue q
    set task_status = 'cancelled'::public.show_task_status,
        completed_at = now(),
        worker_id = null, claimed_by = null, claimed_at = null,
        heartbeat_at = null, lease_expires_at = null,
        error_category = 'scratched_entry',
        error_message = 'Skipped because this exhibitor has no non-scratched entries in the selected Closeout scope.',
        last_error = 'Closeout artifact automatically removed after its entries were scratched.'
    from obsolete o
    where q.report_artifact_id = o.id
      and q.task_type = 'render_report'::public.show_task_type
      and q.task_status <> 'completed'::public.show_task_status
    returning q.id
  )
  update public.show_report_artifacts a
  set is_current = false,
      superseded_at = coalesce(a.superseded_at, now())
  from obsolete o
  where a.id = o.id;
  get diagnostics v_obsolete = row_count;

  with stale as (
    select q.id
    from public.show_task_queue q
    where q.task_type = 'render_report'::public.show_task_type
      and q.task_status = 'running'::public.show_task_status
      and (
        q.lease_expires_at < now()
        or (
          q.lease_expires_at is null
          and coalesce(
            q.heartbeat_at, q.started_at, q.claimed_at, q.created_at
          ) < now() - interval '10 minutes'
        )
      )
    order by coalesce(
      q.lease_expires_at, q.heartbeat_at, q.started_at,
      q.claimed_at, q.created_at
    )
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 25), 100))
  )
  update public.show_task_queue q
  set task_status = 'failed'::public.show_task_status,
      failed_at = now(), available_at = now(), worker_id = null,
      claimed_by = null, heartbeat_at = null, lease_expires_at = null,
      error_category = 'worker_lease_expired',
      last_error = 'The renderer lease expired before completion.',
      error_message = 'Report generation was interrupted and will be retried.'
  from stale s
  where q.id = s.id;
  get diagnostics v_recovered = row_count;

  return v_obsolete + v_recovered;
end;
$function$;

revoke all on function public.recover_stale_report_render_tasks(integer)
  from public, anon, authenticated;
grant execute on function public.recover_stale_report_render_tasks(integer)
  to service_role;

-- Reconcile already-deployed current artifacts immediately. The renderer also
-- performs this reconciliation before every future claim cycle.
select public.recover_stale_report_render_tasks(100);
