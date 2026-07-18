create or replace function public.calculate_cavy_sweepstakes_for_section(
  p_show_id uuid,
  p_scope text,
  p_show_letter text
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_scope text := upper(btrim(coalesce(p_scope, '')));
  v_letter text := upper(btrim(coalesce(p_show_letter, '')));
  v_inserted integer := 0;
begin
  if v_scope not in ('OPEN', 'YOUTH') then
    raise exception 'Invalid cavy sweepstakes scope: %', p_scope;
  end if;
  if v_letter = '' then
    raise exception 'Cavy sweepstakes show letter is required';
  end if;
  delete from public.sweepstakes_results sr
  where sr.show_id = p_show_id
    and upper(sr.scope) = v_scope
    and upper(coalesce(sr.show_letter, '')) = v_letter
    and exists (
      select 1
      from public.entries e
      where e.show_id = p_show_id
        and e.species::text = 'cavy'
        and lower(e.breed) = lower(sr.breed_name)
    );

  delete from public.sweepstakes_entry_results ser
  where ser.show_id = p_show_id
    and upper(ser.scope) = v_scope
    and upper(coalesce(ser.show_letter, '')) = v_letter
    and exists (
      select 1
      from public.entries e
      where e.id = ser.entry_id
        and e.show_id = p_show_id
        and e.species::text = 'cavy'
    );

  drop table if exists pg_temp.cavy_award_points;
  create temporary table cavy_award_points on commit drop as
  with raw_awards as (
    select e.id as entry_id, upper(btrim(ea.award_code)) as raw_code
    from public.entries e
    join public.show_sections sec on sec.id = e.section_id
    join public.entry_awards ea on ea.entry_id = e.id
    where e.show_id = p_show_id
      and e.species::text = 'cavy'
      and upper(sec.kind::text) = v_scope
      and upper(sec.letter::text) = v_letter
      and coalesce(e.is_shown, true)
      and e.scratched_at is null
      and not coalesce(e.is_disqualified, false)
      and ea.award_code is not null
      and btrim(ea.award_code) <> ''
    union
    select e.id, upper(btrim(r.award))
    from public.entries e
    join public.show_sections sec on sec.id = e.section_id
    join public.results r on r.entry_id = e.id and r.show_id = e.show_id
    where e.show_id = p_show_id
      and e.species::text = 'cavy'
      and upper(sec.kind::text) = v_scope
      and upper(sec.letter::text) = v_letter
      and coalesce(e.is_shown, true)
      and e.scratched_at is null
      and not coalesce(e.is_disqualified, false)
      and r.award is not null
      and btrim(r.award) <> ''
    union
    select e.id, upper(btrim(e.special_awards))
    from public.entries e
    join public.show_sections sec on sec.id = e.section_id
    where e.show_id = p_show_id
      and e.species::text = 'cavy'
      and upper(sec.kind::text) = v_scope
      and upper(sec.letter::text) = v_letter
      and coalesce(e.is_shown, true)
      and e.scratched_at is null
      and not coalesce(e.is_disqualified, false)
      and e.special_awards is not null
      and btrim(e.special_awards) <> ''
  ), normalized as (
    select distinct
      entry_id,
      case raw_code
        when 'BOG' then 'BOV'
        when 'BEST OF GROUP' then 'BOV'
        when 'BOSG' then 'BOSV'
        when 'BEST OPPOSITE SEX OF GROUP' then 'BOSV'
        when 'BEST JUNIOR' then 'BJV'
        when 'BEST INTERMEDIATE' then 'BIV'
        when 'BEST SENIOR' then 'BSV'
        when 'BEST IN SHOW' then 'BIS'
        when 'RESERVE IN SHOW' then 'RIS'
        when 'RESERVE BEST IN SHOW' then 'RIS'
        else raw_code
      end as award_code
    from raw_awards
  )
  select
    n.entry_id,
    n.award_code,
    coalesce(pas.cavy_award_points, 0)::numeric(10,2) as points,
    case
      when n.award_code in ('BOV','BOSV','BJV','BIV','BSV') then 'variety'
      when n.award_code in ('BOB','BOSB','BJB','BIB','BSB') then 'breed'
      when n.award_code in ('BIS','RIS','BRIS') then 'show'
      else 'other'
    end as points_bucket
  from normalized n
  join public.point_award_scale pas
    on pas.award_code = n.award_code
   and pas.is_active = true
  where coalesce(pas.cavy_award_points, 0) <> 0;

  insert into public.sweepstakes_entry_results (
    show_id, exhibitor_id, entry_id, animal_id, breed_name, variety_name,
    class_name, sex, tattoo, show_letter, scope, points_source, points
  )
  select
    e.show_id,
    e.exhibitor_id,
    e.id,
    e.animal_id,
    e.breed,
    e.variety,
    e.class_name,
    e.sex,
    e.tattoo,
    v_letter,
    v_scope,
    cap.award_code,
    cap.points
  from cavy_award_points cap
  join public.entries e on e.id = cap.entry_id;

  insert into public.sweepstakes_results (
    show_id, breed_name, exhibitor_id, exhibitor_name, scope, show_letter,
    class_points, variety_points, group_points, bob_points, bis_points,
    fur_points, total_points, calculation_version, rule_source,
    verification_status, engine_type
  )
  select
    e.show_id,
    e.breed,
    e.exhibitor_id::text,
    max(coalesce(
      nullif(ex.display_name, ''),
      btrim(coalesce(ex.first_name, '') || ' ' || coalesce(ex.last_name, ''))
    )),
    v_scope,
    v_letter,
    0,
    coalesce(sum(cap.points) filter (where cap.points_bucket = 'variety'), 0),
    0,
    coalesce(sum(cap.points) filter (where cap.points_bucket = 'breed'), 0),
    coalesce(sum(cap.points) filter (where cap.points_bucket = 'show'), 0),
    0,
    sum(cap.points),
    'cavy-fixed-v1',
    'ACBA_FIXED_AWARD_SCALE',
    'VERIFIED',
    'CAVY_FIXED_AWARDS'
  from cavy_award_points cap
  join public.entries e on e.id = cap.entry_id
  left join public.exhibitors ex on ex.id = e.exhibitor_id
  group by e.show_id, e.breed, e.exhibitor_id;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

revoke all on function public.calculate_cavy_sweepstakes_for_section(
  uuid, text, text
) from public, anon;
grant execute on function public.calculate_cavy_sweepstakes_for_section(
  uuid, text, text
) to authenticated, service_role;
