-- A report artifact keeps delivery metadata so a generated package can be
-- resent later.  That metadata must not become a second source of truth for
-- an exhibitor's name or email: after a secretary corrects the exhibitor,
-- regeneration needs to use the corrected contact details.
create or replace function public.refresh_closeout_exhibitor_artifact_metadata(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_scope_key text,
  p_artifact_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_refreshed_count integer := 0;
begin
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

  update public.show_report_artifacts a
  set metadata = a.metadata || jsonb_build_object(
    'exhibitor_name', coalesce(
      nullif(btrim(ex.display_name), ''),
      nullif(btrim(ex.showing_name), ''),
      nullif(btrim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
      nullif(btrim(a.metadata ->> 'exhibitor_name'), ''),
      'Exhibitor'
    ),
    'exhibitor_email', coalesce(
      nullif(btrim(ex.email), ''),
      nullif(btrim(a.metadata ->> 'exhibitor_email'), ''),
      nullif(btrim(a.metadata ->> 'email'), ''),
      ''
    ),
    'email', coalesce(
      nullif(btrim(ex.email), ''),
      nullif(btrim(a.metadata ->> 'exhibitor_email'), ''),
      nullif(btrim(a.metadata ->> 'email'), ''),
      ''
    )
  )
  from public.exhibitors ex
  where a.show_id = p_show_id
    and a.finalize_run_id = p_finalize_run_id
    and a.is_current = true
    and a.report_name in (
      'exhibitor_report'::public.report_type,
      'legs'::public.report_type,
      'checkin_sheet'::public.report_type
    )
    and (p_artifact_id is null or a.id = p_artifact_id)
    and a.metadata ->> 'exhibitor_id' ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and ex.id = (a.metadata ->> 'exhibitor_id')::uuid;
  get diagnostics v_refreshed_count = row_count;

  return jsonb_build_object('refreshed_count', v_refreshed_count);
end;
$function$;

revoke all on function public.refresh_closeout_exhibitor_artifact_metadata(
  uuid, uuid, text, uuid
) from public, anon;
grant execute on function public.refresh_closeout_exhibitor_artifact_metadata(
  uuid, uuid, text, uuid
) to authenticated, service_role;

-- A one-off retry must receive the same refreshed metadata as Requeue All.
do $migration$
declare
  v_definition text;
  v_anchor text := '  update public.show_report_artifacts a' || chr(10) ||
    '  set artifact_status = ''queued''::public.artifact_status,';
  v_replacement text :=
    '  perform public.refresh_closeout_exhibitor_artifact_metadata(' || chr(10) ||
    '    p_show_id, p_finalize_run_id, p_scope_key, p_artifact_id' || chr(10) ||
    '  );' || chr(10) || chr(10) ||
    v_anchor;
begin
  select pg_get_functiondef(proc.oid)
  into v_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'requeue_single_closeout_artifact'
    and proc.proargtypes = '2950 2950 25 2950'::pg_catalog.oidvector;

  if v_definition is null or strpos(v_definition, v_anchor) = 0 then
    raise exception 'Single-artifact requeue function does not match expected shape';
  end if;
  if strpos(v_definition, 'refresh_closeout_exhibitor_artifact_metadata') > 0 then
    raise exception 'Single-artifact metadata refresh is already installed';
  end if;

  execute replace(v_definition, v_anchor, v_replacement);
end;
$migration$;

-- Requeue All must also rebuild exhibitor metadata before it creates the
-- render-task payloads.  The function is patched rather than redefined so it
-- retains the current scope and species safeguards installed by prior fixes.
do $migration$
declare
  v_definition text;
  v_anchor text := '  if p_regenerate_all then' || chr(10) ||
    '    v_club_manifest := public.rebuild_closeout_club_report_manifest(';
  v_replacement text := '  if p_regenerate_all then' || chr(10) ||
    '    perform public.refresh_closeout_exhibitor_artifact_metadata(' || chr(10) ||
    '      p_show_id, p_finalize_run_id, p_scope_key, null' || chr(10) ||
    '    );' || chr(10) ||
    '    v_club_manifest := public.rebuild_closeout_club_report_manifest(';
begin
  select pg_get_functiondef(proc.oid)
  into v_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'requeue_closeout_render_tasks_for_species'
    and proc.proargtypes = '2950 2950 25 16 25'::pg_catalog.oidvector;

  if v_definition is null or strpos(v_definition, v_anchor) = 0 then
    raise exception 'Closeout requeue function does not match expected shape';
  end if;
  if strpos(v_definition, 'refresh_closeout_exhibitor_artifact_metadata') > 0 then
    raise exception 'Exhibitor metadata refresh is already installed';
  end if;

  execute replace(v_definition, v_anchor, v_replacement);
end;
$migration$;

revoke all on function public.requeue_single_closeout_artifact(uuid, uuid, text, uuid)
  from public, anon;
grant execute on function public.requeue_single_closeout_artifact(uuid, uuid, text, uuid)
  to authenticated, service_role;

revoke all on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) from public, anon;
grant execute on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
) to authenticated, service_role;

comment on function public.refresh_closeout_exhibitor_artifact_metadata(
  uuid, uuid, text, uuid
) is 'Refreshes exhibitor report artifact contact metadata from the current show exhibitor record before report regeneration.';
