-- Regenerate All previously requeued only artifacts captured by the original
-- finalize run. Sanctions added or edited afterward were therefore invisible
-- to the delivery dashboard. Rebuild the club slice of that immutable run
-- before requeueing while preserving non-club artifacts and historical rows.

create or replace function public.rebuild_closeout_club_report_manifest(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_scope_key text,
  p_species_filter text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_run public.show_finalize_runs%rowtype;
  v_species_filter text := nullif(
    lower(btrim(coalesce(p_species_filter, ''))), ''
  );
  v_show_letters text[];
  v_candidate record;
  v_scope record;
  v_artifact_id uuid;
  v_expected_count integer := 0;
  v_inserted_count integer := 0;
  v_refreshed_count integer := 0;
  v_superseded_count integer := 0;
begin
  if v_species_filter is not null
     and v_species_filter not in ('rabbit', 'cavy') then
    raise exception 'Unsupported closeout species filter: %', p_species_filter;
  end if;

  select f.*
  into v_run
  from public.show_finalize_runs f
  where f.id = p_finalize_run_id
    and f.show_id = p_show_id
    and f.scope_key = p_scope_key
  for update;

  if v_run.id is null then
    raise exception 'Finalize run does not match the requested show and scope';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_show_id::text || ':' || p_finalize_run_id::text ||
      ':club-manifest-rebuild',
    0
  ));

  select array_agg(distinct upper(sec.letter) order by upper(sec.letter))
  into v_show_letters
  from public.show_sections sec
  where sec.show_id = p_show_id
    and sec.id = any(v_run.section_ids);

  -- Start with no current club artifacts in the selected species slice. Rows
  -- that remain valid are revived below by their canonical artifact identity;
  -- removed sanctions stay historical instead of being deleted.
  update public.show_report_artifacts a
  set is_current = false,
      superseded_at = coalesce(a.superseded_at, now())
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and (
      lower(btrim(coalesce(a.metadata ->> 'delivery_type', ''))) = 'club'
      or (
        nullif(btrim(a.metadata ->> 'club_name'), '') is not null
        and a.report_name in (
          'sweepstakes_report'::public.report_type,
          'breed_results_detail_report'::public.report_type,
          'details_by_breed'::public.report_type,
          'exh_by_breed'::public.report_type,
          'best_display_report'::public.report_type
        )
      )
    )
    and (
      v_species_filter is null
      or lower(btrim(coalesce(a.metadata ->> 'species', ''))) =
        v_species_filter
    );
  get diagnostics v_superseded_count = row_count;

  -- Pick the newest sanction row for a canonical club/report identity. This
  -- makes duplicate legacy sanction rows deterministic without discarding
  -- their history or depending on file names.
  for v_candidate in
    with candidates as (
      select
        ss.id sanction_id,
        ss.updated_at sanction_updated_at,
        sec.id section_id,
        sec.kind::text section_kind,
        sec.letter show_letter,
        sec.display_name section_label,
        report.report_name,
        lower(e_species.species) species,
        coalesce(ss.breed_name, '') breed_name,
        coalesce(ss.club_name, '') club_name,
        coalesce(ss.sweepstakes_email, '') sweepstakes_email,
        coalesce(ss.sanction_number, '') sanction_number,
        upper(btrim(ss.sanctioning_body)) sanctioning_body
      from public.show_sanctions ss
      join public.show_sections sec
        on sec.id = ss.section_id
       and sec.show_id = ss.show_id
      cross join lateral (
        select unnest(
          case
            when upper(btrim(ss.sanctioning_body)) = 'STATE CLUB' then
              array[
                'details_by_breed',
                'exh_by_breed',
                'best_display_report'
              ]::public.report_type[]
            else
              array[
                'sweepstakes_report',
                'breed_results_detail_report'
              ]::public.report_type[]
          end
        ) report_name
      ) report
      join lateral (
        select distinct lower(entry.species::text) species
        from public.entries entry
        where entry.show_id = p_show_id
          and entry.section_id = sec.id
          and entry.is_shown = true
          and entry.scratched_at is null
          and (
            upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
            or lower(btrim(coalesce(entry.breed, ''))) =
              lower(btrim(coalesce(ss.breed_name, '')))
          )
      ) e_species on true
      where ss.show_id = p_show_id
        and sec.id = any(v_run.section_ids)
        and upper(btrim(ss.sanctioning_body)) in (
          'NATIONAL CLUB', 'STATE BREED CLUB', 'STATE CLUB'
        )
        and (
          v_species_filter is null
          or lower(e_species.species) = v_species_filter
        )
    )
    select distinct on (
      report_name,
      section_id,
      lower(btrim(club_name)),
      lower(btrim(breed_name)),
      species,
      sanctioning_body
    ) *
    from candidates
    order by
      report_name,
      section_id,
      lower(btrim(club_name)),
      lower(btrim(breed_name)),
      species,
      sanctioning_body,
      sanction_updated_at desc nulls last,
      sanction_id desc
  loop
    select *
    into v_scope
    from public.resolve_closeout_artifact_scope(
      p_show_id,
      p_finalize_run_id,
      v_candidate.report_name,
      jsonb_build_object(
        'scope_label', coalesce(
          nullif(btrim(v_run.scope_label), ''), 'Selected Scope'
        ),
        'show_letters', to_jsonb(coalesce(v_show_letters, '{}'::text[])),
        'section_id', v_candidate.section_id,
        'section_label', coalesce(
          nullif(btrim(v_candidate.section_label), ''),
          initcap(v_candidate.section_kind) || ' ' ||
            upper(v_candidate.show_letter)
        ),
        'scope', upper(v_candidate.section_kind),
        'show_letter', upper(v_candidate.show_letter),
        'breed_name', v_candidate.breed_name,
        'club_name', v_candidate.club_name,
        'species', v_candidate.species,
        'sweepstakes_email', v_candidate.sweepstakes_email,
        'sanction_number', v_candidate.sanction_number,
        'sanctioning_body', v_candidate.sanctioning_body,
        'delivery_type', 'club'
      )
    );

    if not coalesce(v_scope.is_repairable, false) then
      raise exception 'Cannot rebuild club artifact scope: %',
        coalesce(v_scope.failure_reason, 'unknown_scope');
    end if;

    v_expected_count := v_expected_count + 1;
    v_artifact_id := null;

    select a.id
    into v_artifact_id
    from public.show_report_artifacts a
    where a.finalize_run_id = p_finalize_run_id
      and a.artifact_key = v_scope.artifact_key
    limit 1
    for update;

    if v_artifact_id is null then
      insert into public.show_report_artifacts (
        show_id,
        finalize_run_id,
        report_name,
        artifact_status,
        metadata,
        is_current,
        scope_key,
        section_ids,
        artifact_key
      ) values (
        p_show_id,
        p_finalize_run_id,
        v_candidate.report_name,
        'queued'::public.artifact_status,
        v_scope.metadata,
        true,
        v_scope.scope_key,
        v_scope.section_ids,
        v_scope.artifact_key
      );
      v_inserted_count := v_inserted_count + 1;
    else
      update public.show_report_artifacts a
      set metadata = v_scope.metadata,
          is_current = true,
          superseded_at = null
      where a.id = v_artifact_id;
      v_refreshed_count := v_refreshed_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'expected_count', v_expected_count,
    'inserted_count', v_inserted_count,
    'refreshed_count', v_refreshed_count,
    'superseded_count', greatest(
      v_superseded_count - v_refreshed_count,
      0
    ),
    'species_filter', v_species_filter
  );
end;
$function$;

revoke all on function public.rebuild_closeout_club_report_manifest(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.rebuild_closeout_club_report_manifest(
  uuid, uuid, text, text
) to service_role;

-- Keep the existing requeue implementation and its accumulated eligibility
-- safeguards intact. Inject one rebuild call into Regenerate All before its
-- scope repair and task requeue steps.
do $migration$
declare
  v_definition text;
  v_declaration_anchor text := '  v_repair jsonb;';
  v_declaration_replacement text := v_declaration_anchor || chr(10) ||
    '  v_club_manifest jsonb := ''{}''::jsonb;';
  v_requeue_anchor text := '  if p_regenerate_all then' || chr(10) ||
    '    update public.show_report_artifacts a' || chr(10) ||
    '    set artifact_status = ''failed''::public.artifact_status,';
  v_requeue_replacement text :=
    '  if p_regenerate_all then' || chr(10) ||
    '    v_club_manifest := public.rebuild_closeout_club_report_manifest(' ||
      chr(10) ||
    '      p_show_id, p_finalize_run_id, p_scope_key, v_species' || chr(10) ||
    '    );' || chr(10) ||
    '  end if;' || chr(10) || chr(10) ||
    v_requeue_anchor;
  v_return_anchor text :=
    '    ''species_filter'', v_species,' || chr(10) ||
    '    ''repaired_count''';
  v_return_replacement text :=
    '    ''species_filter'', v_species,' || chr(10) ||
    '    ''club_manifest'', v_club_manifest,' || chr(10) ||
    '    ''repaired_count''';
begin
  select pg_get_functiondef(proc.oid)
  into v_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'requeue_closeout_render_tasks_for_species'
    and proc.proargtypes = '2950 2950 25 16 25'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception
      'public.requeue_closeout_render_tasks_for_species is required';
  end if;
  if strpos(v_definition, v_declaration_anchor) = 0
     or strpos(v_definition, v_requeue_anchor) = 0
     or strpos(v_definition, v_return_anchor) = 0 then
    raise exception 'Closeout requeue function does not match expected shape';
  end if;
  if strpos(v_definition, 'rebuild_closeout_club_report_manifest') > 0 then
    raise exception 'Club manifest rebuild is already installed';
  end if;

  v_definition := replace(
    v_definition,
    v_declaration_anchor,
    v_declaration_replacement
  );
  v_definition := replace(
    v_definition,
    v_requeue_anchor,
    v_requeue_replacement
  );
  v_definition := replace(
    v_definition,
    v_return_anchor,
    v_return_replacement
  );
  execute v_definition;
end;
$migration$;

revoke all on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) from public, anon;
grant execute on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) to authenticated, service_role;

comment on function public.rebuild_closeout_club_report_manifest(
  uuid, uuid, text, text
) is 'Reconciles current club report artifacts with current sanctions and qualifying shown entries for a finalized closeout scope.';

comment on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) is 'Rebuilds the current club manifest during Regenerate All, then repairs and requeues canonical Closeout artifacts for an optional species.';

-- Fail the migration if the integration call was not installed exactly once.
do $verification$
declare
  v_definition text;
  v_call_count integer;
begin
  select pg_get_functiondef(proc.oid)
  into v_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'requeue_closeout_render_tasks_for_species'
    and proc.proargtypes = '2950 2950 25 16 25'::pg_catalog.oidvector;

  v_call_count := (
    length(v_definition) - length(replace(
      v_definition,
      'public.rebuild_closeout_club_report_manifest',
      ''
    ))
  ) / length('public.rebuild_closeout_club_report_manifest');

  if v_call_count <> 1 then
    raise exception 'Expected one club manifest rebuild call, found %',
      v_call_count;
  end if;
end;
$verification$;
