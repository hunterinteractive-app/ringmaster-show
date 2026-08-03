-- breeds.species is an enum, while the token-scoped helper intentionally
-- normalizes the requested species to text. Cast the enum at both lookups.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.get_exhibitor_checkin_entry_selection_options(text,uuid,uuid)'::regprocedure
  ) into v_definition;

  if position('b.species = v_species' in v_definition) = 0 then
    raise exception 'Expected check-in selection helper definition was not found';
  end if;

  execute replace(
    v_definition,
    'b.species = v_species',
    'b.species::text = v_species'
  );
end;
$$;
