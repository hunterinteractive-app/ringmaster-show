-- The report row helper does not expose section_letter; the enclosing section
-- supplies that value for the saved per-entry point records.
do $block$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.calculate_sweepstakes_for_breed_legacy(uuid,text,text,text)'::regprocedure
  ) into v_definition;

  v_definition := replace(
    v_definition,
    '      row.section_letter,',
    '      section.letter::text as section_letter,'
  );

  execute v_definition;
end;
$block$;
