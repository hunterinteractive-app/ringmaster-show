-- National cavy club sanctions use the aggregate breed label "Cavy" while
-- entries retain their individual breeds (American, Peruvian, Teddy, etc.).
-- Treat that sanction label as a species match in both initial finalization
-- and later Regenerate All manifest rebuilds.

do $migration$
declare
  v_rebuild_definition text;
  v_finalize_definition text;
  v_rebuild_anchor text :=
    '            or lower(btrim(coalesce(entry.breed, ''''))) =' || chr(10) ||
    '              lower(btrim(coalesce(ss.breed_name, '''')))';
  v_rebuild_replacement text :=
    '            or (' || chr(10) ||
    '              lower(btrim(coalesce(ss.breed_name, ''''))) = ''cavy''' ||
      chr(10) ||
    '              and lower(entry.species::text) = ''cavy''' || chr(10) ||
    '            )' || chr(10) ||
    v_rebuild_anchor;
  v_finalize_anchor text :=
    '          or lower(btrim(coalesce(e.breed, ''''))) = lower(btrim(coalesce(ss.breed_name, '''')))';
  v_finalize_replacement text :=
    '          or (' || chr(10) ||
    '            lower(btrim(coalesce(ss.breed_name, ''''))) = ''cavy''' ||
      chr(10) ||
    '            and lower(e.species::text) = ''cavy''' || chr(10) ||
    '          )' || chr(10) ||
    v_finalize_anchor;
  v_occurrences integer;
begin
  select pg_catalog.pg_get_functiondef(proc.oid)
  into v_rebuild_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'rebuild_closeout_club_report_manifest'
    and proc.proargtypes = '2950 2950 25 25'::pg_catalog.oidvector;

  if v_rebuild_definition is null then
    raise exception
      'public.rebuild_closeout_club_report_manifest is required';
  end if;

  v_occurrences := (
    length(v_rebuild_definition) - length(replace(
      v_rebuild_definition,
      v_rebuild_anchor,
      ''
    ))
  ) / length(v_rebuild_anchor);

  if v_occurrences <> 1 then
    raise exception
      'Expected one exact-breed predicate in rebuild manifest, found %',
      v_occurrences;
  end if;

  execute replace(
    v_rebuild_definition,
    v_rebuild_anchor,
    v_rebuild_replacement
  );

  select pg_catalog.pg_get_functiondef(proc.oid)
  into v_finalize_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'finalize_show_scoped'
    and proc.proargtypes = '2950 2951 25 25'::pg_catalog.oidvector;

  if v_finalize_definition is null then
    raise exception 'public.finalize_show_scoped is required';
  end if;

  v_occurrences := (
    length(v_finalize_definition) - length(replace(
      v_finalize_definition,
      v_finalize_anchor,
      ''
    ))
  ) / length(v_finalize_anchor);

  if v_occurrences <> 2 then
    raise exception
      'Expected two exact-breed predicates in finalization, found %',
      v_occurrences;
  end if;

  execute replace(
    v_finalize_definition,
    v_finalize_anchor,
    v_finalize_replacement
  );
end;
$migration$;

comment on function public.rebuild_closeout_club_report_manifest(
  uuid, uuid, text, text
) is 'Reconciles current club report artifacts with current sanctions and qualifying shown entries, including aggregate Cavy national-club sanctions, for a finalized closeout scope.';

comment on function public.finalize_show_scoped(uuid, uuid[], text, text) is
  'Creates an immutable closeout manifest after strict readiness validation; aggregate Cavy national-club sanctions match all shown cavy breeds.';

-- Fail closed if either function was not patched exactly as intended.
do $verification$
declare
  v_definition text;
  v_occurrences integer;
begin
  select pg_catalog.pg_get_functiondef(proc.oid)
  into v_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'rebuild_closeout_club_report_manifest'
    and proc.proargtypes = '2950 2950 25 25'::pg_catalog.oidvector;

  v_occurrences := (
    length(v_definition) - length(replace(
      v_definition,
      'lower(btrim(coalesce(ss.breed_name, ''''))) = ''cavy''',
      ''
    ))
  ) / length('lower(btrim(coalesce(ss.breed_name, ''''))) = ''cavy''');

  if v_occurrences <> 1 then
    raise exception
      'Expected one aggregate Cavy predicate in rebuild manifest, found %',
      v_occurrences;
  end if;

  select pg_catalog.pg_get_functiondef(proc.oid)
  into v_definition
  from pg_catalog.pg_proc proc
  join pg_catalog.pg_namespace namespace
    on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'finalize_show_scoped'
    and proc.proargtypes = '2950 2951 25 25'::pg_catalog.oidvector;

  v_occurrences := (
    length(v_definition) - length(replace(
      v_definition,
      'lower(btrim(coalesce(ss.breed_name, ''''))) = ''cavy''',
      ''
    ))
  ) / length('lower(btrim(coalesce(ss.breed_name, ''''))) = ''cavy''');

  if v_occurrences <> 2 then
    raise exception
      'Expected two aggregate Cavy predicates in finalization, found %',
      v_occurrences;
  end if;
end;
$verification$;
