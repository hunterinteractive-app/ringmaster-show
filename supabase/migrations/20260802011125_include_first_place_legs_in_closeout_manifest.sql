-- Class first-place legs are stored on entries.placement, while the other
-- leg-eligible wins are stored in entry_awards.  The closeout manifest
-- previously looked only at entry_awards, so a first-place-only winner never
-- received a Legs artifact for the renderer to evaluate.
do $block$
declare
  v_definition text;
  v_join_needle text :=
    '      join public.entry_awards ea on ea.entry_id = e.id';
  v_award_needle text :=
    '        and ea.award_code in (';
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'finalize_show_scoped'
    and p.proargtypes = '2950 2951 25 25'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception
      'public.finalize_show_scoped(uuid, uuid[], text, text) is required';
  end if;

  -- The live function may already have this repair from an operational
  -- recovery before this migration is deployed through normal history.
  if position(
    '      left join public.entry_awards ea on ea.entry_id = e.id'
    in v_definition
  ) > 0 and position(
    '        and (e.placement::text = ''1'' or ea.award_code in ('
    in v_definition
  ) > 0 then
    return;
  end if;

  if (
    length(v_definition) - length(replace(v_definition, v_join_needle, ''))
  ) / length(v_join_needle) <> 1 then
    raise exception
      'Expected one legs award join in finalize_show_scoped';
  end if;

  if (
    length(v_definition) - length(replace(v_definition, v_award_needle, ''))
  ) / length(v_award_needle) <> 1 then
    raise exception
      'Expected one legs award predicate in finalize_show_scoped';
  end if;

  v_definition := replace(
    v_definition,
    v_join_needle,
    '      left join public.entry_awards ea on ea.entry_id = e.id'
  );
  v_definition := replace(
    v_definition,
    v_award_needle,
    '        and (e.placement::text = ''1'' or ea.award_code in ('
  );

  -- Close the new grouping before the existing EXISTS predicate closes.
  v_definition := replace(
    v_definition,
    '''BJB'',''BIB'',''BSB'',''BJV'',''BIV'',''BSV'')' || chr(10) ||
      '    );' || chr(10) || chr(10) ||
      '    -- Club identities',
    '''BJB'',''BIB'',''BSB'',''BJV'',''BIV'',''BSV''))' || chr(10) ||
      '    );' || chr(10) || chr(10) ||
      '    -- Club identities'
  );

  execute v_definition;
end;
$block$;
