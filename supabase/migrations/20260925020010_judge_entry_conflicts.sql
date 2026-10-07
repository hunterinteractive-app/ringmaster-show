-- Conflict data is visible only to staff authorized to manage this show's lineup.
create or replace function private.show_lineup_entry_conflicts(p_show_id uuid)
returns table(show_id uuid, section_id uuid, judge_id uuid, breed text,
  exhibitor_id uuid, exhibitor_name text, relationship text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not coalesce(public.user_can_manage_show_lineup(p_show_id),false) then
    raise exception 'Not authorized to check this show lineup' using errcode='42501';
  end if;
  return query
  with judge_people as (
    select j.id, j.email,
      lower(regexp_replace(coalesce(nullif(trim(j.first_name || ' ' || j.last_name),''),nullif(j.display_name,''),j.name), '[^[:alnum:]]', '', 'g')) person_name
    from public.show_judges sj join public.judges j on j.id=sj.judge_id
    where sj.show_id=p_show_id
  ), own_exhibitors as (
    select distinct j.id judge_id, x.id exhibitor_id, x.owner_user_id
    from judge_people j join public.exhibitors x on
      (nullif(lower(trim(j.email)),'')=nullif(lower(trim(x.email)),'')) or
      (nullif(j.person_name,'')=lower(regexp_replace(coalesce(nullif(trim(x.first_name || ' ' || x.last_name),''),x.display_name), '[^[:alnum:]]', '', 'g')))
  ), judge_users as (
    select o.judge_id,o.owner_user_id user_id from own_exhibitors o where o.owner_user_id is not null
    union
    select j.id,u.id from judge_people j join auth.users u on nullif(lower(trim(j.email)),'')=lower(u.email)
  ), household_owners as (
    select ju.judge_id,ju.user_id owner_id from judge_users ju
    union
    select ju.judge_id,i.owner_user_id from judge_users ju join household_private.invitations i
      on i.member_user_id=ju.user_id and i.accepted_at is not null and i.revoked_at is null
  ), related as (
    select o.judge_id,o.exhibitor_id,'Judge identity match'::text relationship from own_exhibitors o
    union
    select h.judge_id,x.id,'Shared household'::text from household_owners h join public.exhibitors x on x.owner_user_id=h.owner_id
    union
    select h.judge_id,x.id,'Shared household'::text from household_owners h
      join household_private.invitations i on i.owner_user_id=h.owner_id and i.accepted_at is not null and i.revoked_at is null
      join public.exhibitors x on x.owner_user_id=i.member_user_id
    union
    select p.judge_id,x.id,coalesce(nullif(p.relationship_label,''),'Recorded relationship')
    from public.show_judge_conflict_profiles p join public.exhibitors x on x.id=p.exhibitor_id or
      (p.exhibitor_id is null and nullif(lower(regexp_replace(p.related_name,'[^[:alnum:]]','','g')),'')=
       lower(regexp_replace(x.display_name,'[^[:alnum:]]','','g')))
    where p.user_id=auth.uid() or exists(select 1 from public.role_assignments ra where ra.user_id=p.user_id and ra.show_id=p_show_id and ra.role in ('admin','superintendent'))
  )
  select distinct e.show_id,e.section_id,r.judge_id,e.breed,x.id,
    coalesce(nullif(x.showing_name,''),x.display_name),r.relationship
  from public.entries e join public.exhibitors x on x.id=e.exhibitor_id
  join related r on r.exhibitor_id=x.id
  where e.show_id=p_show_id and e.scratched_at is null
    and lower(coalesce(e.status,'')) not in ('scratched','cancelled','canceled','deleted');
end $$;
revoke all on function private.show_lineup_entry_conflicts(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.show_lineup_entry_conflicts(uuid) to authenticated;
create or replace function public.get_show_lineup_entry_conflicts(p_show_id uuid)
returns table(show_id uuid, section_id uuid, judge_id uuid, breed text,
  exhibitor_id uuid, exhibitor_name text, relationship text)
language sql stable security invoker set search_path = '' as $$
  select * from private.show_lineup_entry_conflicts(p_show_id);
$$;
revoke all on function public.get_show_lineup_entry_conflicts(uuid) from public,anon;
grant execute on function public.get_show_lineup_entry_conflicts(uuid) to authenticated;
create or replace function public.validate_show_judge_breed_conflict(p_show_id uuid,p_section_id uuid,p_judge_id uuid,p_breed text)
returns table(exhibitor_name text,relationship text)
language sql stable security invoker set search_path = '' as $$
 select distinct c.exhibitor_name,c.relationship from private.show_lineup_entry_conflicts(p_show_id) c
 where c.judge_id=p_judge_id and (p_section_id is null or c.section_id=p_section_id)
 and lower(trim(c.breed))=lower(trim(p_breed));
$$;
revoke all on function public.validate_show_judge_breed_conflict(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.validate_show_judge_breed_conflict(uuid,uuid,uuid,text) to authenticated;
