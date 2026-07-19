do $migration$
declare
  v_updated integer := 0;
begin
  update public.entries e
  set variety = case lower(btrim(e.variety))
      when 'black' then 'Self'
      when 'any other marked' then 'Marked'
      when 'broken color & tortoise shell' then 'Marked'
      else e.variety
    end
  where e.show_id = '0ebe76dd-7c19-4354-b605-dbb3fe964349'::uuid
    and e.species::text = 'cavy'
    and lower(btrim(e.breed)) = 'american satin'
    and lower(btrim(e.variety)) in (
      'black',
      'any other marked',
      'broken color & tortoise shell'
    );

  get diagnostics v_updated = row_count;

  -- Variety changes alter result grouping and every derived report. This
  -- direct correction does not pass through the result-field dirty trigger,
  -- so invalidate derived closeout state once when rows actually changed.
  if v_updated > 0 then
    perform public.bump_show_results_version(
      '0ebe76dd-7c19-4354-b605-dbb3fe964349'::uuid
    );
  end if;
end;
$migration$;

-- Deliberately preserve both historical BOV selections. Once the entries are
-- consolidated under Marked, cavy result validation surfaces duplicate_bov so
-- the superintendent can choose the judge's intended winner.
