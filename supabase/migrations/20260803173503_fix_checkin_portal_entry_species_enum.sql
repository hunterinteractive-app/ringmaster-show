-- entries.species is also an enum. Normalize it as text before comparing it
-- to the portal helper's text species value.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.get_exhibitor_checkin_entry_selection_options(text,uuid,uuid)'::regprocedure
  ) into v_definition;

  if position('lower(coalesce(v_entry.species, ''rabbit''))' in v_definition) = 0 then
    raise exception 'Expected check-in selection helper definition was not found';
  end if;

  execute replace(
    v_definition,
    'lower(coalesce(v_entry.species, ''rabbit''))',
    'lower(coalesce(v_entry.species::text, ''rabbit''))'
  );
end;
$$;
