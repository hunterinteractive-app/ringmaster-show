-- National rehearsal: preserve exact retry identities and bounded automatic recovery.
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
  v_effective_artifact_id uuid := p_artifact_id;
  v_target_section_id text;
  v_target_report public.report_type;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and (auth.uid() is null or not public.user_can_finalize_show(p_show_id, auth.uid())) then
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

  if p_artifact_id is not null then
    select a.metadata ->> 'section_id', a.report_name
    into v_target_section_id, v_target_report
    from public.show_report_artifacts a
    where a.id = p_artifact_id
      and a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true;
    if not found or (p_report_name is not null and p_report_name <> v_target_report) then
      raise exception 'The requested artifact does not match the show, run and report type';
    end if;
  end if;

  -- ARBA artifacts generated before canonical artifact scoping have no
  -- artifact_key and omit the canonical scope fields in metadata. Merely
  -- changing those rows to queued is insufficient: enqueue_report_render_tasks
  -- intentionally ignores them, leaving the UI stuck at "queued" forever.
  -- Feed only the requested legacy rows through the established repair path.
  update public.show_report_artifacts a
  set artifact_status = 'failed'::public.artifact_status,
      metadata = a.metadata || jsonb_build_object(
        'error_category', 'invalid_scope',
        'error_message', 'Legacy ARBA artifact requires canonical scope repair'
      )
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and a.report_name = 'arba_report'::public.report_type
    and (p_report_name is null or a.report_name = p_report_name)
    and (p_artifact_id is null or a.id = p_artifact_id)
    and (
      a.artifact_key is null
      or a.scope_key <> public.closeout_artifact_scope_key(
        a.show_id, a.report_name, a.section_ids, a.metadata
      )
      or a.metadata ->> 'scope_key' is distinct from a.scope_key
      or a.metadata -> 'section_ids' is distinct from to_jsonb(a.section_ids)
    );

  perform public.repair_closeout_artifact_scopes(
    p_show_id,
    p_finalize_run_id
  );

  -- Repair may reuse a pre-existing identity owner and supersede the legacy
  -- row. Continue with that canonical row while preserving single-section
  -- regeneration semantics.
  if p_artifact_id is not null and v_target_report = 'arba_report'::public.report_type
     and v_target_section_id is not null then
    select a.id
    into v_effective_artifact_id
    from public.show_report_artifacts a
    where a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true
      and a.report_name = 'arba_report'::public.report_type
      and a.metadata ->> 'section_id' = v_target_section_id
      and a.scope_key = public.closeout_artifact_scope_key(
        a.show_id, a.report_name, a.section_ids, a.metadata
      )
    order by a.created_at, a.id
    limit 1;
    if v_effective_artifact_id is null then
      raise exception 'No canonical ARBA artifact matched the requested section';
    end if;
  end if;

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
    and (p_report_name is null or a.report_name = p_report_name)
    and (v_effective_artifact_id is null or a.id = v_effective_artifact_id)
    and a.scope_key = public.closeout_artifact_scope_key(
      a.show_id, a.report_name, a.section_ids, a.metadata
    );

  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'No canonical artifact matched the requested finalize run and scope';
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
    and a.is_current = true
    and a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and (p_report_name is null or a.report_name = p_report_name)
    and (v_effective_artifact_id is null or a.id = v_effective_artifact_id)
    and q.task_type = 'render_report'::public.show_task_type;

  perform public.enqueue_report_render_tasks(
    p_show_id,
    p_finalize_run_id,
    true
  );

  return jsonb_build_object(
    'queued_count', v_count,
    'scope_key', p_scope_key,
    'finalize_run_id', p_finalize_run_id,
    'artifact_id', v_effective_artifact_id
  );
end;
$function$;

revoke all on function public.requeue_closeout_artifacts(
  uuid,
  uuid,
  text,
  public.report_type,
  uuid
) from public, anon;

grant execute on function public.requeue_closeout_artifacts(
  uuid,
  uuid,
  text,
  public.report_type,
  uuid
) to authenticated, service_role;

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
      and a.artifact_status in (
        'queued'::public.artifact_status,
        'failed'::public.artifact_status
      )
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
  , recovered as (
    update public.show_task_queue q
    set task_status = case when q.attempt_count < q.max_attempts
          then 'queued'::public.show_task_status else 'failed'::public.show_task_status end,
        failed_at = case when q.attempt_count >= q.max_attempts then now() else null end,
        available_at = now(), worker_id = null, claimed_by = null,
        claimed_at = null, started_at = null, heartbeat_at = null, lease_expires_at = null,
        error_category = 'worker_lease_expired',
        last_error = 'The renderer lease expired before completion.',
        error_message = case when q.attempt_count < q.max_attempts
          then 'Report generation was interrupted and has been queued automatically.'
          else 'Report generation was interrupted repeatedly; review and retry this report.' end
    from stale s
    where q.id = s.id
    returning q.report_artifact_id, q.task_status, q.error_message
  )
  update public.show_report_artifacts a
  set artifact_status = case when r.task_status = 'queued'
        then 'queued'::public.artifact_status else 'failed'::public.artifact_status end,
      metadata = (a.metadata - 'error_category' - 'error_message') ||
        case when r.task_status = 'failed' then jsonb_build_object(
          'error_category', 'worker_lease_expired', 'error_message', r.error_message)
        else '{}'::jsonb end
  from recovered r where a.id = r.report_artifact_id;
  get diagnostics v_recovered = row_count;

  return v_obsolete + v_recovered;
end;
$function$;

revoke all on function public.recover_stale_report_render_tasks(integer)
  from public, anon, authenticated;
grant execute on function public.recover_stale_report_render_tasks(integer)
  to service_role;

-- Section report caches retain their own revision. Show structure/number changes
-- and shared exhibitor/catalog edits still invalidate every affected report.
create table report_generation_private.scoped_result_revisions (
  scope_id uuid primary key,
  revision bigint not null default 1
);
alter table report_generation_private.scoped_result_revisions enable row level security;
revoke all on table report_generation_private.scoped_result_revisions from public, anon, authenticated;

create or replace function report_generation_private.invalidate_result_rows()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_query text; v_column text;
begin
  if TG_ARGV[0] = 'global' then
    insert into report_generation_private.result_revisions(scope_id)
      values ('00000000-0000-0000-0000-000000000000')
    on conflict (scope_id) do update set revision = result_revisions.revision + 1;
  else
    v_query := case TG_OP
      when 'INSERT' then 'select distinct show_id from new_rows'
      when 'DELETE' then 'select distinct show_id from old_rows'
      else 'select show_id from new_rows union select show_id from old_rows' end;
    execute 'insert into report_generation_private.result_revisions(scope_id)
      select show_id from (' || v_query || ') affected where show_id is not null
      order by show_id on conflict (scope_id) do update
      set revision = result_revisions.revision + 1';

    v_column := case when TG_TABLE_NAME = 'entries' then 'coalesce(section_id, show_id)' else 'show_id' end;
    v_query := case TG_OP
      when 'INSERT' then 'select distinct ' || v_column || ' as scope_id from new_rows'
      when 'DELETE' then 'select distinct ' || v_column || ' as scope_id from old_rows'
      else 'select ' || v_column || ' as scope_id from new_rows union select ' || v_column || ' as scope_id from old_rows' end;
    execute 'insert into report_generation_private.scoped_result_revisions(scope_id)
      select scope_id from (' || v_query || ') affected where scope_id is not null
      order by scope_id on conflict (scope_id) do update
      set revision = scoped_result_revisions.revision + 1';
  end if;
  return null;
end;
$$;
revoke all on function report_generation_private.invalidate_result_rows() from public, anon, authenticated;

create function public.get_report_result_revision_scoped(p_show_id uuid, p_section_ids uuid[] default null)
returns text language sql stable security definer set search_path = '' as $$
  select case when coalesce(cardinality(p_section_ids), 0) = 0
    then public.get_report_result_revision(p_show_id)
    else coalesce((select revision::text from report_generation_private.result_revisions
      where scope_id = '00000000-0000-0000-0000-000000000000'), '0') || ':' || (
      select string_agg(ids.id::text || '=' || coalesce(r.revision, 0)::text, ',' order by ids.id)
      from (select distinct unnest(array_append(p_section_ids, p_show_id)) as id) ids
      left join report_generation_private.scoped_result_revisions r on r.scope_id = ids.id
    ) end;
$$;
revoke all on function public.get_report_result_revision_scoped(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.get_report_result_revision_scoped(uuid, uuid[]) to service_role;

-- Match the expressions in the report projection and bound every staff page
-- before joining catalogs, awards and coop labels.
create index if not exists entries_show_id_page_idx on public.entries(show_id, id);
create index if not exists entries_show_section_id_page_idx on public.entries(show_id, section_id, id);
create index if not exists breeds_results_name_species_idx
  on public.breeds(lower(btrim(name)), lower(species::text), name, id) where is_active = true;
create index if not exists varieties_results_name_idx
  on public.varieties(breed_id, lower(btrim(name)), sort_order, name, id);

create function public.get_judging_entry_rows_page(
  p_show_id uuid, p_section_id uuid default null, p_show_letter text default null,
  p_breed text default null, p_entry_ids uuid[] default null,
  p_after_entry_id uuid default null, p_page_size integer default 250
)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
    and not public.user_can_enter_results(p_show_id)
    and not public.user_can_manage_entries(p_show_id)
    and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have access to this show' using errcode = '42501';
  end if;
  return query
  with results as materialized (
    select r.* from public.report_results_entry_rows_page(p_show_id, p_section_id,
      p_show_letter, p_breed, p_entry_ids, p_after_entry_id, p_page_size) r
  )
  select to_jsonb(r) || jsonb_build_object(
    'animal_id', e.animal_id, 'species', e.species, 'animal_name', e.animal_name,
    'coop_number', coalesce(coop.coop_number, ''), '_awards', coalesce(aw.codes, '[]'::jsonb)
  )
  from results r
  join public.entries e on e.id = r.entry_id and e.show_id = p_show_id
  join public.shows sh on sh.id = e.show_id
  left join public.show_sections ss on ss.id = e.section_id
  left join public.show_animal_coop_numbers coop on coop.show_id = e.show_id and coop.animal_id = e.animal_id
    and coop.scope = case when sh.coop_numbering_mode = 'combined' then 'all' else lower(ss.kind::text) end
  left join lateral (
    select jsonb_agg(a.award_code order by a.award_code, a.id) codes
    from public.entry_awards a where a.show_id = p_show_id and a.entry_id = e.id
  ) aw on true
  order by r.entry_id;
end;
$$;
revoke all on function public.get_judging_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer) from public, anon;
grant execute on function public.get_judging_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer) to authenticated, service_role;
