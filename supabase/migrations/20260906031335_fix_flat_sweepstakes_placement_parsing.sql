-- The portal schedule calculator used a doubly escaped `\d` expression.
-- With standard-conforming strings enabled that looks for a literal
-- backslash, so no numeric placements entered the replacement point rows and
-- the generic class-size totals remained in place. Use an explicit digit
-- range so flat and multiplier schedules both consume numeric placements.
do $block$
declare
  v_definition text;
  v_broken_expression constant text := $needle$~ '^\\d+$'$needle$;
  v_fixed_expression constant text := $needle$~ '^[0-9]+$'$needle$;
begin
  select pg_catalog.pg_get_functiondef(
    'public.calculate_sweepstakes_for_breed_portal_class_schedule(uuid,text,text,text)'::regprocedure
  )
  into v_definition;

  if pg_catalog.strpos(v_definition, v_broken_expression) = 0 then
    raise exception
      'Expected numeric-placement expression was not found in the portal sweepstakes calculator';
  end if;

  v_definition := pg_catalog.replace(
    v_definition,
    v_broken_expression,
    v_fixed_expression
  );

  execute v_definition;
end;
$block$;

comment on function public.calculate_sweepstakes_for_breed_portal_class_schedule(
  uuid, text, text, text
) is
  'Calculates rabbit class points with the effective club schedule and correctly recognizes numeric placements.';
