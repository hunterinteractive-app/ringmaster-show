-- JSON exports and ACBA companion reports are seeded on INSERT only. A manifest
-- rebuild must revive them with their current parent instead of silently hiding
-- already-generated files. Removed sanctions still have no current parent.
do $migration$
declare definition text;
begin
  select pg_get_functiondef('public.rebuild_closeout_club_report_manifest(uuid,uuid,text,text)'::regprocedure) into definition;
  if position('  return jsonb_build_object(' in definition) = 0
     or position('v_companion_count' in definition) > 0 then
    raise exception 'Unexpected club manifest function; review companion repair';
  end if;
  definition := replace(definition,
    '  v_superseded_count integer := 0;',
    '  v_superseded_count integer := 0;' || chr(10) || '  v_companion_count integer := 0;');
  definition := replace(definition, '  return jsonb_build_object(', $patch$
  update public.show_report_artifacts companion
  set is_current = true, superseded_at = null
  where companion.show_id = p_show_id
    and companion.finalize_run_id = p_finalize_run_id
    and not companion.is_current
    and (v_species_filter is null
      or lower(btrim(companion.metadata ->> 'species')) = v_species_filter)
    and (
      companion.report_name = 'sweepstakes_json_export'::public.report_type
      or (
        companion.report_name in ('details_by_breed'::public.report_type, 'exh_by_breed'::public.report_type)
        and lower(btrim(companion.metadata ->> 'breed_name')) = 'cavy'
        and upper(btrim(companion.metadata ->> 'sanctioning_body')) = 'NATIONAL CLUB'
      )
    )
    and exists (
      select 1 from public.show_report_artifacts parent
      where parent.show_id = companion.show_id
        and parent.finalize_run_id = companion.finalize_run_id
        and parent.report_name = 'sweepstakes_report'::public.report_type
        and parent.is_current
        and parent.section_ids = companion.section_ids
        and lower(btrim(parent.metadata ->> 'species')) = lower(btrim(companion.metadata ->> 'species'))
        and lower(btrim(parent.metadata ->> 'breed_name')) = lower(btrim(companion.metadata ->> 'breed_name'))
        and lower(btrim(parent.metadata ->> 'club_name')) = lower(btrim(companion.metadata ->> 'club_name'))
        and upper(btrim(parent.metadata ->> 'sanctioning_body')) = upper(btrim(companion.metadata ->> 'sanctioning_body'))
    );
  get diagnostics v_companion_count = row_count;

  return jsonb_build_object($patch$);
  definition := replace(definition,
    'v_superseded_count - v_refreshed_count,',
    'v_superseded_count - v_refreshed_count - v_companion_count,');
  execute definition;
end;
$migration$;
