-- cavy-fixed-v2 is the canonical ACBA sweepstakes calculation. A later
-- class-only migration accidentally zeroed the cavy award scale, while report
-- consumers continued to select cavy-fixed-v1 rows. Restore the v2 inputs and
-- make every calculation/report path agree on the same version.

update public.point_award_scale
set cavy_award_points = case award_code
      when 'BJV' then 10
      when 'BIV' then 10
      when 'BSV' then 10
      when 'BOV' then 25
      when 'BOSV' then 15
      when 'BJB' then 25
      when 'BIB' then 25
      when 'BSB' then 25
      when 'BOB' then 50
      when 'BOSB' then 25
      when 'BIS' then 50
      when 'RIS' then 25
      when 'BRIS' then 25
      else cavy_award_points
    end,
    updated_at = now()
where award_code in (
  'BJV', 'BIV', 'BSV', 'BOV', 'BOSV',
  'BJB', 'BIB', 'BSB', 'BOB', 'BOSB',
  'BIS', 'RIS', 'BRIS'
);

create or replace function public.calculate_cavy_sweepstakes_for_section_baseline(
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
        when 'RESERVE OF SHOW' then 'RIS'
        when '1RIS' then 'RIS'
        when '1ST RIS' then 'RIS'
        when 'FIRST RIS' then 'RIS'
        when '1ST RESERVE IN SHOW' then 'RIS'
        when 'FIRST RESERVE IN SHOW' then 'RIS'
        when '2RIS' then null
        when '2ND RIS' then null
        when 'SECOND RIS' then null
        when '2ND RESERVE IN SHOW' then null
        when 'SECOND RESERVE IN SHOW' then null
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
  where n.award_code is not null
    and coalesce(pas.cavy_award_points, 0) <> 0;

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
    'cavy-fixed-v2',
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

revoke all on function public.calculate_cavy_sweepstakes_for_section_baseline(
  uuid, text, text
) from public, anon;
grant execute on function public.calculate_cavy_sweepstakes_for_section_baseline(
  uuid, text, text
) to authenticated, service_role;

create or replace function public.calculate_cavy_sweepstakes_for_section_unlocked(
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
  v_rules jsonb;
  v_rows integer;
begin
  v_rows := public.calculate_cavy_sweepstakes_for_section_baseline(
    p_show_id,
    p_scope,
    p_show_letter
  );

  select public.get_effective_cavy_sweepstakes_portal_rule(p_show_id)
  into v_rules;

  if v_rules is null or jsonb_typeof(v_rules -> 'awards') <> 'array' then
    return v_rows;
  end if;

  update public.sweepstakes_entry_results result
  set points = award.cavy_points::numeric(10,2)
  from jsonb_to_recordset(v_rules -> 'awards')
    as award(code text, cavy_points numeric, active boolean)
  join public.entries entry
    on entry.id = result.entry_id
   and entry.species::text = 'cavy'
  where result.show_id = p_show_id
    and upper(result.scope) = upper(p_scope)
    and upper(coalesce(result.show_letter, '')) = upper(p_show_letter)
    and upper(result.points_source) = upper(award.code)
    and coalesce(award.active, true);

  update public.sweepstakes_results sr
  set variety_points = coalesce(t.variety_points, 0),
      bob_points = coalesce(t.breed_points, 0),
      bis_points = coalesce(t.show_points, 0),
      total_points = (
        coalesce(t.variety_points, 0) +
        coalesce(t.breed_points, 0) +
        coalesce(t.show_points, 0)
      )::numeric(10,2),
      rule_source = 'PORTAL_EFFECTIVE_CAVY_SCHEDULE'
  from (
    select
      result.breed_name,
      result.exhibitor_id::text as exhibitor_id,
      sum(result.points) filter (
        where result.points_source in ('BOV','BOSV','BJV','BIV','BSV')
      ) as variety_points,
      sum(result.points) filter (
        where result.points_source in ('BOB','BOSB','BJB','BIB','BSB')
      ) as breed_points,
      sum(result.points) filter (
        where result.points_source in ('BIS','RIS','BRIS')
      ) as show_points
    from public.sweepstakes_entry_results result
    where result.show_id = p_show_id
      and upper(result.scope) = upper(p_scope)
      and upper(coalesce(result.show_letter, '')) = upper(p_show_letter)
    group by result.breed_name, result.exhibitor_id
  ) t
  where sr.show_id = p_show_id
    and upper(sr.scope) = upper(p_scope)
    and upper(coalesce(sr.show_letter, '')) = upper(p_show_letter)
    and lower(sr.breed_name) = lower(t.breed_name)
    and sr.exhibitor_id = t.exhibitor_id
    and sr.calculation_version = 'cavy-fixed-v2';

  return v_rows;
end;
$function$;

revoke all on function public.calculate_cavy_sweepstakes_for_section_unlocked(
  uuid, text, text
) from public, anon;
grant execute on function public.calculate_cavy_sweepstakes_for_section_unlocked(
  uuid, text, text
) to authenticated, service_role;

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
  v_lock_key text := concat_ws(
    ':',
    'cavy-sweepstakes',
    p_show_id::text,
    upper(btrim(coalesce(p_scope, ''))),
    upper(btrim(coalesce(p_show_letter, '')))
  );
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_lock_key, 0)
  );

  return public.calculate_cavy_sweepstakes_for_section_unlocked(
    p_show_id,
    p_scope,
    p_show_letter
  );
end;
$function$;

revoke all on function public.calculate_cavy_sweepstakes_for_section(
  uuid, text, text
) from public, anon;
grant execute on function public.calculate_cavy_sweepstakes_for_section(
  uuid, text, text
) to authenticated, service_role;

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
      and (
        v_letter = 'ALL'
        or upper(coalesce(sr.show_letter, '')) = v_letter
      )
      and sr.calculation_version = 'cavy-fixed-v2'
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
  'Calculates breed sweepstakes while serializing concurrent recalculations and treating cavy-fixed-v2 as the canonical cavy result version.';

create or replace view public.v_sweepstakes_pdf_rows
with (security_invoker = true)
as
select
  sr.show_id,
  sr.breed_name,
  sr.scope,
  sr.show_letter,
  sr.exhibitor_id,
  sr.exhibitor_name,
  concat_ws(
    ', ',
    nullif(e.address_line1, ''),
    nullif(e.city, ''),
    nullif(e.state, ''),
    nullif(e.zip, '')
  ) as exhibitor_address,
  sr.class_points,
  sr.class_points as arba_class_points,
  sr.variety_points,
  sr.group_points,
  sr.bob_points,
  sr.bis_points,
  sr.fur_points,
  sr.total_points,
  sr.calculation_version,
  sr.rule_source,
  sr.verification_status,
  sr.engine_type,
  ''::text as arba_sanction_number,
  ''::text as national_club_sanction_number,
  c.name as host_club_name,
  s.location_name as show_location,
  ''::text as secretary_name,
  s.secretary_email,
  s.secretary_phone,
  row_number() over (
    partition by sr.show_id, sr.breed_name, sr.scope, sr.show_letter
    order by sr.total_points desc, sr.class_points desc, sr.exhibitor_name
  ) as rank
from public.sweepstakes_results sr
left join public.exhibitors e on e.id::text = sr.exhibitor_id
left join public.shows s on s.id = sr.show_id
left join public.clubs c on c.id = s.club_id
where sr.calculation_version in ('v2', 'cavy-fixed-v2');

revoke all on table public.v_sweepstakes_pdf_rows from public, anon;
grant select on table public.v_sweepstakes_pdf_rows to authenticated, service_role;
