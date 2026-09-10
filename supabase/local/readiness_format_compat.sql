-- LOCAL BOOTSTRAP ONLY. The August 25 definition compresses this predicate
-- onto the FROM line. The September 3 migration expects a newline and four
-- spaces. Normalize whitespace only so the tracked zero-placement fix can run.
do $$
declare
  definition text := pg_get_functiondef('public.show_results_readiness_scoped(uuid,uuid[])'::regprocedure);
  original constant text := 'from required_results where placement is not null';
  replacement constant text := E'from required_results\n    where placement is not null';
begin
  if strpos(definition, original) = 0 then
    raise exception 'Unexpected readiness definition before local whitespace normalization';
  end if;
  execute replace(definition, original, replacement);
end $$;
