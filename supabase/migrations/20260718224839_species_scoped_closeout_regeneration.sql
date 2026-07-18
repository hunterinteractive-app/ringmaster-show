create or replace function public.requeue_closeout_render_tasks_for_species(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_scope_key text,
  p_regenerate_all boolean default false,
  p_species_filter text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_species text := nullif(lower(btrim(coalesce(p_species_filter, ''))), '');
  v_repair jsonb;
  v_requeued integer := 0;
  v_inserted integer := 0;
begin
  if v_species is not null and v_species not in ('rabbit', 'cavy') then
    raise exception 'Unsupported closeout species filter: %', p_species_filter;
  end if;
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

  if p_regenerate_all then
    update public.show_report_artifacts a
    set artifact_status = 'failed'::public.artifact_status,
        metadata = a.metadata || jsonb_build_object(
          'error_category', 'invalid_scope',
          'error_message', 'Legacy artifact scope requires canonical repair.'
        )
    where a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true
      and a.report_name <> 'arba_report'::public.report_type
      and (v_species is null or lower(a.metadata ->> 'species') = v_species)
      and a.scope_key is distinct from public.closeout_artifact_scope_key(
        a.show_id, a.report_name, a.section_ids, a.metadata
      );
  end if;

  v_repair := public.repair_closeout_artifact_scopes(
    p_show_id, p_finalize_run_id
  );

  if p_regenerate_all then
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
      and a.report_name <> 'arba_report'::public.report_type
      and (v_species is null or lower(a.metadata ->> 'species') = v_species)
      and a.scope_key = public.closeout_artifact_scope_key(
        a.show_id, a.report_name, a.section_ids, a.metadata
      );
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
    and a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and a.report_name <> 'arba_report'::public.report_type
    and (v_species is null or lower(a.metadata ->> 'species') = v_species)
    and q.task_type = 'render_report'::public.show_task_type
    and (
      p_regenerate_all
      or (
        a.artifact_status in ('queued', 'failed')
        and q.task_status = 'failed'
        and q.attempt_count < q.max_attempts
      )
    );
  get diagnostics v_requeued = row_count;

  insert into public.show_task_queue (
    show_id, finalize_run_id, scope_key, task_type, task_status,
    report_artifact_id, payload, priority, available_at
  )
  select
    a.show_id,
    a.finalize_run_id,
    a.scope_key,
    'render_report'::public.show_task_type,
    'queued'::public.show_task_status,
    a.id,
    jsonb_build_object(
      'artifact_id', a.id,
      'report_name', a.report_name,
      'scope_key', a.scope_key,
      'section_ids', to_jsonb(a.section_ids),
      'generation', a.generation,
      'metadata', a.metadata
    ),
    case
      when a.report_name = 'details_by_breed'::public.report_type then 20
      when a.report_name = 'judge_report'::public.report_type then 30
      else 100
    end,
    now()
  from public.show_report_artifacts a
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and a.report_name <> 'arba_report'::public.report_type
    and (v_species is null or lower(a.metadata ->> 'species') = v_species)
    and a.artifact_status in ('queued', 'failed')
  on conflict (report_artifact_id, task_type)
    where report_artifact_id is not null
  do nothing;
  get diagnostics v_inserted = row_count;

  return jsonb_build_object(
    'finalize_run_id', p_finalize_run_id,
    'scope_key', p_scope_key,
    'species_filter', v_species,
    'repaired_count', coalesce((v_repair ->> 'repaired_count')::integer, 0),
    'unrepairable_count', coalesce(
      (v_repair ->> 'unrepairable_count')::integer, 0
    ),
    'unrepairable_reasons', coalesce(
      v_repair -> 'unrepairable_reasons', '{}'::jsonb
    ),
    'requeued_count', v_requeued,
    'inserted_count', v_inserted,
    'queued_count', v_requeued + v_inserted
  );
end;
$function$;

revoke all on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) from public, anon;
grant execute on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) to authenticated, service_role;

create or replace function public.get_closeout_dashboard_scoped_for_species(
  p_show_id uuid,
  p_scope_key text,
  p_section_ids uuid[],
  p_artifact_limit integer default 100,
  p_artifact_offset integer default 0,
  p_report_name public.report_type default null,
  p_species_filter text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_species text := nullif(lower(btrim(coalesce(p_species_filter, ''))), '');
  v_dashboard jsonb;
  v_run_id uuid;
  v_reports jsonb := '[]'::jsonb;
  v_review_reports jsonb := '[]'::jsonb;
  v_artifact_counts jsonb := '{}'::jsonb;
  v_task_counts jsonb := '{}'::jsonb;
begin
  if v_species is not null and v_species not in ('rabbit', 'cavy') then
    raise exception 'Unsupported closeout species filter: %', p_species_filter;
  end if;

  v_dashboard := public.get_closeout_dashboard_scoped(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );
  if v_species is null then
    return v_dashboard;
  end if;

  v_run_id := nullif(v_dashboard -> 'latest_finalize' ->> 'id', '')::uuid;
  if v_run_id is null then
    return v_dashboard;
  end if;

  select coalesce(jsonb_agg(report.value order by report.ordinality), '[]'::jsonb)
  into v_reports
  from jsonb_array_elements(coalesce(v_dashboard -> 'reports', '[]'::jsonb))
    with ordinality report(value, ordinality)
  where lower(coalesce(report.value -> 'metadata' ->> 'species', '')) = v_species;

  select coalesce(jsonb_agg(review.value order by review.ordinality), '[]'::jsonb)
  into v_review_reports
  from jsonb_array_elements(
    coalesce(v_dashboard -> 'review_reports', '[]'::jsonb)
  ) with ordinality review(value, ordinality)
  where lower(coalesce(
    review.value ->> 'species',
    review.value -> 'metadata' ->> 'species',
    ''
  )) = v_species;

  select jsonb_build_object(
    'total', count(*)::integer,
    'generated', count(*) filter (
      where a.artifact_status = 'generated'
    )::integer,
    'queued', count(*) filter (
      where a.artifact_status = 'queued'
    )::integer,
    'failed', count(*) filter (
      where a.artifact_status = 'failed'
    )::integer,
    'by_report', coalesce((
      select jsonb_object_agg(grouped.report_name, grouped.report_count)
      from (
        select species_artifact.report_name, count(*)::integer report_count
        from public.show_report_artifacts species_artifact
        where species_artifact.finalize_run_id = v_run_id
          and species_artifact.is_current = true
          and species_artifact.report_name <> 'arba_report'::public.report_type
          and lower(species_artifact.metadata ->> 'species') = v_species
          and (p_report_name is null or species_artifact.report_name = p_report_name)
        group by species_artifact.report_name
      ) grouped
    ), '{}'::jsonb)
  )
  into v_artifact_counts
  from public.show_report_artifacts a
  where a.finalize_run_id = v_run_id
    and a.is_current = true
    and a.report_name <> 'arba_report'::public.report_type
    and lower(a.metadata ->> 'species') = v_species
    and (p_report_name is null or a.report_name = p_report_name);

  with species_artifacts as (
    select a.id, a.artifact_status
    from public.show_report_artifacts a
    where a.finalize_run_id = v_run_id
      and a.is_current = true
      and a.report_name <> 'arba_report'::public.report_type
      and lower(a.metadata ->> 'species') = v_species
      and (p_report_name is null or a.report_name = p_report_name)
  ), counts as (
    select
      count(*) filter (where q.task_status = 'queued')::integer queued,
      count(*) filter (where q.task_status = 'running')::integer running,
      count(*) filter (where q.task_status = 'failed')::integer failed,
      count(*) filter (where q.task_status = 'completed')::integer completed,
      count(*) filter (
        where q.task_status = 'failed'
          and q.attempt_count < q.max_attempts
      )::integer retryable_failed,
      max(coalesce(
        q.completed_at,
        q.failed_at,
        q.heartbeat_at,
        q.claimed_at,
        q.started_at,
        q.created_at
      )) last_activity_at,
      max(q.completed_at) completed_at
    from public.show_task_queue q
    join species_artifacts a on a.id = q.report_artifact_id
    where q.task_type = 'render_report'::public.show_task_type
  ), missing as (
    select count(*)::integer missing_count
    from species_artifacts a
    where a.artifact_status in ('queued', 'failed')
      and not exists (
        select 1
        from public.show_task_queue q
        where q.report_artifact_id = a.id
          and q.task_type = 'render_report'::public.show_task_type
      )
  )
  select jsonb_build_object(
    'queued', coalesce(c.queued, 0),
    'running', coalesce(c.running, 0),
    'failed', coalesce(c.failed, 0),
    'completed', coalesce(c.completed, 0),
    'retryable_failed', coalesce(c.retryable_failed, 0),
    'remaining', coalesce(c.retryable_failed, 0) + coalesce(m.missing_count, 0),
    'last_activity_at', c.last_activity_at,
    'completed_at', c.completed_at
  )
  into v_task_counts
  from counts c
  cross join missing m;

  v_dashboard := jsonb_set(v_dashboard, '{reports}', v_reports, true);
  v_dashboard := jsonb_set(
    v_dashboard, '{review_reports}', v_review_reports, true
  );
  v_dashboard := jsonb_set(
    v_dashboard, '{artifact_counts}', v_artifact_counts, true
  );
  v_dashboard := jsonb_set(v_dashboard, '{task_counts}', v_task_counts, true);
  v_dashboard := jsonb_set(
    v_dashboard,
    '{dashboard,closeout,reports_generated_count}',
    to_jsonb(coalesce((v_artifact_counts ->> 'generated')::integer, 0)),
    true
  );
  return v_dashboard;
end;
$function$;

revoke all on function public.get_closeout_dashboard_scoped_for_species(
  uuid, text, uuid[], integer, integer, public.report_type, text
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped_for_species(
  uuid, text, uuid[], integer, integer, public.report_type, text
) to authenticated, service_role;

comment on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) is 'Regenerates all reports or only artifacts explicitly tagged for the requested rabbit/cavy species.';

comment on function public.get_closeout_dashboard_scoped_for_species(
  uuid, text, uuid[], integer, integer, public.report_type, text
) is 'Returns closeout artifacts and progress filtered to an explicit rabbit/cavy species when requested.';
