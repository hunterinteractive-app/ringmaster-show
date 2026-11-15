-- Show-level breed awards do not confer recognition, legs, or finals eligibility.
-- Keep the section judging-date recognition checks and private trigger ACLs.
begin;
create or replace function public.cod_has_disallowed_awards(p_awards text)
returns boolean language sql immutable security invoker set search_path = '' as $$
  select exists(select 1 from regexp_split_to_table(coalesce(p_awards, ''), '[,;|]+') a
    where upper(trim(a)) not in ('', 'BOV', 'BOSV', 'BOB', 'BOSB'));
$$;
revoke all on function public.cod_has_disallowed_awards(text) from public, anon;
grant execute on function public.cod_has_disallowed_awards(text) to authenticated, service_role;

-- Only update the explanation in existing validators. Preserve their scopes,
-- security attributes, final-award population filters, and recognition logic.
do $$
declare target regprocedure; definition text;
begin
  foreach target in array array[
    'show_awards_private.validate_cod_awards()'::regprocedure,
    'public.show_results_readiness_scoped(uuid,uuid[])'::regprocedure
  ] loop
    definition := pg_get_functiondef(target);
    if strpos(definition, 'COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.') = 0 then
      raise exception 'Unexpected COD validator definition: %', target;
    end if;
    execute replace(definition,
      'COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.',
      'COD entries may receive class placements, BOV, BOSV, BOB, and BOSB, but cannot earn legs or final awards.');
  end loop;
end $$;
commit;
