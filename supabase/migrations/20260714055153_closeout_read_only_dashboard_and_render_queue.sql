-- Closeout is split into a read model and explicit commands. This migration
-- intentionally does not rewrite or delete historical artifacts, runs, tasks,
-- deliveries, or sweepstakes rows.

do $migration$
begin
  if exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'show_task_status'
      and e.enumlabel = 'claimed'
  ) and not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'show_task_status'
      and e.enumlabel = 'running'
  ) then
    alter type public.show_task_status rename value 'claimed' to 'running';
  end if;
end;
$migration$;

alter table public.show_report_artifacts
  add column if not exists artifact_key text,
  add column if not exists generation integer not null default 1;

alter table public.show_task_queue
  add column if not exists scope_key text,
  add column if not exists available_at timestamptz not null default now(),
  add column if not exists started_at timestamptz,
  add column if not exists worker_id text,
  add column if not exists last_error text,
  add column if not exists error_category text,
  add column if not exists heartbeat_at timestamptz,
  add column if not exists lease_expires_at timestamptz;

-- These legacy constraints treated a report as show-global and therefore
-- prevented two exact scopes containing the same section/target from coexisting.
drop index if exists public.uq_sra_current_club_scoped;
drop index if exists public.uq_sra_current_exhibitor_scoped;
drop index if exists public.uq_sra_current_global;
drop index if exists public.uq_sra_current_section;

-- Historical rows keep a null artifact_key. New manifests receive a structured
-- identity from the trigger below, so old ambiguous metadata is never assigned
-- to a new scope merely to satisfy a constraint.
create unique index if not exists show_report_artifacts_run_identity_uidx
  on public.show_report_artifacts (finalize_run_id, artifact_key)
  where finalize_run_id is not null and artifact_key is not null;

create unique index if not exists show_task_queue_artifact_type_uidx
  on public.show_task_queue (report_artifact_id, task_type)
  where report_artifact_id is not null;

create index if not exists show_report_artifacts_dashboard_idx
  on public.show_report_artifacts
  (show_id, scope_key, finalize_run_id, report_name, artifact_status)
  where is_current = true;

create index if not exists show_task_queue_claim_idx
  on public.show_task_queue (task_status, available_at, priority, created_at)
  where task_status in ('queued'::public.show_task_status, 'failed'::public.show_task_status);

create index if not exists show_task_queue_scope_summary_idx
  on public.show_task_queue
  (show_id, finalize_run_id, scope_key, task_status, task_type);

create index if not exists show_task_queue_expired_lease_idx
  on public.show_task_queue (lease_expires_at)
  where task_status = 'running'::public.show_task_status;

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
    coalesce(p_metadata ->> 'section_id', ''),
    coalesce(p_metadata ->> 'exhibitor_id', ''),
    lower(coalesce(p_metadata ->> 'breed_name', '')),
    lower(coalesce(p_metadata ->> 'club_name', '')),
    lower(coalesce(p_metadata ->> 'species', '')),
    upper(coalesce(p_metadata ->> 'scope', '')),
    upper(coalesce(p_metadata ->> 'show_letter', '')),
    upper(coalesce(p_metadata ->> 'sanctioning_body', '')),
    lower(coalesce(p_metadata ->> 'delivery_type', ''))
  );
$function$;

create or replace function public.set_closeout_artifact_scope_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.scope_key := coalesce(new.scope_key, nullif(new.metadata ->> 'scope_key', ''));
  if new.section_ids is null and jsonb_typeof(new.metadata -> 'section_ids') = 'array' then
    new.section_ids := array(
      select value::uuid
      from jsonb_array_elements_text(new.metadata -> 'section_ids') value
      order by value
    );
  end if;
  if tg_op = 'INSERT' and new.finalize_run_id is not null and new.artifact_key is null then
    new.artifact_key := public.closeout_artifact_identity(new.report_name, new.metadata);
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
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and a.artifact_status in (
      'queued'::public.artifact_status,
      'failed'::public.artifact_status
    )
  on conflict (report_artifact_id, task_type)
    where report_artifact_id is not null
  do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

drop function if exists public.finalize_show_scoped(uuid, uuid[], text, text);

create function public.finalize_show_scoped(
  p_show_id uuid,
  p_section_ids uuid[],
  p_scope_label text default 'Selected Scope',
  p_scope_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_finalize_run_id uuid;
  v_results_version bigint;
  v_section_ids uuid[];
  v_scope_key text;
  v_scope_metadata jsonb;
  v_species text[];
  v_show_letters text[];
  v_readiness jsonb;
  v_task_count integer := 0;
  v_reused boolean := false;
  v_section record;
begin
  -- EXECUTE is granted only to service_role below. run-closeout authenticates
  -- and authorizes the initiating user before invoking this trusted RPC.

  select array_agg(sec.id order by sec.id)
  into v_section_ids
  from public.show_sections sec
  where sec.show_id = p_show_id and sec.is_enabled = true
    and sec.id = any(coalesce(p_section_ids, array[]::uuid[]));

  if coalesce(array_length(v_section_ids, 1), 0) = 0 then
    raise exception 'No enabled sections were selected for closeout.';
  end if;
  if array_length(v_section_ids, 1) <> array_length(p_section_ids, 1) then
    raise exception 'The closeout selection contains an invalid, duplicate, or disabled section.';
  end if;

  v_scope_key := p_show_id::text || ':' || array_to_string(v_section_ids, ',');
  if nullif(btrim(p_scope_key), '') is not null and btrim(p_scope_key) <> v_scope_key then
    raise exception 'scope_key does not match the canonical selected section IDs';
  end if;

  select s.results_version into v_results_version
  from public.shows s where s.id = p_show_id;
  if v_results_version is null then
    raise exception 'Show % was not found or has no results version', p_show_id;
  end if;

  -- Finalize is the explicit point at which the expensive live validation is
  -- allowed. The read-only dashboard never invokes this loader-style RPC.
  select public.show_results_readiness(p_show_id) into v_readiness;
  if not coalesce((v_readiness ->> 'ready')::boolean, false) then
    raise exception 'Results are not ready for finalization: %', v_readiness::text;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_show_id::text || ':' || v_scope_key, 0));

  -- Only version-2 manifests are reusable. Older historical runs remain
  -- untouched and accessible, but are never guessed into the new identity.
  select f.id into v_finalize_run_id
  from public.show_finalize_runs f
  where f.show_id = p_show_id
    and f.scope_key = v_scope_key
    and f.section_ids = v_section_ids
    and f.results_version = v_results_version
    and f.run_status in ('completed','completed_with_warnings')
    and f.summary ->> 'manifest_version' = '2'
  order by f.started_at desc
  limit 1;

  if v_finalize_run_id is not null then
    v_reused := true;
    select public.enqueue_report_render_tasks(p_show_id, v_finalize_run_id)
    into v_task_count;
  else
    select
      array_agg(distinct x.species order by x.species)
        filter (where x.species in ('rabbit','cavy')),
      array_agg(distinct upper(sec.letter) order by upper(sec.letter))
    into v_species, v_show_letters
    from public.show_sections sec
    left join lateral (
      select lower(e.species::text) species
      from public.entries e
      where e.show_id = p_show_id and e.section_id = sec.id
      union
      select lower(b.species::text)
      from public.breeds b
      where b.id = any(coalesce(sec.allowed_breed_ids, array[]::uuid[]))
    ) x on true
    where sec.id = any(v_section_ids);

    v_scope_metadata := jsonb_build_object(
      'scope_key', v_scope_key,
      'scope_label', coalesce(nullif(btrim(p_scope_label), ''), 'Selected Scope'),
      'section_ids', to_jsonb(v_section_ids),
      'species', to_jsonb(coalesce(v_species, array[]::text[])),
      'show_letters', to_jsonb(coalesce(v_show_letters, array[]::text[]))
    );

    for v_section in
      select sec.kind, sec.letter from public.show_sections sec
      where sec.id = any(v_section_ids)
    loop
      perform public.calculate_sweepstakes_for_show(
        p_show_id, upper(v_section.kind::text), upper(v_section.letter)
      );
    end loop;

    insert into public.show_finalize_runs (
      show_id, run_status, started_at, results_version,
      scope_key, scope_label, section_ids, summary
    ) values (
      p_show_id, 'running', now(), v_results_version, v_scope_key,
      coalesce(nullif(btrim(p_scope_label), ''), 'Selected Scope'),
      v_section_ids,
      jsonb_build_object('manifest_version', 2, 'scope_key', v_scope_key)
    ) returning id into v_finalize_run_id;

    update public.show_report_artifacts a
    set is_current = false, superseded_at = now()
    where a.show_id = p_show_id and a.scope_key = v_scope_key and a.is_current = true;

    -- One ARBA artifact for each selected section that actually has qualifying
    -- shown entries. A missing sanction number fails only this artifact later.
    insert into public.show_report_artifacts (
      show_id, finalize_run_id, report_name, artifact_status, metadata,
      is_current, scope_key, section_ids
    )
    select p_show_id, v_finalize_run_id, 'arba_report', 'queued',
      v_scope_metadata || jsonb_build_object(
        'section_id', sec.id, 'show_letter', upper(sec.letter),
        'scope', upper(sec.kind::text),
        'section_label', coalesce(nullif(btrim(sec.display_name), ''),
          initcap(sec.kind::text) || ' ' || upper(sec.letter)),
        'delivery_type', 'arba'
      ), true, v_scope_key, v_section_ids
    from public.show_sections sec
    where sec.id = any(v_section_ids)
      and exists (
        select 1 from public.entries e
        where e.show_id = p_show_id and e.section_id = sec.id
          and e.is_shown = true and e.scratched_at is null
          and lower(coalesce(e.status, '')) <> 'scratched'
      );

    -- Exhibitor-facing artifacts are created only for exhibitors with shown
    -- entries in the exact section set. Legs are further limited to winners.
    insert into public.show_report_artifacts (
      show_id, finalize_run_id, report_name, artifact_status, metadata,
      is_current, scope_key, section_ids
    )
    select p_show_id, v_finalize_run_id, report.report_name, 'queued',
      v_scope_metadata || jsonb_build_object(
        'exhibitor_id', ex.id,
        'exhibitor_name', coalesce(nullif(btrim(ex.display_name), ''),
          btrim(coalesce(ex.first_name, '') || ' ' || coalesce(ex.last_name, ''))),
        'delivery_type', 'exhibitor'
      ), true, v_scope_key, v_section_ids
    from public.exhibitors ex
    cross join lateral (
      select unnest(array['exhibitor_report','checkin_sheet']::public.report_type[]) report_name
    ) report
    where exists (
      select 1 from public.entries e
      where e.show_id = p_show_id and e.section_id = any(v_section_ids)
        and e.exhibitor_id = ex.id and e.is_shown = true
        and e.scratched_at is null and lower(coalesce(e.status, '')) <> 'scratched'
    );

    insert into public.show_report_artifacts (
      show_id, finalize_run_id, report_name, artifact_status, metadata,
      is_current, scope_key, section_ids
    )
    select p_show_id, v_finalize_run_id, 'legs', 'queued',
      v_scope_metadata || jsonb_build_object(
        'exhibitor_id', ex.id,
        'exhibitor_name', coalesce(nullif(btrim(ex.display_name), ''),
          btrim(coalesce(ex.first_name, '') || ' ' || coalesce(ex.last_name, ''))),
        'delivery_type', 'exhibitor'
      ), true, v_scope_key, v_section_ids
    from public.exhibitors ex
    where exists (
      select 1 from public.entries e
      join public.entry_awards ea on ea.entry_id = e.id
      where e.show_id = p_show_id and e.section_id = any(v_section_ids)
        and e.exhibitor_id = ex.id and e.is_shown = true
        and e.scratched_at is null
        and ea.award_code in ('BOB','BOSB','BOV','BOSV','BIS','RIS','BJB','BIB','BSB','BJV','BIV','BSV')
    );

    -- Club identities come from structured sanction and section columns, never
    -- filenames. Each target must have qualifying shown data in that section.
    insert into public.show_report_artifacts (
      show_id, finalize_run_id, report_name, artifact_status, metadata,
      is_current, scope_key, section_ids
    )
    select p_show_id, v_finalize_run_id, report.report_name, 'queued',
      v_scope_metadata || jsonb_build_object(
        'section_id', sec.id, 'scope', upper(sec.kind::text),
        'show_letter', upper(sec.letter), 'breed_name', coalesce(ss.breed_name, ''),
        'club_name', coalesce(ss.club_name, ''), 'species', lower(coalesce(e_species.species, '')),
        'sweepstakes_email', coalesce(ss.sweepstakes_email, ''),
        'sanction_number', coalesce(ss.sanction_number, ''),
        'sanctioning_body', upper(btrim(ss.sanctioning_body)),
        'delivery_type', 'club'
      ), true, v_scope_key, v_section_ids
    from public.show_sanctions ss
    join public.show_sections sec on sec.id = ss.section_id
    cross join lateral (
      select unnest(case
        when upper(btrim(ss.sanctioning_body)) = 'STATE CLUB' then
          array['details_by_breed','exh_by_breed','best_display_report']::public.report_type[]
        else array['sweepstakes_report','breed_results_detail_report']::public.report_type[]
      end) report_name
    ) report
    join lateral (
      select distinct lower(e.species::text) species
      from public.entries e
      where e.show_id = p_show_id and e.section_id = sec.id
        and e.is_shown = true and e.scratched_at is null
        and (
          upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
          or lower(btrim(coalesce(e.breed, ''))) = lower(btrim(coalesce(ss.breed_name, '')))
        )
    ) e_species on true
    where ss.show_id = p_show_id and sec.id = any(v_section_ids)
      and upper(btrim(ss.sanctioning_body)) in ('NATIONAL CLUB','STATE BREED CLUB','STATE CLUB')
      and exists (
        select 1 from public.entries e
        where e.show_id = p_show_id and e.section_id = sec.id
          and e.is_shown = true and e.scratched_at is null
          and (
            upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
            or lower(btrim(coalesce(e.breed, ''))) = lower(btrim(coalesce(ss.breed_name, '')))
          )
      );

    -- Show-level builders are represented once per immutable scoped run. They
    -- are skipped when the scope contains no entries at all.
    insert into public.show_report_artifacts (
      show_id, finalize_run_id, report_name, artifact_status, metadata,
      is_current, scope_key, section_ids
    )
    select p_show_id, v_finalize_run_id, report.report_name, 'queued',
      v_scope_metadata || jsonb_build_object('delivery_type', 'internal'),
      true, v_scope_key, v_section_ids
    from unnest(array[
      'unpaid_balances_report','paid_exhibitor_report',
      'entered_exhibitors_contact_report','ribbon_payout_report',
      'payback_report','judge_report','breed_judged_totals_report'
    ]::public.report_type[]) report(report_name)
    where exists (
      select 1 from public.entries e
      where e.show_id = p_show_id and e.section_id = any(v_section_ids)
    );

    select public.enqueue_report_render_tasks(p_show_id, v_finalize_run_id)
    into v_task_count;

    update public.show_finalize_runs f
    set run_status = 'completed', completed_at = now(),
        summary = f.summary || jsonb_build_object(
          'artifact_count', (select count(*) from public.show_report_artifacts a where a.finalize_run_id = f.id),
          'render_task_count', (select count(*) from public.show_task_queue q where q.finalize_run_id = f.id and q.task_type = 'render_report')
        )
    where f.id = v_finalize_run_id;

    perform public.refresh_show_reports_state(p_show_id);
  end if;

  return jsonb_build_object(
    'finalize_run_id', v_finalize_run_id,
    'scope_key', v_scope_key,
    'section_ids', to_jsonb(v_section_ids),
    'reused', v_reused,
    'new_tasks', v_task_count,
    'counts', (
      select jsonb_build_object(
        'artifacts', count(*)::integer,
        'generated', count(*) filter (where a.artifact_status = 'generated')::integer,
        'queued', count(*) filter (where a.artifact_status = 'queued')::integer,
        'failed', count(*) filter (where a.artifact_status = 'failed')::integer
      ) from public.show_report_artifacts a where a.finalize_run_id = v_finalize_run_id
    )
  );
exception when others then
  if v_finalize_run_id is not null and not v_reused then
    update public.show_finalize_runs
    set run_status = 'failed', completed_at = now(),
        error_summary = jsonb_build_object('sql_error', sqlerrm)
    where id = v_finalize_run_id;
  end if;
  raise;
end;
$function$;

revoke all on function public.finalize_show_scoped(uuid, uuid[], text, text) from public, anon, authenticated;
grant execute on function public.finalize_show_scoped(uuid, uuid[], text, text) to service_role;

-- One fixed-size summary query and one bounded artifact page. No report loader,
-- target reconciliation, Storage lookup, or write is reachable from this RPC.
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
    where f.show_id = p_show_id
      and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  artifact_counts as (
    select
      count(*)::integer total,
      count(*) filter (where a.artifact_status = 'generated')::integer generated,
      count(*) filter (where a.artifact_status = 'queued')::integer queued,
      count(*) filter (where a.artifact_status = 'failed')::integer failed,
      coalesce(jsonb_object_agg(a.report_name, a.report_count), '{}'::jsonb) by_report
    from (
      select a.report_name, a.artifact_status, count(*) over (partition by a.report_name)::integer report_count
      from public.show_report_artifacts a
      join selected_run r on r.id = a.finalize_run_id
      where a.show_id = p_show_id and a.scope_key = p_scope_key and a.is_current = true
    ) a
  ),
  task_counts as (
    select
      count(*) filter (where q.task_status = 'queued')::integer queued,
      count(*) filter (where q.task_status = 'running')::integer running,
      count(*) filter (where q.task_status = 'failed')::integer failed,
      count(*) filter (where q.task_status = 'completed')::integer completed,
      (
        count(*) filter (
          where q.task_status = 'failed' and q.task_type = 'render_report'
            and q.attempt_count < q.max_attempts
        ) +
        (select count(*)
         from public.show_report_artifacts a
         join selected_run sr on sr.id = a.finalize_run_id
         where a.show_id = p_show_id and a.scope_key = p_scope_key
           and a.is_current = true and a.artifact_status in ('queued','failed')
           and not exists (
             select 1 from public.show_task_queue missing_q
             where missing_q.report_artifact_id = a.id
               and missing_q.task_type = 'render_report'
           ))
      )::integer remaining
    from public.show_task_queue q
    join selected_run r on r.id = q.finalize_run_id
    where q.show_id = p_show_id and q.scope_key = p_scope_key
  ),
  artifact_page as (
    select a.*
    from public.show_report_artifacts a
    join selected_run r on r.id = a.finalize_run_id
    cross join requested req
    where a.show_id = p_show_id
      and a.scope_key = p_scope_key
      and a.is_current = true
      and (p_report_name is null or a.report_name = p_report_name)
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
      'remaining', coalesce(tc.remaining, 0)
    ),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'finalize_run_id', a.finalize_run_id,
        'report_name', a.report_name, 'artifact_status', a.artifact_status,
        'file_name', a.file_name, 'storage_bucket', a.storage_bucket,
        'storage_path', a.storage_path, 'generated_at', a.generated_at,
        'is_current', a.is_current, 'metadata', a.metadata
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

create or replace function public.claim_report_render_tasks(
  p_worker_id text,
  p_batch_size integer default 5
)
returns setof public.show_task_queue
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if nullif(btrim(p_worker_id), '') is null then
    raise exception 'worker_id is required';
  end if;

  return query
  with claimable as (
    select q.id
    from public.show_task_queue q
    where q.task_type = 'render_report'::public.show_task_type
      and q.task_status in (
        'queued'::public.show_task_status,
        'failed'::public.show_task_status
      )
      and q.available_at <= now()
      and q.attempt_count < q.max_attempts
    order by q.priority, q.available_at, q.created_at
    for update skip locked
    limit greatest(1, least(coalesce(p_batch_size, 5), 25))
  )
  update public.show_task_queue q
  set task_status = 'running'::public.show_task_status,
      attempt_count = q.attempt_count + 1,
      started_at = now(), claimed_at = now(),
      worker_id = btrim(p_worker_id), claimed_by = btrim(p_worker_id),
      last_error = null, error_message = null, error_category = null,
      heartbeat_at = now(), lease_expires_at = now() + interval '10 minutes'
  from claimable c
  where q.id = c.id
  returning q.*;
end;
$function$;

create or replace function public.heartbeat_report_render_task(
  p_task_id uuid,
  p_worker_id text,
  p_lease_seconds integer default 600
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_expires_at timestamptz;
begin
  update public.show_task_queue q
  set heartbeat_at = now(),
      lease_expires_at = now() + make_interval(
        secs => greatest(60, least(coalesce(p_lease_seconds, 600), 3600))
      )
  where q.id = p_task_id
    and q.task_type = 'render_report'::public.show_task_type
    and q.task_status = 'running'::public.show_task_status
    and q.worker_id = btrim(p_worker_id)
  returning q.lease_expires_at into v_expires_at;
  if v_expires_at is null then
    raise exception 'Render task is not owned by this worker';
  end if;
  return v_expires_at;
end;
$function$;

create or replace function public.recover_stale_report_render_tasks(
  p_limit integer default 25
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer := 0;
begin
  with stale as (
    select q.id
    from public.show_task_queue q
    where q.task_type = 'render_report'::public.show_task_type
      and q.task_status = 'running'::public.show_task_status
      and q.lease_expires_at < now()
    order by q.lease_expires_at
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 25), 100))
  )
  update public.show_task_queue q
  set task_status = 'failed'::public.show_task_status,
      failed_at = now(), available_at = now(), worker_id = null,
      claimed_by = null, heartbeat_at = null, lease_expires_at = null,
      error_category = 'worker_lease_expired',
      last_error = 'The renderer lease expired before completion.',
      error_message = 'The renderer lease expired before completion.'
  from stale s
  where q.id = s.id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

create or replace function public.count_report_render_tasks_ready()
returns bigint
language sql
stable
security definer
set search_path = ''
as $function$
  select count(*)
  from public.show_task_queue q
  where q.task_type = 'render_report'::public.show_task_type
    and q.task_status in (
      'queued'::public.show_task_status,
      'failed'::public.show_task_status
    )
    and q.available_at <= now()
    and q.attempt_count < q.max_attempts;
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

  if p_regenerate_all then
    update public.show_report_artifacts a
    set artifact_status = 'queued'::public.artifact_status,
        storage_bucket = 'show-files',
        storage_path = format(
          'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
          a.show_id, a.finalize_run_id, a.id, a.generation + 1
        ), file_name = null,
        mime_type = null, file_size_bytes = null, file_hash_sha256 = null,
        generated_at = null, error_count = 0,
        generation = a.generation + 1,
        metadata = jsonb_set(
          a.metadata - 'error_message',
          '{previous_versions}',
          coalesce(a.metadata -> 'previous_versions', '[]'::jsonb) ||
            case when a.storage_path is null then '[]'::jsonb else jsonb_build_array(
              jsonb_build_object(
                'generation', a.generation, 'storage_bucket', a.storage_bucket,
                'storage_path', a.storage_path, 'file_name', a.file_name,
                'file_size_bytes', a.file_size_bytes,
                'file_hash_sha256', a.file_hash_sha256,
                'generated_at', a.generated_at
              )
            ) end,
          true
        )
    where a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
      and a.scope_key = p_scope_key and a.is_current = true;
  end if;

  update public.show_task_queue q
  set task_status = 'queued'::public.show_task_status,
      available_at = now(), started_at = null, completed_at = null,
      failed_at = null, worker_id = null, claimed_by = null, claimed_at = null,
      last_error = null, error_message = null, error_category = null,
      heartbeat_at = null, lease_expires_at = null, attempt_count = 0,
      payload = q.payload || jsonb_build_object(
        'generation', a.generation, 'artifact_id', a.id
      )
  from public.show_report_artifacts a
  where q.report_artifact_id = a.id
    and a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
    and a.scope_key = p_scope_key and a.is_current = true
    and q.task_type = 'render_report'::public.show_task_type
    and (
      p_regenerate_all
      or (a.artifact_status in ('queued','failed') and q.task_status = 'failed'
          and q.attempt_count < q.max_attempts)
    );
  get diagnostics v_requeued = row_count;

  select public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id)
  into v_inserted;

  return jsonb_build_object(
    'finalize_run_id', p_finalize_run_id, 'scope_key', p_scope_key,
    'requeued_count', v_requeued, 'inserted_count', v_inserted,
    'queued_count', v_requeued + v_inserted
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

  update public.show_report_artifacts a
  set artifact_status = 'queued'::public.artifact_status,
      storage_bucket = 'show-files',
      storage_path = format(
        'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
        a.show_id, a.finalize_run_id, a.id, a.generation + 1
      ), file_name = null,
      mime_type = null, file_size_bytes = null, file_hash_sha256 = null,
      generated_at = null, error_count = 0, generation = a.generation + 1,
      metadata = jsonb_set(
        a.metadata - 'error_message',
        '{previous_versions}',
        coalesce(a.metadata -> 'previous_versions', '[]'::jsonb) ||
          case when a.storage_path is null then '[]'::jsonb else jsonb_build_array(
            jsonb_build_object(
              'generation', a.generation, 'storage_bucket', a.storage_bucket,
              'storage_path', a.storage_path, 'file_name', a.file_name,
              'file_size_bytes', a.file_size_bytes,
              'file_hash_sha256', a.file_hash_sha256,
              'generated_at', a.generated_at
            )
          ) end,
        true
      )
  where a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
    and a.scope_key = p_scope_key and a.is_current = true
    and (p_report_name is null or a.report_name = p_report_name)
    and (p_artifact_id is null or a.id = p_artifact_id);
  get diagnostics v_count = row_count;

  if v_count = 0 then
    raise exception 'No artifact matched the requested finalize run and scope';
  end if;

  update public.show_task_queue q
  set task_status = 'queued'::public.show_task_status,
      available_at = now(), started_at = null, completed_at = null,
      failed_at = null, worker_id = null, claimed_by = null, claimed_at = null,
      last_error = null, error_message = null, error_category = null,
      heartbeat_at = null, lease_expires_at = null, attempt_count = 0,
      payload = q.payload || jsonb_build_object('generation', a.generation)
  from public.show_report_artifacts a
  where q.report_artifact_id = a.id
    and a.show_id = p_show_id and a.finalize_run_id = p_finalize_run_id
    and a.scope_key = p_scope_key and a.is_current = true
    and (p_report_name is null or a.report_name = p_report_name)
    and (p_artifact_id is null or a.id = p_artifact_id)
    and q.task_type = 'render_report'::public.show_task_type;

  perform public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id);
  return jsonb_build_object('queued_count', v_count, 'scope_key', p_scope_key,
    'finalize_run_id', p_finalize_run_id);
end;
$function$;

create or replace function public.complete_report_render_task(
  p_task_id uuid,
  p_worker_id text,
  p_storage_bucket text,
  p_storage_path text,
  p_file_name text,
  p_mime_type text,
  p_file_size_bytes bigint,
  p_file_hash_sha256 text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_artifact_id uuid;
  v_expected_bucket text;
  v_expected_path text;
  v_updated integer := 0;
begin
  -- A worker may successfully commit completion and lose the HTTP response.
  -- Treat an exact replay by the same worker as success, while rejecting any
  -- attempt to rewrite the authoritative object metadata.
  if exists (
    select 1
    from public.show_task_queue q
    join public.show_report_artifacts a on a.id = q.report_artifact_id
    where q.id = p_task_id
      and q.task_type = 'render_report'::public.show_task_type
      and q.task_status = 'completed'::public.show_task_status
      and q.worker_id = btrim(p_worker_id)
      and a.artifact_status = 'generated'::public.artifact_status
      and a.storage_bucket = p_storage_bucket
      and a.storage_path = p_storage_path
      and a.file_name = p_file_name
      and a.mime_type = p_mime_type
      and a.file_size_bytes = p_file_size_bytes
      and coalesce(a.file_hash_sha256, '') = coalesce(nullif(btrim(p_file_hash_sha256), ''), '')
  ) then
    return;
  end if;

  select a.id, a.storage_bucket, a.storage_path
  into v_artifact_id, v_expected_bucket, v_expected_path
  from public.show_task_queue q
  join public.show_report_artifacts a on a.id = q.report_artifact_id
  where q.id = p_task_id and q.task_type = 'render_report'
    and q.task_status = 'running' and q.worker_id = btrim(p_worker_id)
  for update of q, a;
  if v_artifact_id is null then
    raise exception 'Render task is not owned by this worker';
  end if;
  if p_storage_bucket <> v_expected_bucket or p_storage_path <> v_expected_path then
    raise exception 'Uploaded object does not match the artifact-authoritative Storage location';
  end if;

  update public.show_task_queue q
  set task_status = 'completed'::public.show_task_status,
      completed_at = now(), last_error = null, error_message = null,
      error_category = null, heartbeat_at = now(), lease_expires_at = null
  where q.id = p_task_id and q.task_type = 'render_report'
    and q.task_status = 'running' and q.worker_id = btrim(p_worker_id)
  returning q.report_artifact_id into v_artifact_id;
  if v_artifact_id is null then
    raise exception 'Render task is not owned by this worker';
  end if;

  update public.show_report_artifacts a
  set artifact_status = 'generated'::public.artifact_status,
      storage_bucket = p_storage_bucket, storage_path = p_storage_path,
      file_name = p_file_name, mime_type = p_mime_type,
      file_size_bytes = p_file_size_bytes,
      file_hash_sha256 = nullif(btrim(p_file_hash_sha256), ''),
      generated_at = now(), error_count = 0,
      metadata = a.metadata - 'error_message'
  where a.id = v_artifact_id and a.is_current = true;
  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception 'Current render artifact was not updated';
  end if;
end;
$function$;

create or replace function public.fail_report_render_task(
  p_task_id uuid,
  p_worker_id text,
  p_error_category text,
  p_user_message text,
  p_diagnostic text,
  p_retryable boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_task public.show_task_queue;
  v_backoff interval;
begin
  select q.* into v_task from public.show_task_queue q
  where q.id = p_task_id and q.task_type = 'render_report'
    and q.task_status = 'running' and q.worker_id = btrim(p_worker_id)
  for update;
  if v_task.id is null then
    raise exception 'Render task is not owned by this worker';
  end if;

  v_backoff := make_interval(secs => least(3600, 30 * power(2, greatest(v_task.attempt_count - 1, 0))::integer));
  update public.show_task_queue q
  set task_status = 'failed'::public.show_task_status,
      failed_at = now(), error_category = left(p_error_category, 120),
      last_error = left(p_diagnostic, 8000),
      error_message = left(p_user_message, 1000),
      heartbeat_at = null, lease_expires_at = null,
      attempt_count = case when p_retryable then q.attempt_count else q.max_attempts end,
      available_at = now() + v_backoff
  where q.id = p_task_id;

  update public.show_report_artifacts a
  set artifact_status = 'failed'::public.artifact_status,
      error_count = a.error_count + 1,
      metadata = a.metadata || jsonb_build_object(
        'error_category', left(p_error_category, 120),
        'error_message', left(p_user_message, 1000)
      )
  where a.id = v_task.report_artifact_id;

  return jsonb_build_object(
    'task_id', p_task_id,
    'retry_eligible', p_retryable and v_task.attempt_count < v_task.max_attempts,
    'available_at', now() + v_backoff,
    'attempt_count', v_task.attempt_count,
    'max_attempts', v_task.max_attempts
  );
end;
$function$;

revoke all on function public.claim_report_render_tasks(text, integer) from public, anon, authenticated;
grant execute on function public.claim_report_render_tasks(text, integer) to service_role;

revoke all on function public.heartbeat_report_render_task(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.heartbeat_report_render_task(uuid, text, integer) to service_role;

revoke all on function public.recover_stale_report_render_tasks(integer) from public, anon, authenticated;
grant execute on function public.recover_stale_report_render_tasks(integer) to service_role;

revoke all on function public.count_report_render_tasks_ready() from public, anon, authenticated;
grant execute on function public.count_report_render_tasks_ready() to service_role;

revoke all on function public.complete_report_render_task(uuid, text, text, text, text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.complete_report_render_task(uuid, text, text, text, text, text, bigint, text) to service_role;

revoke all on function public.fail_report_render_task(uuid, text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fail_report_render_task(uuid, text, text, text, text, boolean) to service_role;

revoke all on function public.requeue_closeout_render_tasks(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.requeue_closeout_render_tasks(uuid, uuid, text, boolean) to authenticated, service_role;

revoke all on function public.requeue_closeout_artifacts(uuid, uuid, text, public.report_type, uuid) from public, anon;
grant execute on function public.requeue_closeout_artifacts(uuid, uuid, text, public.report_type, uuid) to authenticated, service_role;

revoke all on function public.get_closeout_dashboard_scoped(uuid, text, uuid[], integer, integer, public.report_type) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped(uuid, text, uuid[], integer, integer, public.report_type) to authenticated, service_role;
