-- Older Fur/Wool results used `placement` while newer entries use
-- `fur_placement`.  Treat either field as the Fur/Wool placing so legacy
-- reports remain eligible and score consistently with newly-entered results.
do $migration$
declare
  v_definition text;
  v_original text := $needle$
    when coalesce(e.is_fur, false) = true then
      (
        e.fur_placement is not null
        and e.fur_placement > 0
      )
$needle$;
  v_replacement text := $replacement$
    when coalesce(e.is_fur, false) = true then
      (
        coalesce(
          e.fur_placement,
          case
            when e.placement ~ '^[0-9]+$' then e.placement::integer
          end
        ) is not null
        and coalesce(
          e.fur_placement,
          case
            when e.placement ~ '^[0-9]+$' then e.placement::integer
          end
        ) > 0
      )
$replacement$;
begin
  select pg_get_functiondef(
    'public.report_results_entry_rows(uuid,uuid,text)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'report_results_entry_rows(uuid, uuid, text) is missing';
  end if;

  if position(v_replacement in v_definition) > 0 then
    return;
  end if;

  if position(v_original in v_definition) = 0 then
    raise exception
      'Unable to repair legacy Fur/Wool report eligibility; expected source shape was not found';
  end if;

  execute replace(v_definition, v_original, v_replacement);
end;
$migration$;
