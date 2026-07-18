-- Legacy finalize runs stored the finalize-run scope on every artifact. Newer
-- render workers require each artifact's canonical report/section scope. Make
-- Regenerate All route those legacy rows through the existing identity-safe
-- scope repair before attempting to reset and enqueue them.
do $block$
declare
  v_definition text;
  v_needle text := '  v_repair := public.repair_closeout_artifact_scopes(' || chr(10) ||
    '    p_show_id, p_finalize_run_id' || chr(10) ||
    '  );';
  v_replacement text;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'requeue_closeout_render_tasks'
    and p.proargtypes = '2950 2950 25 16'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception 'public.requeue_closeout_render_tasks is required';
  end if;
  if strpos(v_definition, v_needle) = 0 then
    raise exception 'Scope-repair call was not found in requeue_closeout_render_tasks';
  end if;

  v_replacement :=
    '  if p_regenerate_all then' || chr(10) ||
    '    update public.show_report_artifacts a' || chr(10) ||
    '    set artifact_status = ''failed''::public.artifact_status,' || chr(10) ||
    '        metadata = a.metadata || jsonb_build_object(' || chr(10) ||
    '          ''error_category'', ''invalid_scope'',' || chr(10) ||
    '          ''error_message'', ''Legacy artifact scope requires canonical repair.''' || chr(10) ||
    '        )' || chr(10) ||
    '    where a.show_id = p_show_id' || chr(10) ||
    '      and a.finalize_run_id = p_finalize_run_id' || chr(10) ||
    '      and a.is_current = true' || chr(10) ||
    '      and a.report_name <> ''arba_report''::public.report_type' || chr(10) ||
    '      and a.scope_key is distinct from public.closeout_artifact_scope_key(' || chr(10) ||
    '        a.show_id, a.report_name, a.section_ids, a.metadata' || chr(10) ||
    '      );' || chr(10) ||
    '  end if;' || chr(10) || chr(10) ||
    v_needle;

  execute replace(v_definition, v_needle, v_replacement);
end;
$block$;

comment on function public.requeue_closeout_render_tasks(uuid, uuid, text, boolean)
is 'Repairs legacy artifact scopes when regenerating all, then resets and queues canonical report render tasks.';
