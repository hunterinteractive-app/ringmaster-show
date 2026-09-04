-- Older closeout artifacts can retain an historic finalize-run/scope mapping.
-- The caller's artifact selection is validated by the requeue functions themselves,
-- so the metadata refresh must not reject a valid artifact solely because its
-- finalize-run row has since been replaced or re-scoped.
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
    and a.scope_key = p_scope_key
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

comment on function public.refresh_closeout_exhibitor_artifact_metadata(
  uuid, uuid, text, uuid
) is 'Refreshes exhibitor report metadata from the current exhibitor record while preserving legacy closeout artifact scope compatibility.';
