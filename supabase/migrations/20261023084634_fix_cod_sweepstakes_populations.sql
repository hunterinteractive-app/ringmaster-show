-- Exclude explicit COD entries from every rabbit sweepstakes population.
-- Completed-show caches and historical placements are intentionally retained.
do $block$
declare
  fn text;
  definition text;
  needle text;
  replacement text;
begin
  foreach fn in array array['calculate_sweepstakes_for_breed_baseline', 'calculate_sweepstakes_for_breed_portal_class_schedule', 'calculate_sweepstakes_for_breed_legacy'] loop
    definition := pg_get_functiondef(to_regprocedure('public.' || fn || '(uuid,text,text,text)'));
    if fn = 'calculate_sweepstakes_for_breed_baseline' then
      needle := 'AND coalesce(is_disqualified, false) = false';
      replacement := needle || E'\n      AND NOT public.is_cod_entry(breed_name, variety_name)';
    elsif fn = 'calculate_sweepstakes_for_breed_portal_class_schedule' then
      needle := 'and not coalesce(is_disqualified, false)';
      replacement := needle || E'\n      and not public.is_cod_entry(breed_name, variety_name)';
    else
      needle := 'and not coalesce(entry.is_disqualified, false)';
      replacement := needle || E'\n      and not public.is_cod_entry(entry.breed, entry.variety)';
    end if;
    if definition is null or strpos(definition, needle) = 0 then
      raise exception 'Expected sweepstakes eligibility filter missing in %', fn;
    end if;
    execute replace(definition, needle, replacement);
  end loop;
end;
$block$;
