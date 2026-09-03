-- Placement 0 records that judging is complete but the animal did not place.
-- It must satisfy the entered-result check without forming a duplicate rank.

do $migration$
declare
  v_definition text;
  v_target constant text := '    where placement is not null';
  v_replacement constant text :=
    '    where placement is not null and placement <> ''0''';
  v_target_count integer;
begin
  select pg_get_functiondef(
    'public.show_results_readiness_scoped(uuid,uuid[])'::regprocedure
  )
  into v_definition;

  v_target_count := (
    length(v_definition) - length(replace(v_definition, v_target, ''))
  ) / length(v_target);

  if v_target_count <> 1 then
    raise exception
      'Expected one duplicate-placement predicate in show_results_readiness_scoped; found %',
      v_target_count;
  end if;

  execute replace(v_definition, v_target, v_replacement);
end;
$migration$;

comment on function public.show_results_readiness_scoped(uuid, uuid[]) is
  'Checks scoped result and final-award readiness; placement 0 is entered but unplaced and is excluded from duplicate-rank detection.';

do $verify$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.show_results_readiness_scoped(uuid,uuid[])'::regprocedure
  )
  into v_definition;

  if strpos(
    v_definition,
    'where placement is not null and placement <> ''0'''
  ) = 0 then
    raise exception 'Zero-placement duplicate exclusion was not installed';
  end if;
end;
$verify$;
