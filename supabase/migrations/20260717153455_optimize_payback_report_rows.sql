-- see committed migration 20260717153335_optimize_payback_report_rows.sql
do $block$
declare
  v_function_definition text;
begin
  select pg_get_functiondef(p.oid)
    into v_function_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'report_payback_rows'
    and p.proargtypes = '2950 2950'::pg_catalog.oidvector;

  if v_function_definition is null then
    raise exception 'public.report_payback_rows(uuid, uuid) is required';
  end if;

  v_function_definition := replace(
    v_function_definition,
    'scoped_entries AS (',
    'scoped_entries AS MATERIALIZED ('
  );
  v_function_definition := replace(
    v_function_definition,
    'best_display_breed_entry_rows AS (',
    'best_display_breed_entry_rows AS MATERIALIZED ('
  );

  execute v_function_definition;
end;
$block$;;
