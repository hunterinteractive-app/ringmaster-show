-- Separate the finalize-run selection scope from the immutable scope of each
-- report artifact. Historical artifacts and tasks are preserved. The repair
-- command below creates replacement artifacts only when the scope can be
-- derived from relational data and the existing structured report identity.

create or replace function public.closeout_artifact_identity(
  p_report_name public.report_type,
  p_metadata jsonb
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select concat_ws('|',
    p_report_name::text,
    btrim(coalesce(p_metadata ->> 'section_id', '')),
    btrim(coalesce(p_metadata ->> 'exhibitor_id', '')),
    lower(btrim(coalesce(p_metadata ->> 'breed_name', ''))),
    lower(btrim(coalesce(p_metadata ->> 'club_name', ''))),
    case when jsonb_typeof(p_metadata -> 'species') = 'string'
      then lower(btrim(p_metadata ->> 'species')) else '' end,
    upper(btrim(coalesce(p_metadata ->> 'scope', ''))),
    upper(btrim(coalesce(p_metadata ->> 'show_letter', ''))),
    upper(btrim(coalesce(p_metadata ->> 'sanctioning_body', ''))),
    lower(btrim(coalesce(p_metadata ->> 'delivery_type', ''))),
    btrim(coalesce(p_metadata ->> 'judge_id', '')),
    lower(btrim(coalesce(p_metadata ->> 'report_scope', '')))
  );
$function$;

create or replace function public.closeout_artifact_scope_key(
  p_show_id uuid,
  p_report_name public.report_type,
  p_section_ids uuid[],
  p_metadata jsonb
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select p_show_id::text || ':' ||
    array_to_string(array(
      select distinct section_id
      from unnest(coalesce(p_section_ids, '{}'::uuid[])) section_id
      order by section_id
    ), ',') || ':' ||
    md5(public.closeout_artifact_identity(p_report_name, p_metadata));
$function$;

create or replace function public.resolve_closeout_artifact_scope(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_report_name public.report_type,
  p_metadata jsonb
)
returns table(
  is_repairable boolean,
  failure_reason text,
  scope_key text,
  section_ids uuid[],
  metadata jsonb,
  artifact_key text
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_run public.show_finalize_runs%rowtype;
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_section public.show_sections%rowtype;
  v_section_id uuid;
  v_exhibitor_id uuid;
  v_sections uuid[];
  v_species text;
  v_identity text;
begin
  select f.* into v_run
  from public.show_finalize_runs f
  where f.id = p_finalize_run_id and f.show_id = p_show_id;

  if v_run.id is null or cardinality(coalesce(v_run.section_ids, '{}'::uuid[])) = 0 then
    return query select false, 'missing_finalize_run_scope', null::text,
      '{}'::uuid[], v_metadata, null::text;
    return;
  end if;

  if p_report_name::text in (
    'arba_report', 'sweepstakes_report', 'breed_results_detail_report',
    'details_by_breed', 'exh_by_breed', 'best_display_report'
  ) then
    if coalesce(v_metadata ->> 'section_id', '') !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return query select false, 'missing_section_id', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_section_id := (v_metadata ->> 'section_id')::uuid;
    select s.* into v_section
    from public.show_sections s
    where s.id = v_section_id and s.show_id = p_show_id
      and s.id = any(v_run.section_ids);
    if v_section.id is null then
      return query select false, 'section_not_in_finalize_scope', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    if nullif(btrim(v_metadata ->> 'scope'), '') is not null
       and upper(btrim(v_metadata ->> 'scope')) <> upper(v_section.kind::text) then
      return query select false, 'section_kind_mismatch', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    if nullif(btrim(v_metadata ->> 'show_letter'), '') is not null
       and upper(btrim(v_metadata ->> 'show_letter')) <> upper(v_section.letter) then
      return query select false, 'show_letter_mismatch', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_sections := array[v_section.id];
    v_metadata := v_metadata || jsonb_build_object(
      'section_id', v_section.id,
      'scope', upper(v_section.kind::text),
      'show_letter', upper(v_section.letter)
    );

    if p_report_name::text in (
      'sweepstakes_report', 'breed_results_detail_report',
      'details_by_breed', 'exh_by_breed', 'best_display_report'
    ) then
      if nullif(btrim(v_metadata ->> 'breed_name'), '') is null
         and p_report_name::text in ('sweepstakes_report', 'breed_results_detail_report') then
        return query select false, 'missing_breed_name', null::text,
          '{}'::uuid[], v_metadata, null::text;
        return;
      end if;
      v_species := lower(nullif(btrim(v_metadata ->> 'species'), ''));
      if v_species is null and nullif(btrim(v_metadata ->> 'breed_name'), '') is not null then
        select case when count(distinct lower(b.species::text)) = 1
                    then min(lower(b.species::text)) end
        into v_species
        from public.breeds b
        where lower(btrim(b.name)) = lower(btrim(v_metadata ->> 'breed_name'));
      end if;
      if v_species is null then
        select case when count(distinct lower(e.species::text)) = 1
                    then min(lower(e.species::text)) end
        into v_species
        from public.entries e
        where e.show_id = p_show_id and e.section_id = v_section.id
          and e.is_shown = true and e.scratched_at is null;
      end if;
      if v_species not in ('rabbit', 'cavy') then
        return query select false, 'ambiguous_species', null::text,
          '{}'::uuid[], v_metadata, null::text;
        return;
      end if;
      v_metadata := v_metadata || jsonb_build_object('species', v_species);
    end if;
  elsif p_report_name::text in ('exhibitor_report', 'checkin_sheet', 'legs') then
    if coalesce(v_metadata ->> 'exhibitor_id', '') !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return query select false, 'missing_exhibitor_id', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_exhibitor_id := (v_metadata ->> 'exhibitor_id')::uuid;
    select array_agg(distinct e.section_id order by e.section_id)
    into v_sections
    from public.entries e
    where e.show_id = p_show_id and e.exhibitor_id = v_exhibitor_id
      and e.section_id = any(v_run.section_ids)
      and e.is_shown = true and e.scratched_at is null
      and lower(coalesce(e.status, '')) <> 'scratched';
    if cardinality(coalesce(v_sections, '{}'::uuid[])) = 0 then
      return query select false, 'exhibitor_has_no_qualifying_entries', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
  elsif p_report_name::text in (
    'unpaid_balances_report', 'paid_exhibitor_report',
    'entered_exhibitors_contact_report', 'ribbon_payout_report',
    'payback_report', 'judge_report', 'breed_judged_totals_report'
  ) then
    v_sections := v_run.section_ids;
  else
    return query select false, 'unsupported_report_scope', null::text,
      '{}'::uuid[], v_metadata, null::text;
    return;
  end if;

  v_sections := array(
    select distinct section_id from unnest(v_sections) section_id order by section_id
  );
  v_metadata := v_metadata || jsonb_build_object(
    'run_scope_key', v_run.scope_key,
    'section_ids', to_jsonb(v_sections)
  );
  v_identity := public.closeout_artifact_identity(p_report_name, v_metadata);
  scope_key := public.closeout_artifact_scope_key(
    p_show_id, p_report_name, v_sections, v_metadata
  );
  metadata := v_metadata || jsonb_build_object('scope_key', scope_key);
  section_ids := v_sections;
  artifact_key := v_identity;
  is_repairable := true;
  failure_reason := null;
  return next;
end;
$function$;

create or replace function public.set_closeout_artifact_scope_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_scope record;
begin
  if new.finalize_run_id is not null then
    if tg_op = 'UPDATE'
       and old.show_id = new.show_id
       and old.finalize_run_id = new.finalize_run_id
       and old.report_name = new.report_name
       and old.artifact_key = public.closeout_artifact_identity(
         new.report_name, new.metadata
       )
       and old.scope_key = public.closeout_artifact_scope_key(
         old.show_id, old.report_name, old.section_ids, old.metadata
       ) then
      new.scope_key := old.scope_key;
      new.section_ids := old.section_ids;
      new.artifact_key := old.artifact_key;
      new.metadata := new.metadata || jsonb_build_object(
        'scope_key', old.scope_key,
        'section_ids', to_jsonb(old.section_ids),
        'run_scope_key', old.metadata ->> 'run_scope_key'
      );
    else
    select * into v_scope
    from public.resolve_closeout_artifact_scope(
      new.show_id, new.finalize_run_id, new.report_name, new.metadata
    );
    if not coalesce(v_scope.is_repairable, false) then
      raise exception 'Cannot derive canonical closeout artifact scope: %',
        coalesce(v_scope.failure_reason, 'unknown_scope');
    end if;
    new.scope_key := v_scope.scope_key;
    new.section_ids := v_scope.section_ids;
    new.metadata := v_scope.metadata;
    new.artifact_key := v_scope.artifact_key;
    end if;
  end if;
  if new.finalize_run_id is not null and new.id is not null then
    new.storage_bucket := coalesce(nullif(new.storage_bucket, ''), 'show-files');
    new.storage_path := coalesce(nullif(new.storage_path, ''), format(
      'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
      new.show_id, new.finalize_run_id, new.id, new.generation
    ));
  end if;
  return new;
end;
$function$;

create or replace function public.supersede_prior_closeout_scope_artifacts()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if nullif(btrim(new.scope_key), '') is not null then
    update public.show_report_artifacts a
    set is_current = false, superseded_at = coalesce(a.superseded_at, now())
    where a.show_id = new.show_id and a.is_current = true
      and a.finalize_run_id in (
        select f.id from public.show_finalize_runs f
        where f.show_id = new.show_id and f.id <> new.id
          and f.scope_key = new.scope_key and f.section_ids = new.section_ids
      );
  end if;
  return new;
end;
$function$;

drop trigger if exists supersede_prior_closeout_scope_artifacts
  on public.show_finalize_runs;
create trigger supersede_prior_closeout_scope_artifacts
after insert on public.show_finalize_runs
for each row execute function public.supersede_prior_closeout_scope_artifacts();

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

    select a.id into v_replacement_id
    from public.show_report_artifacts a
    where a.finalize_run_id = v_artifact.finalize_run_id
      and a.artifact_key = v_scope.artifact_key
      and a.is_current = true and a.id <> v_artifact.id
    limit 1;

    if v_replacement_id is null then
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

create or replace function public.enqueue_report_render_tasks(
  p_show_id uuid,
  p_finalize_run_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
begin
  insert into public.show_task_queue (
    show_id, finalize_run_id, scope_key, task_type, task_status,
    report_artifact_id, payload, priority, available_at
  )
  select
    a.show_id, a.finalize_run_id, a.scope_key,
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
      when a.report_name = 'arba_report'::public.report_type then 10
      when a.report_name = 'details_by_breed'::public.report_type then 20
      when a.report_name = 'judge_report'::public.report_type then 30
      else 100
    end,
    now()
  from public.show_report_artifacts a
  where a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and a.artifact_status in (
      'queued'::public.artifact_status, 'failed'::public.artifact_status
    )
    and cardinality(coalesce(a.section_ids, '{}'::uuid[])) > 0
    and a.metadata ->> 'scope_key' = a.scope_key
    and a.metadata -> 'section_ids' = to_jsonb(a.section_ids)
    and a.scope_key = public.closeout_artifact_scope_key(
      a.show_id, a.report_name, a.section_ids, a.metadata
    )
  on conflict (report_artifact_id, task_type)
    where report_artifact_id is not null
  do nothing;
  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

create or replace function public.requeue_closeout_render_tasks(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_scope_key text,
  p_regenerate_all boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_repair jsonb;
  v_requeued integer := 0;
  v_inserted integer := 0;
begin
  if auth.uid() is not null
     and not public.user_can_finalize_show(p_show_id, auth.uid()) then
    raise exception 'Not authorized to manage closeout for this show';
  end if;
  if not exists (
    select 1 from public.show_finalize_runs f
    where f.id = p_finalize_run_id and f.show_id = p_show_id
      and f.scope_key = p_scope_key
  ) then
    raise exception 'Finalize run does not match the requested show and scope';
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
        file_name = null, mime_type = null, file_size_bytes = null,
        file_hash_sha256 = null, generated_at = null, error_count = 0,
        generation = a.generation + 1,
        metadata = a.metadata - 'error_category' - 'error_message'
    where a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true
      and a.scope_key = public.closeout_artifact_scope_key(
        a.show_id, a.report_name, a.section_ids, a.metadata
      );
  end if;

  update public.show_task_queue q
  set task_status = 'queued'::public.show_task_status,
      scope_key = a.scope_key, available_at = now(),
      started_at = null, completed_at = null, failed_at = null,
      worker_id = null, claimed_by = null, claimed_at = null,
      last_error = null, error_message = null, error_category = null,
      heartbeat_at = null, lease_expires_at = null, attempt_count = 0,
      payload = jsonb_build_object(
        'artifact_id', a.id, 'report_name', a.report_name,
        'scope_key', a.scope_key, 'section_ids', to_jsonb(a.section_ids),
        'generation', a.generation, 'metadata', a.metadata
      )
  from public.show_report_artifacts a
  where q.report_artifact_id = a.id
    and a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and q.task_type = 'render_report'::public.show_task_type
    and (
      p_regenerate_all
      or (a.artifact_status in ('queued','failed')
          and q.task_status = 'failed' and q.attempt_count < q.max_attempts)
    );
  get diagnostics v_requeued = row_count;

  select public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id)
  into v_inserted;
  return jsonb_build_object(
    'finalize_run_id', p_finalize_run_id,
    'scope_key', p_scope_key,
    'repaired_count', coalesce((v_repair ->> 'repaired_count')::integer, 0),
    'unrepairable_count', coalesce((v_repair ->> 'unrepairable_count')::integer, 0),
    'unrepairable_reasons', coalesce(v_repair -> 'unrepairable_reasons', '{}'::jsonb),
    'requeued_count', v_requeued,
    'inserted_count', v_inserted,
    'queued_count', v_requeued + v_inserted +
      coalesce((v_repair ->> 'queued_count')::integer, 0)
  );
end;
$function$;

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
begin
  if auth.uid() is not null
     and not public.user_can_finalize_show(p_show_id, auth.uid()) then
    raise exception 'Not authorized to manage closeout for this show';
  end if;
  if not exists (
    select 1 from public.show_finalize_runs f
    where f.id = p_finalize_run_id and f.show_id = p_show_id
      and f.scope_key = p_scope_key
  ) then
    raise exception 'Finalize run does not match the requested show and scope';
  end if;

  update public.show_report_artifacts a
  set artifact_status = 'queued'::public.artifact_status,
      storage_bucket = 'show-files',
      storage_path = format(
        'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
        a.show_id, a.finalize_run_id, a.id, a.generation + 1
      ),
      file_name = null, mime_type = null, file_size_bytes = null,
      file_hash_sha256 = null, generated_at = null, error_count = 0,
      generation = a.generation + 1,
      metadata = a.metadata - 'error_category' - 'error_message'
  where a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and (p_report_name is null or a.report_name = p_report_name)
    and (p_artifact_id is null or a.id = p_artifact_id)
    and a.scope_key = public.closeout_artifact_scope_key(
      a.show_id, a.report_name, a.section_ids, a.metadata
    );
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'No canonical artifact matched the requested finalize run and scope';
  end if;

  update public.show_task_queue q
  set task_status = 'queued'::public.show_task_status,
      scope_key = a.scope_key, available_at = now(),
      started_at = null, completed_at = null, failed_at = null,
      worker_id = null, claimed_by = null, claimed_at = null,
      last_error = null, error_message = null, error_category = null,
      heartbeat_at = null, lease_expires_at = null, attempt_count = 0,
      payload = jsonb_build_object(
        'artifact_id', a.id, 'report_name', a.report_name,
        'scope_key', a.scope_key, 'section_ids', to_jsonb(a.section_ids),
        'generation', a.generation, 'metadata', a.metadata
      )
  from public.show_report_artifacts a
  where q.report_artifact_id = a.id and a.is_current = true
    and a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
    and (p_report_name is null or a.report_name = p_report_name)
    and (p_artifact_id is null or a.id = p_artifact_id)
    and q.task_type = 'render_report'::public.show_task_type;

  perform public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id);
  return jsonb_build_object(
    'queued_count', v_count, 'scope_key', p_scope_key,
    'finalize_run_id', p_finalize_run_id
  );
end;
$function$;

create or replace function public.get_closeout_dashboard_scoped(
  p_show_id uuid,
  p_scope_key text,
  p_section_ids uuid[],
  p_artifact_limit integer default 100,
  p_artifact_offset integer default 0,
  p_report_name public.report_type default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  with requested as (
    select
      greatest(1, least(coalesce(p_artifact_limit, 100), 200)) page_limit,
      greatest(0, coalesce(p_artifact_offset, 0)) page_offset
  ),
  show_row as (
    select s.id, s.name, s.results_version, s.results_last_changed_at
    from public.shows s where s.id = p_show_id
  ),
  state_row as (
    select cs.* from public.show_closeout_state cs where cs.show_id = p_show_id
  ),
  selected_run as (
    select f.id, f.run_status, f.started_at, f.completed_at, f.scope_key,
           f.scope_label, f.section_ids
    from public.show_finalize_runs f
    where f.show_id = p_show_id and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  current_artifacts as (
    select a.*
    from public.show_report_artifacts a
    join selected_run r on r.id = a.finalize_run_id
    where a.show_id = p_show_id and a.is_current = true
  ),
  artifact_counts as (
    select
      count(*)::integer total,
      count(*) filter (where a.artifact_status = 'generated')::integer generated,
      count(*) filter (where a.artifact_status = 'queued')::integer queued,
      count(*) filter (where a.artifact_status = 'failed')::integer failed,
      coalesce(jsonb_object_agg(a.report_name, a.report_count), '{}'::jsonb) by_report
    from (
      select a.report_name, a.artifact_status,
             count(*) over (partition by a.report_name)::integer report_count
      from current_artifacts a
    ) a
  ),
  task_base as (
    select q.*, a.artifact_status, a.metadata artifact_metadata
    from public.show_task_queue q
    join current_artifacts a on a.id = q.report_artifact_id
    where q.show_id = p_show_id
      and q.task_type = 'render_report'::public.show_task_type
  ),
  repairable_invalid as (
    select count(*)::integer repairable_count
    from current_artifacts a
    cross join lateral public.resolve_closeout_artifact_scope(
      a.show_id, a.finalize_run_id, a.report_name, a.metadata
    ) scope
    where a.artifact_status = 'failed'
      and a.metadata ->> 'error_category' = 'invalid_scope'
      and scope.is_repairable
  ),
  task_counts as (
    select
      count(*) filter (where q.task_status = 'queued')::integer queued,
      count(*) filter (where q.task_status = 'running')::integer running,
      count(*) filter (where q.task_status = 'failed')::integer failed,
      count(*) filter (where q.task_status = 'completed')::integer completed,
      (
        count(*) filter (
          where q.task_status = 'failed' and q.attempt_count < q.max_attempts
        ) + (select repairable_count from repairable_invalid)
      )::integer retryable_failed,
      (select count(*)::integer from current_artifacts a
       where a.artifact_status in ('queued','failed')) remaining
    from task_base q
  ),
  artifact_page as (
    select a.*
    from current_artifacts a
    cross join requested req
    where p_report_name is null or a.report_name = p_report_name
    order by a.report_name, a.created_at, a.id
    limit (select page_limit from requested)
    offset (select page_offset from requested)
  )
  select jsonb_build_object(
    'dashboard', jsonb_build_object(
      'show_id', s.id, 'show_name', s.name,
      'results_version', coalesce(s.results_version, 0),
      'results_last_changed_at', s.results_last_changed_at,
      'closeout', jsonb_build_object(
        'sync_status', coalesce(cs.sync_status::text, 'not_ready'),
        'is_points_stale', coalesce(cs.is_points_stale, true),
        'is_reports_stale', coalesce(ac.queued + ac.failed > 0, true),
        'has_warnings', coalesce(cs.has_warnings, false),
        'has_blocking_errors', coalesce(cs.has_blocking_errors, false),
        'is_archived', coalesce(cs.is_archived, false),
        'warning_count', coalesce(cs.warning_count, 0),
        'error_count', coalesce(cs.error_count, 0),
        'blocking_error_count', coalesce(cs.blocking_error_count, 0),
        'reports_generated_count', coalesce(ac.generated, 0),
        'finalized_at', r.completed_at,
        'points_generated_at', cs.points_generated_at,
        'reports_generated_at', cs.reports_generated_at,
        'validation_checked_at', cs.validation_checked_at,
        'last_finalize_message', cs.last_finalize_message
      )
    ),
    'results_readiness', jsonb_build_object(
      'ready', not coalesce(cs.has_blocking_errors, false),
      'missing_placement_count', 0, 'missing_judge_count', 0,
      'duplicate_placement_group_count', 0,
      'missing_final_award_count', 0, 'duplicate_final_award_count', 0
    ),
    'latest_finalize', coalesce(to_jsonb(r), '{}'::jsonb),
    'artifact_counts', jsonb_build_object(
      'total', coalesce(ac.total, 0), 'generated', coalesce(ac.generated, 0),
      'queued', coalesce(ac.queued, 0), 'failed', coalesce(ac.failed, 0),
      'by_report', coalesce(ac.by_report, '{}'::jsonb)
    ),
    'task_counts', jsonb_build_object(
      'queued', coalesce(tc.queued, 0), 'running', coalesce(tc.running, 0),
      'failed', coalesce(tc.failed, 0), 'completed', coalesce(tc.completed, 0),
      'retryable_failed', coalesce(tc.retryable_failed, 0),
      'remaining', coalesce(tc.remaining, 0)
    ),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'finalize_run_id', a.finalize_run_id,
        'report_name', a.report_name, 'artifact_status', a.artifact_status,
        'file_name', a.file_name, 'storage_bucket', a.storage_bucket,
        'storage_path', a.storage_path, 'generated_at', a.generated_at,
        'is_current', a.is_current, 'scope_key', a.scope_key,
        'section_ids', to_jsonb(a.section_ids), 'metadata', a.metadata
      ) order by a.report_name, a.created_at, a.id)
      from artifact_page a
    ), '[]'::jsonb),
    'artifact_page', jsonb_build_object(
      'limit', (select page_limit from requested),
      'offset', (select page_offset from requested),
      'has_more', coalesce(ac.total, 0) >
        (select page_limit + page_offset from requested)
    ),
    'deliveries', '[]'::jsonb,
    'latest_archive', '{}'::jsonb
  )
  from show_row s
  left join state_row cs on true
  left join selected_run r on true
  cross join artifact_counts ac
  cross join task_counts tc;
$function$;

revoke all on function public.requeue_closeout_render_tasks(uuid, uuid, text, boolean)
  from public, anon;
grant execute on function public.requeue_closeout_render_tasks(uuid, uuid, text, boolean)
  to authenticated, service_role;
revoke all on function public.requeue_closeout_artifacts(uuid, uuid, text, public.report_type, uuid)
  from public, anon;
grant execute on function public.requeue_closeout_artifacts(uuid, uuid, text, public.report_type, uuid)
  to authenticated, service_role;
revoke all on function public.get_closeout_dashboard_scoped(uuid, text, uuid[], integer, integer, public.report_type)
  from public, anon;
grant execute on function public.get_closeout_dashboard_scoped(uuid, text, uuid[], integer, integer, public.report_type)
  to authenticated, service_role;
