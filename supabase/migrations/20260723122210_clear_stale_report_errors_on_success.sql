do $block$
declare
  v_definition text;
  v_updated text;
  v_old text := 'metadata = a.metadata - ''error_message''';
  v_new text :=
    'metadata = a.metadata'
    || ' - ''error_message'''
    || ' - ''last_error'''
    || ' - ''error_category'''
    || ' - ''missing_field'''
    || ' - ''missing_label''';
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'complete_report_render_task'
    and p.proargtypes =
      '2950 25 25 25 25 25 20 25'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception 'public.complete_report_render_task is required';
  end if;
  if strpos(v_definition, v_old) = 0 then
    raise exception 'Artifact success metadata update was not found';
  end if;

  v_updated := replace(v_definition, v_old, v_new);
  execute v_updated;
end;
$block$;

do $block$
declare
  v_definition text;
  v_updated text;
  v_old text :=
    'metadata = a.metadata - ''error_category'' - ''error_message''';
  v_new text :=
    'metadata = a.metadata'
    || ' - ''error_category'''
    || ' - ''error_message'''
    || ' - ''last_error'''
    || ' - ''missing_field'''
    || ' - ''missing_label''';
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'requeue_closeout_artifacts'
    and p.pronargs = 5;

  if v_definition is null then
    raise exception 'public.requeue_closeout_artifacts is required';
  end if;
  if strpos(v_definition, v_old) = 0 then
    raise exception 'Artifact requeue metadata update was not found';
  end if;

  v_updated := replace(v_definition, v_old, v_new);
  execute v_updated;
end;
$block$;
