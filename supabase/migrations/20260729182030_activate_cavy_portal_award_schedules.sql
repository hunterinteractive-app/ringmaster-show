-- ACBA sanctions use the umbrella breed name "Cavy". A schedule therefore
-- applies to every cavy breed in that sanctioned show.
create function public.get_effective_cavy_sweepstakes_portal_rule(p_show_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with context as (select id, start_date, coalesce(is_national_show,false) national from public.shows where id=p_show_id)
  select schedule.rules from context
  join public.show_sanctions sanction on sanction.show_id=context.id
  join public.sweepstakes_portal_clubs club on club.normalized_name=lower(btrim(sanction.club_name))
  join public.sweepstakes_point_schedules schedule on schedule.portal_club_id=club.id and schedule.effective_on<=context.start_date
  where lower(btrim(sanction.breed_name))='cavy'
    and schedule.rules->>'points_mode'='cavy_awards'
    and coalesce(schedule.rules->>'show_type','regular')=case when context.national then 'national' else 'regular' end
  order by schedule.effective_on desc, schedule.created_at desc limit 1;
$$;
revoke all on function public.get_effective_cavy_sweepstakes_portal_rule(uuid) from public;
grant execute on function public.get_effective_cavy_sweepstakes_portal_rule(uuid) to authenticated, service_role;

alter function public.calculate_cavy_sweepstakes_for_section_unlocked(uuid,text,text) rename to calculate_cavy_sweepstakes_for_section_baseline;
create function public.calculate_cavy_sweepstakes_for_section_unlocked(p_show_id uuid,p_scope text,p_show_letter text)
returns integer language plpgsql security invoker set search_path='' as $function$
declare v_rules jsonb; v_rows integer; begin
  v_rows:=public.calculate_cavy_sweepstakes_for_section_baseline(p_show_id,p_scope,p_show_letter);
  select public.get_effective_cavy_sweepstakes_portal_rule(p_show_id) into v_rules;
  if v_rules is null or jsonb_typeof(v_rules->'awards')<>'array' then return v_rows; end if;
  update public.sweepstakes_entry_results result set points=award.cavy_points::numeric(10,2)
  from jsonb_to_recordset(v_rules->'awards') as award(code text,cavy_points numeric,active boolean)
  join public.entries entry on entry.id=result.entry_id and entry.species::text='cavy'
  where result.show_id=p_show_id and upper(result.scope)=upper(p_scope)
    and upper(coalesce(result.show_letter,''))=upper(p_show_letter)
    and upper(result.points_source)=upper(award.code) and coalesce(award.active,true);
  update public.sweepstakes_results sr set
    variety_points=coalesce(t.variety_points,0), bob_points=coalesce(t.breed_points,0), bis_points=coalesce(t.show_points,0),
    total_points=(coalesce(t.variety_points,0)+coalesce(t.breed_points,0)+coalesce(t.show_points,0))::numeric(10,2),
    rule_source='PORTAL_EFFECTIVE_CAVY_SCHEDULE'
  from (select result.breed_name,result.exhibitor_id::text exhibitor_id,
      sum(result.points) filter(where result.points_source in('BOV','BOSV','BJV','BIV','BSV')) variety_points,
      sum(result.points) filter(where result.points_source in('BOB','BOSB','BJB','BIB','BSB')) breed_points,
      sum(result.points) filter(where result.points_source in('BIS','RIS','BRIS')) show_points
    from public.sweepstakes_entry_results result where result.show_id=p_show_id and upper(result.scope)=upper(p_scope)
      and upper(coalesce(result.show_letter,''))=upper(p_show_letter) group by result.breed_name,result.exhibitor_id) t
  where sr.show_id=p_show_id and upper(sr.scope)=upper(p_scope) and upper(coalesce(sr.show_letter,''))=upper(p_show_letter)
    and lower(sr.breed_name)=lower(t.breed_name) and sr.exhibitor_id=t.exhibitor_id;
  return v_rows;
end;$function$;
revoke all on function public.calculate_cavy_sweepstakes_for_section_unlocked(uuid,text,text) from public,anon;
grant execute on function public.calculate_cavy_sweepstakes_for_section_unlocked(uuid,text,text) to authenticated,service_role;
