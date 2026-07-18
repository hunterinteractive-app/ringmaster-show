do $block$
begin
  if to_regprocedure(
       'public.calculate_sweepstakes_for_breed_legacy(uuid,text,text,text)'
     ) is null then
    alter function public.calculate_sweepstakes_for_breed(
      uuid, text, text, text
    ) rename to calculate_sweepstakes_for_breed_legacy;
  end if;
end;
$block$;

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
begin
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

alter function public.calculate_sweepstakes_for_breed_legacy(
  uuid, text, text, text
) set search_path = '';
alter function public.calculate_sweepstakes_for_breed(
  uuid, text, text
) set search_path = '';
