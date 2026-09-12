-- Keep the existing-assignment lookup as an anti-join. An OR around the
-- correlated NOT EXISTS can cause a separate growing-table scan per animal.
-- Preserve the installed function's permission checks, ordering and metadata.
do $migration$
declare
  v_function regprocedure := to_regprocedure('public.assign_show_coop_numbers(uuid,text,boolean)');
  v_definition text;
  v_old text := E'  where p_overwrite_existing\n     or not exists (';
  v_lookup text := '       where existing.show_id = p_show_id';
  v_new_lookup text := E'       where not coalesce(p_overwrite_existing, false)\n         and existing.show_id = p_show_id';
begin
  -- The loader-only local baseline does not contain this historical function.
  -- Full-event preparation reapplies this migration after restoring it.
  if v_function is null then
    raise notice 'Coop assignment is not installed in this schema';
    return;
  end if;
  v_definition := pg_get_functiondef(v_function);
  if position(v_new_lookup in v_definition) > 0 then
    return;
  end if;
  if (length(v_definition) - length(replace(v_definition, v_old, ''))) <> length(v_old)
     or (length(v_definition) - length(replace(v_definition, v_lookup, ''))) <> length(v_lookup) then
    raise exception 'Unexpected coop assignment definition; review before applying the lookup optimization';
  end if;
  v_definition := replace(v_definition, v_old, '  where not exists (');
  v_definition := replace(v_definition, v_lookup, v_new_lookup);
  execute v_definition;
end;
$migration$;
