-- Keep the closeout progress poll cheap while hundreds of reports render.
-- Retryable task failures are still active work; only exhausted tasks are
-- reported as failed to the secretary.
create schema if not exists report_generation_private;
revoke all on schema report_generation_private from public, anon;
grant usage on schema report_generation_private to authenticated, service_role;

create or replace function report_generation_private.get_closeout_report_generation_progress(
  p_show_id uuid,
  p_finalize_run_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_finalize_run_id uuid;
  v_scope_key text;
  v_section_ids uuid[];
begin
  if p_show_id is null then
    raise exception 'show_id is required'
      using errcode = '22023';
  end if;

  if auth.uid() is not null
     and not public.user_can_finalize_show(p_show_id, auth.uid()) then
    raise exception 'Not authorized to manage closeout for this show'
      using errcode = '42501';
  end if;

  select run.id, run.scope_key, run.section_ids
  into v_finalize_run_id, v_scope_key, v_section_ids
  from public.show_finalize_runs run
  where run.show_id = p_show_id
    and (p_finalize_run_id is null or run.id = p_finalize_run_id)
  order by run.created_at desc, run.id desc
  limit 1;

  if v_finalize_run_id is null then
    if p_finalize_run_id is not null then
      raise exception 'Closeout run not found' using errcode = 'P0002';
    end if;

    return jsonb_build_object(
      'finalize_run_id', null,
      'scope_key', null,
      'section_ids', '[]'::jsonb,
      'task_counts', jsonb_build_object(
        'queued', 0, 'running', 0, 'completed', 0,
        'failed', 0, 'retryable_failed', 0
      ),
      'artifact_counts', jsonb_build_object(
        'total', 0, 'generated', 0, 'failed', 0
      )
    );
  end if;

  with scoped_artifacts as (
    select artifact.id, artifact.artifact_status
    from public.show_report_artifacts artifact
    where artifact.show_id = p_show_id
      and artifact.finalize_run_id = v_finalize_run_id
      and artifact.is_current = true
      and artifact.report_name <> 'arba_report'::public.report_type
  ),
  scoped_tasks as (
    select
      task.task_status,
      task.attempt_count,
      task.max_attempts,
      artifact.artifact_status
    from scoped_artifacts artifact
    left join public.show_task_queue task
      on task.report_artifact_id = artifact.id
     and task.task_type = 'render_report'::public.show_task_type
  ),
  counts as (
    select
      count(*)::integer as report_total,
      count(*) filter (
        where artifact_status in (
          'generated'::public.artifact_status,
          'warning'::public.artifact_status
        )
      )::integer as generated,
      count(*) filter (
        where task_status = 'completed'::public.show_task_status
      )::integer as completed,
      count(*) filter (
        where task_status = 'running'::public.show_task_status
      )::integer as running,
      count(*) filter (
        where task_status = 'queued'::public.show_task_status
           or (
             task_status = 'failed'::public.show_task_status
             and attempt_count < max_attempts
           )
      )::integer as queued,
      count(*) filter (
        where task_status = 'failed'::public.show_task_status
          and attempt_count < max_attempts
      )::integer as retryable_failed,
      count(*) filter (
        where task_status = 'failed'::public.show_task_status
          and attempt_count >= max_attempts
      )::integer as failed
    from scoped_tasks
  )
  select jsonb_build_object(
    'finalize_run_id', v_finalize_run_id,
    'scope_key', v_scope_key,
    'section_ids', to_jsonb(coalesce(v_section_ids, array[]::uuid[])),
    'task_counts', jsonb_build_object(
      'queued', counts.queued,
      'running', counts.running,
      'completed', counts.completed,
      'failed', counts.failed,
      'retryable_failed', counts.retryable_failed
    ),
    'artifact_counts', jsonb_build_object(
      'total', counts.report_total,
      'generated', counts.generated,
      'failed', counts.failed
    )
  )
  into v_result
  from counts;

  return coalesce(v_result, jsonb_build_object(
    'finalize_run_id', v_finalize_run_id,
    'scope_key', v_scope_key,
    'section_ids', to_jsonb(coalesce(v_section_ids, array[]::uuid[])),
    'task_counts', jsonb_build_object(
      'queued', 0, 'running', 0, 'completed', 0,
      'failed', 0, 'retryable_failed', 0
    ),
    'artifact_counts', jsonb_build_object(
      'total', 0, 'generated', 0, 'failed', 0
    )
  ));
end;
$function$;

revoke all on function report_generation_private.get_closeout_report_generation_progress(uuid, uuid)
  from public, anon;
grant execute on function report_generation_private.get_closeout_report_generation_progress(uuid, uuid)
  to authenticated, service_role;

comment on function report_generation_private.get_closeout_report_generation_progress(uuid, uuid)
is 'Lightweight closeout render progress for polling; retryable failures remain queued until attempts are exhausted.';

create or replace function public.get_closeout_report_generation_progress(
  p_show_id uuid,
  p_finalize_run_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select report_generation_private.get_closeout_report_generation_progress(
    p_show_id,
    p_finalize_run_id
  );
$function$;

revoke all on function public.get_closeout_report_generation_progress(uuid, uuid)
  from public, anon;
grant execute on function public.get_closeout_report_generation_progress(uuid, uuid)
  to authenticated, service_role;

comment on function public.get_closeout_report_generation_progress(uuid, uuid)
is 'Authorized Data API wrapper for lightweight closeout render progress.';


-- Check-in sheet rendering previously called report_checkin_entries once per
-- section and exhibitor. That function refreshes every persisted balance for
-- the show, so concurrent renderers repeatedly updated the same rows and
-- deadlocked. The worker-specific source below is a single read-only query,
-- scoped to the one exhibitor and the requested sections.
create or replace function public.report_closeout_checkin_entries(
  p_show_id uuid,
  p_exhibitor_id uuid,
  p_section_ids uuid[],
  p_include_scratched boolean default false
)
returns table(
  entry_id uuid,
  show_id uuid,
  section_id uuid,
  exhibitor_id uuid,
  exhibitor_label text,
  exhibitor_showing_name text,
  exhibitor_display_name text,
  exhibitor_first_name text,
  exhibitor_last_name text,
  exhibitor_arba_number text,
  exhibitor_address_line1 text,
  exhibitor_address_line2 text,
  exhibitor_city text,
  exhibitor_state text,
  exhibitor_zip text,
  exhibitor_phone text,
  exhibitor_email text,
  section_letter text,
  section_display_name text,
  section_kind text,
  section_sort_order integer,
  species text,
  breed text,
  group_name text,
  group_sort_order integer,
  variety text,
  variety_sort_order integer,
  sex text,
  class_name text,
  class_age_label text,
  class_sort_order integer,
  tattoo text,
  scratched_at timestamptz,
  created_at timestamptz,
  entry_fee_cents numeric,
  balance_due_all_shows numeric,
  balance_due_this_show numeric
)
language sql
stable
security invoker
set search_path = ''
as $function$
  with authoritative_balance as (
    select balance.exhibitor_id, balance.balance_due_cents
    from public.show_exhibitor_balances balance
    where balance.show_id = p_show_id
      and balance.exhibitor_id = p_exhibitor_id
      and (
        balance.source = 'entries'
        or not exists (
          select 1
          from public.show_exhibitor_balances entries_balance
          where entries_balance.show_id = balance.show_id
            and entries_balance.exhibitor_id = balance.exhibitor_id
            and entries_balance.source = 'entries'
        )
      )
    order by (balance.source = 'entries') desc, balance.updated_at desc
    limit 1
  )
  select
    report_entry.entry_id,
    report_entry.show_id,
    report_entry.section_id,
    report_entry.exhibitor_id,
    report_entry.exhibitor_label,
    report_entry.exhibitor_showing_name,
    report_entry.exhibitor_display_name,
    report_entry.exhibitor_first_name,
    report_entry.exhibitor_last_name,
    report_entry.exhibitor_arba_number,
    report_entry.exhibitor_address_line1,
    report_entry.exhibitor_address_line2,
    report_entry.exhibitor_city,
    report_entry.exhibitor_state,
    report_entry.exhibitor_zip,
    report_entry.exhibitor_phone,
    report_entry.exhibitor_email,
    report_entry.section_letter,
    report_entry.section_display_name,
    report_entry.section_kind::text,
    report_entry.section_sort_order,
    report_entry.species::text,
    report_entry.breed,
    report_entry.group_name,
    report_entry.group_sort_order,
    report_entry.variety,
    report_entry.variety_sort_order,
    report_entry.sex,
    report_entry.class_name,
    report_entry.class_age_label,
    report_entry.class_sort_order,
    report_entry.tattoo,
    report_entry.scratched_at,
    report_entry.created_at,
    round(coalesce(fees.fee_per_entry, 0) * 100)::numeric,
    coalesce(balance.balance_due_cents, 0)::numeric / 100.0,
    coalesce(balance.balance_due_cents, 0)::numeric / 100.0
  from public.report_entry_base_v report_entry
  left join public.show_section_fee_settings fees
    on fees.section_id = report_entry.section_id
  left join authoritative_balance balance
    on balance.exhibitor_id = report_entry.exhibitor_id
  where report_entry.show_id = p_show_id
    and report_entry.exhibitor_id = p_exhibitor_id
    and report_entry.section_id = any(p_section_ids)
    and (p_include_scratched or report_entry.scratched_at is null)
  order by
    case
      when lower(coalesce(report_entry.section_kind::text, '')) = 'open' then 1
      when lower(coalesce(report_entry.section_kind::text, '')) = 'youth' then 2
      else 99
    end,
    coalesce(report_entry.section_sort_order, 9999),
    coalesce(report_entry.section_letter, ''),
    lower(coalesce(report_entry.breed, '')),
    coalesce(report_entry.group_sort_order, 9999),
    lower(coalesce(report_entry.group_name, '')),
    coalesce(report_entry.variety_sort_order, 9999),
    lower(coalesce(report_entry.variety, '')),
    coalesce(report_entry.class_sort_order, 9999),
    lower(coalesce(report_entry.tattoo, ''));
$function$;

revoke all on function public.report_closeout_checkin_entries(uuid, uuid, uuid[], boolean)
  from public, anon, authenticated;
grant execute on function public.report_closeout_checkin_entries(uuid, uuid, uuid[], boolean)
  to service_role;

comment on function public.report_closeout_checkin_entries(uuid, uuid, uuid[], boolean)
is 'Read-only closeout check-in rows for one exhibitor and exact sections; avoids concurrent balance refresh writes.';
