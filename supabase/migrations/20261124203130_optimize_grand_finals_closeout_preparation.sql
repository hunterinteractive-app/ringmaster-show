-- Calculate each cavy section only once while retaining all scoring rules.
CREATE OR REPLACE FUNCTION public.calculate_sweepstakes_for_show(p_show_id uuid, p_scope text, p_show_letter text DEFAULT NULL::text)
 RETURNS SETOF sweepstakes_results
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$declare
  v_breed record;
  v_cavy_calculated boolean := false;
  v_letter text := upper(coalesce(nullif(btrim(p_show_letter), ''), 'ALL'));
begin
  if upper(coalesce(p_scope, '')) not in ('OPEN', 'YOUTH') then
    raise exception 'Invalid scope: %. Expected OPEN or YOUTH.', p_scope;
  end if;

  delete from public.sweepstakes_results sr
  where sr.show_id = p_show_id
    and upper(sr.scope) = upper(p_scope)
    and upper(coalesce(sr.show_letter, 'ALL')) = v_letter
    and sr.calculation_version = 'v2';

  for v_breed in

    -- specific letter path
    select distinct rer.breed_name
    from public.show_sections s
    cross join lateral public.report_results_entry_rows(
      p_show_id,
      s.id,
      null
    ) rer
    where s.show_id = p_show_id
      and upper(s.kind::text) = upper(p_scope)
      and p_show_letter is not null
      and btrim(p_show_letter) <> ''
      and rer.breed_name is not null
      and btrim(rer.breed_name) <> ''
      and upper(coalesce(s.letter::text, '')) = upper(p_show_letter)

    union

    -- all letters path
    select distinct rer.breed_name
    from public.show_sections s
    cross join lateral public.report_results_entry_rows(
      p_show_id,
      s.id,
      null
    ) rer
    where s.show_id = p_show_id
      and upper(s.kind::text) = upper(p_scope)
      and (p_show_letter is null or btrim(p_show_letter) = '')
      and rer.breed_name is not null
      and btrim(rer.breed_name) <> ''

    order by 1

  loop
    -- The cavy dispatcher calculates every breed in the selected section(s).
    -- Calling it again for another cavy breed repeats the same delete/rebuild.
    if exists (
      select 1 from public.entries e
      where e.show_id = p_show_id and e.species::text = 'cavy'
        and lower(e.breed) = lower(v_breed.breed_name)
    ) then
      if v_cavy_calculated then
        continue;
      end if;
      v_cavy_calculated := true;
    end if;
    perform public.calculate_sweepstakes_for_breed(
      p_show_id,
      v_breed.breed_name,
      upper(p_scope),
      p_show_letter
    );
  end loop;

  return query
  select sr.*
  from public.sweepstakes_results sr
  where sr.show_id = p_show_id
    and upper(sr.scope) = upper(p_scope)
    and upper(coalesce(sr.show_letter, 'ALL')) = v_letter
    and sr.calculation_version = 'v2'
  order by sr.breed_name asc, sr.total_points desc, sr.exhibitor_name asc;
end;$function$;

-- Point recalculation reads and replaces rows by show and breed.
create index if not exists sweepstakes_entry_results_show_breed_scope_idx
  on public.sweepstakes_entry_results(show_id,breed_name,scope,show_letter);

notify pgrst, 'reload schema';
