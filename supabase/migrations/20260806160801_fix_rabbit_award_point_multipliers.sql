-- Rabbit sweepstakes award values are multipliers, not flat point amounts.
-- Fur/Wool is a separate class and is intentionally excluded from regular
-- Best of Breed, Best Opposite Sex of Breed, and Best in Show counts.
create or replace function public.calculate_sweepstakes_for_breed_legacy(
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
  v_rules jsonb;
  v_is_completed boolean := false;
  v_has_saved_results boolean := false;
begin
  select coalesce(show.is_closed, false) or show.finalized_at is not null
    into v_is_completed
  from public.shows show
  where show.id = p_show_id;

  select exists (
    select 1 from public.sweepstakes_results result
    where result.show_id = p_show_id
      and result.breed_name = p_breed_name
      and upper(result.scope) = upper(p_scope)
      and upper(coalesce(result.show_letter, 'ALL')) = v_letter
  ) into v_has_saved_results;

  if v_is_completed and v_has_saved_results then
    return query
    select result.* from public.sweepstakes_results result
    where result.show_id = p_show_id
      and result.breed_name = p_breed_name
      and upper(result.scope) = upper(p_scope)
      and upper(coalesce(result.show_letter, 'ALL')) = v_letter
    order by result.total_points desc, result.exhibitor_name;
    return;
  end if;

  perform public.calculate_sweepstakes_for_breed_portal_class_schedule(
    p_show_id, p_breed_name, p_scope, p_show_letter
  );

  select public.get_effective_rabbit_sweepstakes_portal_rule(p_show_id, p_breed_name)
    into v_rules;

  if v_rules is null or jsonb_typeof(v_rules -> 'awards') <> 'array' then
    return query
    select result.* from public.sweepstakes_results result
    where result.show_id = p_show_id
      and result.breed_name = p_breed_name
      and upper(result.scope) = upper(p_scope)
      and upper(coalesce(result.show_letter, 'ALL')) = v_letter
    order by result.total_points desc, result.exhibitor_name;
    return;
  end if;

  delete from public.sweepstakes_entry_results entry_result
  where entry_result.show_id = p_show_id
    and entry_result.breed_name = p_breed_name
    and upper(entry_result.scope) = upper(p_scope)
    and upper(coalesce(entry_result.show_letter, 'ALL')) = v_letter
    and entry_result.points_source not in ('CLASS', 'FUR');

  insert into public.sweepstakes_entry_results (
    show_id, exhibitor_id, entry_id, animal_id, breed_name, variety_name,
    class_name, sex, tattoo, show_letter, scope, points_source, points
  )
  with configured_awards as (
    select upper(btrim(award.code)) as award_code, award.rabbit_points::numeric as points
    from jsonb_to_recordset(v_rules -> 'awards')
      as award(code text, rabbit_points numeric, active boolean)
    where coalesce(award.active, true)
      and coalesce(award.rabbit_points, 0) <> 0
  ), section_entries as (
    select
      entry.id as entry_id, entry.show_id, entry.exhibitor_id, entry.animal_id,
      entry.breed, entry.variety, entry.class_name, entry.sex, entry.tattoo,
      section.letter::text as show_letter
    from public.entries entry
    join public.show_sections section on section.id = entry.section_id
    where entry.show_id = p_show_id
      and coalesce(entry.species::text, 'rabbit') = 'rabbit'
      and upper(section.kind::text) = upper(p_scope)
      and upper(section.letter::text) = v_letter
      and not coalesce(entry.is_fur, false)
      and coalesce(entry.is_shown, true)
      and entry.scratched_at is null
      and not coalesce(entry.is_disqualified, false)
  ), scoped_entries as (
    select *
    from section_entries
    where lower(breed) = lower(p_breed_name)
  ), raw_awards as (
    select scoped.entry_id, upper(btrim(award.award_code)) as raw_code
    from scoped_entries scoped join public.entry_awards award on award.entry_id = scoped.entry_id
    where nullif(btrim(award.award_code), '') is not null
    union
    select scoped.entry_id, upper(btrim(result.award))
    from scoped_entries scoped join public.results result
      on result.entry_id = scoped.entry_id and result.show_id = scoped.show_id
    where nullif(btrim(result.award), '') is not null
    union
    select scoped.entry_id, upper(btrim(entry.special_awards))
    from scoped_entries scoped join public.entries entry on entry.id = scoped.entry_id
    where nullif(btrim(entry.special_awards), '') is not null
  ), normalized_awards as (
    select distinct entry_id,
      case raw_code
        when 'BEST IN SHOW' then 'BIS'
        when 'RESERVE IN SHOW' then 'RIS'
        when 'RESERVE BEST IN SHOW' then 'RIS'
        when 'BEST 4-CLASS' then 'B4C'
        when 'BEST 6-CLASS' then 'B6C'
        when 'BEST OF BREED' then 'BOB'
        when 'BEST OPPOSITE SEX OF BREED' then 'BOSB'
        when 'BEST OPPOSITE BREED' then 'BOSB'
        else raw_code
      end as award_code
    from raw_awards
  ), award_counts as (
    select
      scoped.entry_id,
      count(*) filter (
        where lower(section_entry.breed) = lower(scoped.breed)
      )::numeric as breed_entry_count,
      count(*) filter (
        where lower(section_entry.breed) = lower(scoped.breed)
          and lower(coalesce(section_entry.sex, '')) = lower(coalesce(scoped.sex, ''))
      )::numeric as breed_sex_entry_count,
      count(*)::numeric as show_entry_count
    from scoped_entries scoped
    cross join section_entries section_entry
    group by scoped.entry_id
  )
  select
    scoped.show_id, scoped.exhibitor_id, scoped.entry_id, scoped.animal_id,
    scoped.breed, scoped.variety, scoped.class_name, scoped.sex, scoped.tattoo,
    scoped.show_letter, upper(p_scope), award.award_code,
    (
      award.points * case award.award_code
        when 'BOB' then counts.breed_entry_count
        when 'BOS' then counts.breed_sex_entry_count
        when 'BOSB' then counts.breed_sex_entry_count
        when 'BIS' then counts.show_entry_count
        else 1
      end
    )::numeric(10,2)
  from normalized_awards normalized
  join configured_awards award on award.award_code = normalized.award_code
  join scoped_entries scoped on scoped.entry_id = normalized.entry_id
  join award_counts counts on counts.entry_id = scoped.entry_id;

  update public.sweepstakes_results result
  set
    variety_points = coalesce(totals.variety_points, 0),
    group_points = coalesce(totals.group_points, 0),
    bob_points = coalesce(totals.bob_points, 0),
    bis_points = coalesce(totals.bis_points, 0),
    total_points = (
      coalesce(result.class_points, 0) + coalesce(result.fur_points, 0)
      + coalesce(totals.variety_points, 0) + coalesce(totals.group_points, 0)
      + coalesce(totals.bob_points, 0) + coalesce(totals.bis_points, 0)
    )::numeric(10,2),
    rule_source = 'PORTAL_EFFECTIVE_SCHEDULE'
  from (
    select
      entry_result.exhibitor_id::text as exhibitor_id,
      sum(entry_result.points) filter (where entry_result.points_source in ('BOV','BOSV','BJV','BIV','BSV'))::numeric(10,2) as variety_points,
      sum(entry_result.points) filter (where entry_result.points_source in ('BOG','BOSG'))::numeric(10,2) as group_points,
      sum(entry_result.points) filter (where entry_result.points_source in ('BOB','BOS','BOSB','BJB','BIB','BSB'))::numeric(10,2) as bob_points,
      sum(entry_result.points) filter (where entry_result.points_source in ('B4C','B6C','BIS','RIS','BRIS'))::numeric(10,2) as bis_points
    from public.sweepstakes_entry_results entry_result
    where entry_result.show_id = p_show_id
      and entry_result.breed_name = p_breed_name
      and upper(entry_result.scope) = upper(p_scope)
      and upper(coalesce(entry_result.show_letter, 'ALL')) = v_letter
      and entry_result.points_source not in ('CLASS', 'FUR')
    group by entry_result.exhibitor_id
  ) totals
  where result.show_id = p_show_id
    and result.breed_name = p_breed_name
    and upper(result.scope) = upper(p_scope)
    and upper(coalesce(result.show_letter, 'ALL')) = v_letter
    and result.exhibitor_id = totals.exhibitor_id;

  update public.sweepstakes_results result
  set variety_points = 0, group_points = 0, bob_points = 0, bis_points = 0,
      total_points = (coalesce(result.class_points, 0) + coalesce(result.fur_points, 0))::numeric(10,2),
      rule_source = 'PORTAL_EFFECTIVE_SCHEDULE'
  where result.show_id = p_show_id
    and result.breed_name = p_breed_name
    and upper(result.scope) = upper(p_scope)
    and upper(coalesce(result.show_letter, 'ALL')) = v_letter
    and not exists (
      select 1 from public.sweepstakes_entry_results entry_result
      where entry_result.show_id = result.show_id
        and entry_result.breed_name = result.breed_name
        and upper(entry_result.scope) = upper(result.scope)
        and upper(coalesce(entry_result.show_letter, 'ALL')) = upper(coalesce(result.show_letter, 'ALL'))
        and entry_result.exhibitor_id::text = result.exhibitor_id
        and entry_result.points_source not in ('CLASS', 'FUR')
    );

  return query
  select result.* from public.sweepstakes_results result
  where result.show_id = p_show_id
    and result.breed_name = p_breed_name
    and upper(result.scope) = upper(p_scope)
    and upper(coalesce(result.show_letter, 'ALL')) = v_letter
  order by result.total_points desc, result.exhibitor_name;
end;
$function$;

revoke all on function public.calculate_sweepstakes_for_breed_legacy(uuid, text, text, text) from public, anon;
grant execute on function public.calculate_sweepstakes_for_breed_legacy(uuid, text, text, text)
  to authenticated, service_role;
