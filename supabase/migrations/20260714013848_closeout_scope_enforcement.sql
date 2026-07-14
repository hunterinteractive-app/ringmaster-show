alter table public.show_report_artifacts
  add column if not exists scope_key text,
  add column if not exists section_ids uuid[];

alter table public.show_finalize_runs
  add column if not exists scope_key text,
  add column if not exists scope_label text,
  add column if not exists section_ids uuid[];

create index if not exists show_report_artifacts_scope_status_idx
  on public.show_report_artifacts
  (show_id, finalize_run_id, scope_key, artifact_status)
  where is_current = true;

create index if not exists show_report_artifacts_sections_gin_idx
  on public.show_report_artifacts using gin (section_ids);

create index if not exists show_finalize_runs_scope_idx
  on public.show_finalize_runs (show_id, scope_key, started_at desc);

-- Backfill only rows whose structured metadata identifies their section set.
update public.show_report_artifacts a
set section_ids = case
  when jsonb_typeof(a.metadata -> 'section_ids') = 'array' then
    array(
      select value::uuid
      from jsonb_array_elements_text(a.metadata -> 'section_ids') value
      order by value
    )
  when nullif(a.metadata ->> 'section_id', '') is not null then
    array[(a.metadata ->> 'section_id')::uuid]
  else null
end
where a.section_ids is null
  and (
    jsonb_typeof(a.metadata -> 'section_ids') = 'array'
    or nullif(a.metadata ->> 'section_id', '') is not null
  );

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
  return new;
end;
$function$;

drop trigger if exists set_closeout_artifact_scope_columns
  on public.show_report_artifacts;
create trigger set_closeout_artifact_scope_columns
before insert or update of metadata, scope_key, section_ids
on public.show_report_artifacts
for each row execute function public.set_closeout_artifact_scope_columns();

create or replace function public.get_closeout_scope_sections(p_show_id uuid)
returns table(
  section_id uuid,
  kind text,
  letter text,
  display_name text,
  breed_scope text,
  allowed_breed_ids uuid[],
  is_enabled boolean,
  sort_order integer,
  species text[],
  entry_count integer
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select
    ss.id,
    ss.kind::text,
    ss.letter,
    ss.display_name,
    ss.breed_scope,
    ss.allowed_breed_ids,
    ss.is_enabled,
    ss.sort_order,
    array(
      select distinct source.species
      from (
        select lower(e.species::text) as species
        from public.entries e
        where e.show_id = ss.show_id and e.section_id = ss.id
        union all
        select lower(b.species::text)
        from public.breeds b
        where b.id = any(coalesce(ss.allowed_breed_ids, array[]::uuid[]))
      ) source
      where source.species in ('rabbit', 'cavy')
      order by source.species
    ),
    (select count(*)::integer from public.entries e
      where e.show_id = ss.show_id and e.section_id = ss.id)
  from public.show_sections ss
  where ss.show_id = p_show_id
  order by ss.sort_order, ss.id;
$function$;

drop function if exists public.finalize_show_scoped(uuid, uuid[], text);

create function public.finalize_show_scoped(
  p_show_id uuid,
  p_section_ids uuid[],
  p_scope_label text default 'Selected Scope',
  p_scope_key text default null
)
returns uuid
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
  v_section record;
begin
  select array_agg(sec.id order by sec.id)
  into v_section_ids
  from public.show_sections sec
  where sec.show_id = p_show_id
    and sec.is_enabled = true
    and sec.id = any(coalesce(p_section_ids, array[]::uuid[]));

  if coalesce(array_length(v_section_ids, 1), 0) = 0 then
    raise exception 'No enabled sections were selected for closeout.';
  end if;
  if array_length(v_section_ids, 1) <> array_length(p_section_ids, 1) then
    raise exception 'The closeout selection contains an invalid or disabled section.';
  end if;

  v_scope_key := coalesce(
    nullif(btrim(p_scope_key), ''),
    p_show_id::text || ':' || array_to_string(v_section_ids, ',')
  );
  select
    array_agg(distinct resolved_species order by resolved_species)
      filter (where resolved_species in ('rabbit', 'cavy')),
    array_agg(distinct upper(sec.letter) order by upper(sec.letter))
  into v_species, v_show_letters
  from public.show_sections sec
  left join lateral (
    select lower(e.species::text) resolved_species
    from public.entries e
    where e.show_id = p_show_id and e.section_id = sec.id
    union
    select lower(b.species::text)
    from public.breeds b
    where b.id = any(coalesce(sec.allowed_breed_ids, array[]::uuid[]))
  ) species_source on true
  where sec.id = any(v_section_ids);
  v_scope_metadata := jsonb_build_object(
    'scope_key', v_scope_key,
    'scope_label', coalesce(nullif(btrim(p_scope_label), ''), 'Selected Scope'),
    'section_ids', to_jsonb(v_section_ids),
    'species', to_jsonb(coalesce(v_species, array[]::text[])),
    'show_letters', to_jsonb(coalesce(v_show_letters, array[]::text[]))
  );

  perform public.ensure_show_closeout_state(p_show_id);
  perform public.prepare_club_delivery_targets(p_show_id);

  for v_section in
    select sec.kind, sec.letter
    from public.show_sections sec
    where sec.id = any(v_section_ids)
  loop
    perform public.calculate_sweepstakes_for_show(
      p_show_id,
      upper(v_section.kind::text),
      upper(v_section.letter)
    );
  end loop;

  select s.results_version into v_results_version
  from public.shows s where s.id = p_show_id;
  if v_results_version is null then
    raise exception 'Show % not found or results_version is null', p_show_id;
  end if;

  -- Serialize finalize creation for a show without turning a scoped report run
  -- into a global show lock.
  perform pg_advisory_xact_lock(hashtextextended(p_show_id::text, 0));

  insert into public.show_finalize_runs (
    show_id, run_status, started_at, results_version,
    scope_key, scope_label, section_ids
  ) values (
    p_show_id, 'running', now(), v_results_version,
    v_scope_key, p_scope_label, v_section_ids
  ) returning id into v_finalize_run_id;

  update public.show_report_artifacts a
  set is_current = false, superseded_at = now()
  where a.show_id = p_show_id
    and a.is_current = true
    and (
      a.scope_key = v_scope_key
      or (a.scope_key is null and a.section_ids = v_section_ids)
      or (
        a.scope_key is null
        and a.section_ids is null
        and nullif(a.metadata ->> 'section_id', '') = any(v_section_ids::text[])
      )
    );

  -- ARBA: one independently-failable artifact per selected section.
  insert into public.show_report_artifacts (
    show_id, finalize_run_id, report_name, artifact_status, metadata,
    is_current, scope_key, section_ids
  )
  select p_show_id, v_finalize_run_id, 'arba_report', 'queued',
    v_scope_metadata || jsonb_build_object(
      'section_id', sec.id,
      'show_letter', upper(sec.letter),
      'scope', upper(sec.kind::text),
      'section_label', coalesce(nullif(btrim(sec.display_name), ''), initcap(sec.kind::text) || ' ' || upper(sec.letter))
    ), true, v_scope_key, v_section_ids
  from public.show_sections sec
  where sec.id = any(v_section_ids);

  -- Do not queue empty exhibitor reports. A shown, non-scratched row in the
  -- exact selection is required; disqualification remains report-visible.
  insert into public.show_report_artifacts (
    show_id, finalize_run_id, report_name, artifact_status, metadata,
    is_current, scope_key, section_ids
  )
  select p_show_id, v_finalize_run_id, 'exhibitor_report', 'queued',
    v_scope_metadata || jsonb_build_object(
      'exhibitor_id', ex.id,
      'exhibitor_name', coalesce(nullif(btrim(ex.display_name), ''), btrim(coalesce(ex.first_name, '') || ' ' || coalesce(ex.last_name, '')))
    ), true, v_scope_key, v_section_ids
  from public.exhibitors ex
  where exists (
    select 1 from public.entries e
    where e.show_id = p_show_id
      and e.section_id = any(v_section_ids)
      and e.exhibitor_id = ex.id
      and e.is_shown = true
      and e.scratched_at is null
      and lower(coalesce(e.status, '')) <> 'scratched'
  );

  -- Legs are also scoped at job creation. Missing sanction data is handled by
  -- this artifact alone during rendering, never by the whole finalize run.
  insert into public.show_report_artifacts (
    show_id, finalize_run_id, report_name, artifact_status, metadata,
    is_current, scope_key, section_ids
  )
  select p_show_id, v_finalize_run_id, 'legs', 'queued',
    v_scope_metadata || jsonb_build_object(
      'exhibitor_id', ex.id,
      'exhibitor_name', coalesce(nullif(btrim(ex.display_name), ''), btrim(coalesce(ex.first_name, '') || ' ' || coalesce(ex.last_name, '')))
    ), true, v_scope_key, v_section_ids
  from public.exhibitors ex
  where exists (
    select 1
    from public.entries e
    join public.entry_awards ea on ea.entry_id = e.id
    where e.show_id = p_show_id
      and e.section_id = any(v_section_ids)
      and e.exhibitor_id = ex.id
      and e.is_shown = true
      and e.scratched_at is null
      and ea.award_code in ('BOB','BOSB','BOV','BOSV','BIS','RIS','BJB','BIB','BSB','BJV','BIV','BSV')
  );

  -- Club artifacts are tied to one selected section and are only seeded when
  -- that section contains qualifying shown data.
  insert into public.show_report_artifacts (
    show_id, finalize_run_id, report_name, artifact_status, metadata,
    is_current, scope_key, section_ids
  )
  select p_show_id, v_finalize_run_id, report.report_name, 'queued',
    v_scope_metadata || jsonb_build_object(
      'section_id', sec.id, 'scope', upper(sec.kind::text),
      'show_letter', upper(sec.letter), 'breed_name', coalesce(ss.breed_name, ''),
      'club_name', coalesce(ss.club_name, ''), 'sweepstakes_email', coalesce(ss.sweepstakes_email, ''),
      'sanction_number', coalesce(ss.sanction_number, ''),
      'sanctioning_body', upper(btrim(ss.sanctioning_body))
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
  where ss.show_id = p_show_id
    and sec.id = any(v_section_ids)
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

  perform public.sync_club_report_artifact_metadata(p_show_id, v_finalize_run_id);
  perform public.enqueue_report_render_tasks(p_show_id, v_finalize_run_id);
  perform public.refresh_show_reports_state(p_show_id);

  update public.show_finalize_runs
  set run_status = 'completed', completed_at = now()
  where id = v_finalize_run_id;
  return v_finalize_run_id;
exception when others then
  if v_finalize_run_id is not null then
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
