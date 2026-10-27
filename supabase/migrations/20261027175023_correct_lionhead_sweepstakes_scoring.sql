-- NALRC rules supplied by the club, with the secretary's confirmed exclusions:
-- Open/Youth and each show section stay separate; scratched, unshown, DQ,
-- COD, cavy, and fur entries do not contribute to any population or points.
alter table public.shows
  add column if not exists is_arba_convention boolean not null default false;

comment on column public.shows.is_arba_convention is
  'Distinguishes ARBA Convention from a breed national show. Uses the selected national_show_section_id, or all sections for legacy national events without a selection.';

create or replace function public.lionhead_sweepstakes_points(
  p_event_type text,
  p_source text,
  p_placement integer,
  p_class_count numeric,
  p_breed_count numeric,
  p_show_count numeric,
  p_is_specialty boolean
)
returns numeric
language sql immutable security invoker set search_path = ''
as $$
  select case upper(p_source)
    when 'CLASS' then
      case when p_event_type in ('convention', 'national') then
        case when p_placement between 1 and 10 then (11 - p_placement) * p_class_count else 0 end
      else
        coalesce((array[6,4,3,2,1])[p_placement], 0) * p_class_count
      end
    when 'BOB' then 2 * p_breed_count
    when 'BOSB' then p_breed_count
    when 'BIS' then
      case when p_event_type = 'national' or p_is_specialty then 0
           when p_event_type = 'convention' then least(p_show_count, 3000)
           else least(p_show_count, 1500) end
    when 'RIS' then case when p_event_type = 'regular' then 0.5 * p_show_count else 0 end
    when 'B4C' then case when p_event_type = 'regular' then 2 * p_breed_count else 0 end
    else 0
  end::numeric(10,2);
$$;

create or replace function public.calculate_lionhead_sweepstakes(
  p_show_id uuid,
  p_scope text,
  p_show_letter text default null
)
returns setof public.sweepstakes_results
language plpgsql security invoker set search_path = ''
as $function$
declare
  v_scope text := upper(btrim(coalesce(p_scope, '')));
  v_letter text := upper(coalesce(nullif(btrim(p_show_letter), ''), 'ALL'));
  v_completed boolean;
  v_section record;
begin
  if v_scope not in ('OPEN', 'YOUTH') then
    raise exception 'Invalid scope: %. Expected OPEN or YOUTH.', p_scope;
  end if;

  -- Match the existing serialization even when this helper is invoked directly.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    concat_ws(':', 'sweepstakes', p_show_id::text, 'lionhead', v_scope, v_letter), 0
  ));

  select coalesce(s.is_closed, false) or s.finalized_at is not null
    into v_completed from public.shows s where s.id = p_show_id;

  if v_completed and exists (
    select 1 from public.sweepstakes_results r
    where r.show_id = p_show_id and r.breed_name = 'Lionhead'
      and r.scope = v_scope
      and (v_letter = 'ALL' or upper(coalesce(r.show_letter, 'ALL')) = v_letter)
  ) then
    return query select r.* from public.sweepstakes_results r
    where r.show_id = p_show_id and r.breed_name = 'Lionhead'
      and r.scope = v_scope
      and (v_letter = 'ALL' or upper(coalesce(r.show_letter, 'ALL')) = v_letter)
    order by r.total_points desc, r.exhibitor_name;
    return;
  end if;

  if v_letter = 'ALL' then
    -- Calculate separately so counts, caps, and national rules never bleed
    -- between sections. The report loader also requests individual letters.
    for v_section in
      select distinct upper(s.letter) as letter from public.show_sections s
      where s.show_id = p_show_id and upper(s.kind::text) = v_scope and s.is_enabled
      order by 1
    loop
      perform public.calculate_lionhead_sweepstakes(p_show_id, v_scope, v_section.letter);
    end loop;
    return query select r.* from public.sweepstakes_results r
    where r.show_id = p_show_id and r.breed_name = 'Lionhead'
      and r.scope = v_scope and r.show_letter <> 'ALL' and r.calculation_version = 'v2'
    order by r.total_points desc, r.exhibitor_name;
    return;
  end if;

  delete from public.sweepstakes_entry_results r
  where r.show_id = p_show_id and r.breed_name = 'Lionhead'
    and upper(r.scope) = v_scope and upper(r.show_letter) = v_letter;

  delete from public.sweepstakes_results r
  where r.show_id = p_show_id and r.breed_name = 'Lionhead'
    and upper(r.scope) = v_scope and upper(r.show_letter) = v_letter
    and r.calculation_version = 'v2';

  insert into public.sweepstakes_entry_results (
    show_id, exhibitor_id, entry_id, animal_id, breed_name, variety_name,
    class_name, sex, tattoo, show_letter, scope, points_source, points
  )
  with section_context as (
    select s.id, s.letter,
      case when sh.is_national_show
                  and (sh.national_show_section_id is null or sh.national_show_section_id = s.id)
           then case when sh.is_arba_convention then 'convention' else 'national' end
           else 'regular' end as event_type,
      (coalesce((to_jsonb(sh) ->> 'is_single_breed_show')::boolean, false)
       or coalesce(s.breed_scope, 'all') not in ('all', 'all_breed')) as is_specialty
    from public.show_sections s join public.shows sh on sh.id = s.show_id
    where s.show_id = p_show_id and upper(s.kind::text) = v_scope
      and upper(s.letter) = v_letter and s.is_enabled
  ), eligible as materialized (
    select e.*, ctx.event_type, ctx.is_specialty,
      count(*) over (partition by e.section_id)::numeric as show_count,
      count(*) over (partition by e.section_id, lower(btrim(e.breed)))::numeric as breed_count,
      count(*) over (partition by e.section_id, lower(btrim(e.breed)), e.variety, e.sex, e.class_name)::numeric as class_count
    from public.entries e join section_context ctx on ctx.id = e.section_id
    where e.show_id = p_show_id and coalesce(e.species::text, 'rabbit') = 'rabbit'
      and not coalesce(e.is_fur, false) and coalesce(e.is_shown, true)
      and e.scratched_at is null and not coalesce(e.is_disqualified, false)
      and not public.is_cod_entry(e.breed, e.variety)
  ), lionheads as (
    select e.*, case when btrim(coalesce(e.placement::text, '')) ~ '^[0-9]{1,2}$'
                     then btrim(e.placement::text)::integer end as place_num
    from eligible e where lower(btrim(e.breed)) = 'lionhead'
  ), raw_awards as (
    select e.id as entry_id, upper(btrim(a.award_code)) as code
    from lionheads e join public.entry_awards a on a.entry_id = e.id
    union
    select e.id, upper(btrim(r.award)) from lionheads e
    join public.results r on r.entry_id = e.id and r.show_id = p_show_id
    union
    select e.id, upper(btrim(e.special_awards)) from lionheads e
  ), normalized_awards as (
    select distinct entry_id,
      case code
        when 'BEST IN SHOW' then 'BIS'
        when 'RESERVE IN SHOW' then 'RIS'
        when 'RESERVE BEST IN SHOW' then 'RIS'
        when 'BRIS' then 'RIS'
        when 'RBIS' then 'RIS'
        when '1RIS' then 'RIS'
        when 'BEST 4-CLASS' then 'B4C'
        when 'BEST 4 CLASS' then 'B4C'
        when 'BEST OF BREED' then 'BOB'
        when 'BOS' then 'BOSB'
        when 'BEST OPPOSITE SEX OF BREED' then 'BOSB'
        when 'BEST OPPOSITE BREED' then 'BOSB'
        else code
      end as code
    from raw_awards
  ), sources as (
    select e.id as entry_id, 'CLASS'::text as code from lionheads e
    union all
    select a.entry_id, a.code from normalized_awards a
    where a.code in ('BOB','BOSB','BIS','RIS','B4C')
  )
  select p_show_id, e.exhibitor_id::text, e.id, e.animal_id, 'Lionhead', e.variety,
    e.class_name, e.sex, e.tattoo, v_letter, v_scope, src.code, scored.points
  from lionheads e join sources src on src.entry_id = e.id
  cross join lateral (select public.lionhead_sweepstakes_points(
    e.event_type, src.code, e.place_num, e.class_count, e.breed_count,
    e.show_count, e.is_specialty
  ) as points) scored
  where scored.points > 0;

  insert into public.sweepstakes_results (
    show_id, breed_name, exhibitor_id, exhibitor_name, scope, show_letter,
    class_points, variety_points, group_points, bob_points, bis_points,
    fur_points, total_points, calculation_version, rule_source,
    verification_status, engine_type
  )
  select p_show_id, 'Lionhead', r.exhibitor_id,
    coalesce(nullif(ex.display_name, ''), nullif(ex.showing_name, ''),
             nullif(btrim(concat_ws(' ', ex.first_name, ex.last_name)), ''), ''),
    v_scope, v_letter,
    coalesce(sum(r.points) filter (where r.points_source = 'CLASS'), 0), 0, 0,
    coalesce(sum(r.points) filter (where r.points_source in ('BOB','BOSB')), 0),
    coalesce(sum(r.points) filter (where r.points_source in ('BIS','RIS','B4C')), 0),
    0, sum(r.points), 'v2', 'VERIFIED', 'VERIFIED', 'ADDITIVE_STANDARD'
  from public.sweepstakes_entry_results r
  left join public.exhibitors ex on ex.id::text = r.exhibitor_id
  where r.show_id = p_show_id and r.breed_name = 'Lionhead'
    and r.scope = v_scope and r.show_letter = v_letter
  group by r.exhibitor_id, ex.display_name, ex.showing_name, ex.first_name, ex.last_name;

  return query select r.* from public.sweepstakes_results r
  where r.show_id = p_show_id and r.breed_name = 'Lionhead'
    and r.scope = v_scope and r.show_letter = v_letter and r.calculation_version = 'v2'
  order by r.total_points desc, r.exhibitor_name;
end;
$function$;

revoke all on function public.lionhead_sweepstakes_points(text,text,integer,numeric,numeric,numeric,boolean) from public, anon;
revoke all on function public.calculate_lionhead_sweepstakes(uuid,text,text) from public, anon;
grant execute on function public.lionhead_sweepstakes_points(text,text,integer,numeric,numeric,numeric,boolean) to authenticated, service_role;
grant execute on function public.calculate_lionhead_sweepstakes(uuid,text,text) to authenticated, service_role;

-- Keep every existing rabbit/cavy route and locking behavior intact.
do $block$
declare
  definition text := pg_get_functiondef(to_regprocedure('public.calculate_sweepstakes_for_breed(uuid,text,text,text)'));
  needle text := '  return query' || E'\n  select legacy.*';
begin
  if position('public.calculate_lionhead_sweepstakes' in definition) > 0 then return; end if;
  if definition is null or position(needle in definition) = 0 then
    raise exception 'Expected rabbit sweepstakes dispatcher missing';
  end if;
  execute replace(definition, needle,
    E'  if lower(btrim(p_breed_name)) = ''lionhead'' then\n    return query select * from public.calculate_lionhead_sweepstakes(p_show_id, p_scope, p_show_letter);\n    return;\n  end if;\n\n' || needle);
end;
$block$;

update public.breed_rules_matrix
set bob_points = 2, bosb_points = 1, bob_basis = 'BREED_COUNT', bos_basis = 'BREED_COUNT',
    uses_bis_points = true, uses_ris_points = true, uses_best4class_points = true,
    bis_points = 1500, bis_basis = 'SHOW_COUNT_CAPPED', bris_points = 0.5, ris_basis = 'SHOW_COUNT',
    best4class_points = 2, convention_override = true, national_override = true,
    rule_source = 'NALRC rules supplied by club; population exclusions confirmed by secretary',
    verification_status = 'club_supplied', status = 'active',
    notes = 'Standard: class 6/4/3/2/1 x class count; BOB 2x breed; BOS 1x breed; BIS min(show count,1500), none at specialties; RIS 0.5x show; B4C 2x breed. Dedicated NALRC calculator applies the award bases and exclusions.',
    national_notes = 'NALRC National: class 10/9/8/7/6/5/4/3/2/1 x class count; BOB 2x breed; BOS 1x breed; BIS/RIS/B4C zero. Club determines membership in good standing.',
    convention_notes = 'ARBA Convention: national class scale through tenth; BOB 2x breed; BOS 1x breed; BIS min(show count,3000); RIS/B4C zero. Club determines membership in good standing.',
    updated_at = now()
where breed_name = 'Lionhead';

update public.breed_rules_profiles
set rule_source = 'VERIFIED', verification_status = 'VERIFIED',
    uses_bis_points = true, uses_fur_wool = false,
    notes = 'NALRC standard, Convention, and breed National rules supplied by club. Open/Youth and sections separate; exclude scratches, no-shows, DQ, COD, and fur. Membership eligibility remains with the club.',
    updated_at = now()
where breed_name = 'Lionhead';
