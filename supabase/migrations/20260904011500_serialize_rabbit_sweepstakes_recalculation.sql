create or replace function public.calculate_sweepstakes_for_breed(
  p_show_id uuid,
  p_breed_name text,
  p_scope text,
  p_show_letter text default null
)
returns setof public.sweepstakes_results
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_letter text := upper(coalesce(nullif(btrim(p_show_letter), ''), 'ALL'));
  v_is_cavy boolean;
  v_lock_key text := concat_ws(
    ':',
    'sweepstakes',
    p_show_id::text,
    lower(btrim(coalesce(p_breed_name, ''))),
    upper(btrim(coalesce(p_scope, ''))),
    v_letter
  );
begin
  -- A sweepstakes report and its matching breed-detail report can be rendered
  -- concurrently. Both recalculate the same persisted rows, so serialize that
  -- work by show, breed, scope, and letter to prevent delete/insert races.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_lock_key, 0)
  );

  select exists (
    select 1
    from public.entries e
    where e.show_id = p_show_id
      and e.species::text = 'cavy'
      and lower(e.breed) = lower(p_breed_name)
  ) into v_is_cavy;

  if v_is_cavy then
    if v_letter = 'ALL' then
      perform public.calculate_cavy_sweepstakes_for_section(
        p_show_id,
        p_scope,
        sec.letter::text
      )
      from public.show_sections sec
      where sec.show_id = p_show_id
        and upper(sec.kind::text) = upper(p_scope)
        and sec.is_enabled = true;
    else
      perform public.calculate_cavy_sweepstakes_for_section(
        p_show_id,
        p_scope,
        v_letter
      );
    end if;

    return query
    select sr.*
    from public.sweepstakes_results sr
    where sr.show_id = p_show_id
      and lower(sr.breed_name) = lower(p_breed_name)
      and upper(sr.scope) = upper(p_scope)
      and upper(coalesce(sr.show_letter, 'ALL')) = v_letter
      and sr.calculation_version = 'cavy-fixed-v1'
    order by sr.total_points desc, sr.exhibitor_name;
    return;
  end if;

  return query
  select legacy.*
  from public.calculate_sweepstakes_for_breed_legacy(
    p_show_id,
    p_breed_name,
    p_scope,
    p_show_letter
  ) legacy;
end;
$function$;

revoke all on function public.calculate_sweepstakes_for_breed(
  uuid, text, text, text
) from public, anon;
grant execute on function public.calculate_sweepstakes_for_breed(
  uuid, text, text, text
) to authenticated, service_role;

comment on function public.calculate_sweepstakes_for_breed(
  uuid, text, text, text
) is
  'Calculates breed sweepstakes while serializing concurrent recalculations for the same show, breed, scope, and show letter.';
