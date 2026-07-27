-- Keep shared report rows aligned with closeout eligibility.  A scratched
-- entry can retain its historical placement and `is_shown` value, but it must
-- never contribute to sweepstakes totals or report class counts.
do $migration$
declare
  v_definition text;
  v_original text := $needle$
  end as result_status,

  case
    when coalesce(e.is_fur, false) = true then
$needle$;
  v_replacement text := $replacement$
  end as result_status,

  case
    when e.scratched_at is not null then false
    when coalesce(e.is_fur, false) = true then
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
      'Unable to add scratched-entry eligibility to report_results_entry_rows; expected source shape was not found';
  end if;

  execute replace(v_definition, v_original, v_replacement);
end;
$migration$;
