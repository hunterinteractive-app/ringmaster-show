update public.show_task_queue
set
  task_status = 'failed'::public.show_task_status,
  attempt_count = max_attempts,
  failed_at = coalesce(failed_at, now()),
  completed_at = null,
  claimed_at = null,
  claimed_by = null,
  started_at = null,
  worker_id = null,
  heartbeat_at = null,
  lease_expires_at = null,
  error_category = 'legacy_queue_quarantined',
  error_message =
    'Legacy render task quarantined during deployment of the database-backed renderer.',
  last_error =
    'Legacy task lacks reliable artifact-specific structured scope metadata.'
where task_type = 'render_report'::public.show_task_type
  and created_at < timestamptz '2026-07-14 05:51:53+00'
  and task_status in (
    'queued'::public.show_task_status,
    'running'::public.show_task_status,
    'failed'::public.show_task_status
  );
