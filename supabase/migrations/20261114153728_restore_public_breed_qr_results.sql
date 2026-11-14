-- Printed breed QR links intentionally work without a RingMaster account.
-- Keep that narrow public workflow separate from staff reports (which include
-- exhibitor contact details). Existing show/section/breed links remain valid.
create schema if not exists qr_results_private;
revoke all on schema qr_results_private from public, anon, authenticated;

create or replace function qr_results_private.assert_scope(p_show uuid,p_section uuid,p_breed text)
returns void language plpgsql stable set search_path='' as $$
begin
 if p_section is null or nullif(trim(p_breed),'') is null or not exists(
   select 1 from public.shows sh join public.show_sections s on s.show_id=sh.id
   where sh.id=p_show and s.id=p_section and sh.is_published=true
     and coalesce(sh.is_locked,false)=false and s.is_enabled=true
 ) then
   raise exception 'This QR results link is unavailable. The show must be published and unlocked, with an enabled section.' using errcode='42501';
 end if;
end $$;

create or replace function qr_results_private.deadline(p_show uuid,p_section uuid,p_breed text)
returns timestamptz language sql stable set search_path='' as $$
 select min(t) from (
   select l.lock_starts_at t from public.show_result_entry_locks l
   where l.show_id=p_show and l.section_id=p_section and lower(trim(l.breed_id))=lower(trim(p_breed))
   union all
   -- Honor BOB selections already recorded before this repair.
   select min(a.created_at)+interval '20 minutes' from public.entry_awards a
   join public.entries e on e.id=a.entry_id and e.show_id=a.show_id
   where e.show_id=p_show and e.section_id=p_section and lower(trim(e.breed))=lower(trim(p_breed))
     and not coalesce(e.is_fur,false) and upper(trim(a.award_code))='BOB'
 ) deadlines;
$$;

create or replace function qr_results_private.assert_editable(p_show uuid,p_section uuid,p_breed text)
returns void language plpgsql set search_path='' as $$
begin
 perform qr_results_private.assert_scope(p_show,p_section,p_breed);
 -- Serialize BOB selection and concurrent saves for the same breed/section.
 perform pg_advisory_xact_lock(hashtextextended('qr-results:'||p_show::text||':'||p_section::text||':'||lower(trim(p_breed)),0));
 if clock_timestamp() >= qr_results_private.deadline(p_show,p_section,p_breed) then
   raise exception 'This QR results link is locked. The 20-minute correction window after BOB has ended. Contact show staff.' using errcode='42501';
 end if;
end $$;

create or replace function public.get_qr_results_context(p_show_id uuid,p_section_id uuid,p_breed text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform qr_results_private.assert_scope(p_show_id,p_section_id,p_breed);
 select jsonb_build_object(
   'show',jsonb_build_object('name',sh.name,'final_award_mode',sh.final_award_mode,'coop_numbering_mode',sh.coop_numbering_mode),
   'section',jsonb_build_object('letter',s.letter,'display_name',s.display_name,'kind',s.kind),
   'lock_starts_at',qr_results_private.deadline(sh.id,s.id,p_breed),
   'locked',coalesce(statement_timestamp()>=qr_results_private.deadline(sh.id,s.id,p_breed),false),
   'judges',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'judge_id',a.judge_id,'assignment_label',a.assignment_label,
       'judges',jsonb_build_object('id',j.id,'display_name',j.display_name,'name',j.name,'first_name',j.first_name,'last_name',j.last_name,'arba_judge_number',j.arba_judge_number)))
     from public.judge_assignments a join public.judges j on j.id=a.judge_id where a.show_id=sh.id),'[]'::jsonb),
   'breed_class_systems',coalesce((select jsonb_agg(jsonb_build_object('name',b.name,'class_system',b.class_system))
     from public.breeds b where b.is_active and (b.local_show_id is null or b.local_show_id=sh.id)
       and lower(trim(b.name))=lower(trim(p_breed))),'[]'::jsonb)
 ) into result from public.shows sh join public.show_sections s on s.show_id=sh.id
 where sh.id=p_show_id and s.id=p_section_id;
 return result;
end $$;

create or replace function public.get_qr_results_entry_rows(
 p_show_id uuid,p_section_id uuid,p_breed text,p_after_entry_id uuid default null,p_page_size integer default 1000
) returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform qr_results_private.assert_scope(p_show_id,p_section_id,p_breed);
 return query
 with page_entries as materialized (
   select e.* from public.entries e
   where e.show_id=p_show_id and e.section_id=p_section_id and lower(trim(e.breed))=lower(trim(p_breed))
     and (p_after_entry_id is null or e.id>p_after_entry_id)
     and lower(coalesce(e.status,'')) not in ('cart','draft','cancelled','canceled')
   order by e.id limit greatest(1,least(coalesce(p_page_size,1000),1000))
 ), projection as (
select distinct on (e.id)
  e.id as entry_id,
  e.section_id,
  e.exhibitor_id,
  coalesce(
    nullif(ex.display_name, ''),
    nullif(ex.showing_name, ''),
    nullif(trim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
    ''
  )::text as exhibitor_label,
  coalesce(ex.exhibitor_number::text, sen.exhibitor_number::text, '')::text as exhibitor_number,
  coalesce(ex.showing_name, '')::text as exhibitor_showing_name,
  coalesce(ex.first_name, '')::text as exhibitor_first_name,
  coalesce(ex.last_name, '')::text as exhibitor_last_name,
  coalesce(e.breed, '')::text as breed,
  b.id as breed_id,
  coalesce(b.name, e.breed, '')::text as breed_name,
  coalesce(e.variety, '')::text as variety,
  coalesce(v.name, e.variety, '')::text as variety_name,
  coalesce(e.fur_variety, '')::text as fur_variety,
  case when coalesce(e.is_fur, false) then 'Fur / Wool' else coalesce(vg.name, '')::text end::text as group_name,
  coalesce(e.class_name, '')::text as class_name,
  coalesce(e.sex, '')::text as sex,
  coalesce(e.tattoo, '')::text as tattoo,
  case when coalesce(e.is_fur, false) then e.fur_placement::text else e.placement::text end as placement,
  case
    when lower(coalesce(e.result_status, '')) like 'disqualified%' then e.result_status::text
    when coalesce(e.is_disqualified, false) then ('Disqualified - ' || coalesce(nullif(trim(e.disqualified_reason), ''), 'Other'))::text
    else coalesce(e.result_status, 'Shown')::text
  end as result_status,
  case
    when e.scratched_at is not null then false
    when coalesce(e.is_fur, false) then coalesce(e.is_shown, true)
    else coalesce(e.is_shown, true)
  end::boolean as is_shown,
  coalesce(e.is_disqualified, false)::boolean as is_disqualified,
  coalesce(e.disqualified_reason, '')::text as disqualified_reason,
  e.scratched_at,
  e.judged_by_show_judge_id,
  coalesce(e.is_fur, false)::boolean as is_fur,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_group_awards, false) end::boolean as uses_group_awards,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_variety_awards, false) end::boolean as uses_variety_awards,
  0::integer as breed_sort_order,
  case when coalesce(e.is_fur, false) then 9999 when vg.id is null then 9998 else coalesce(vg.sort_order, 9998)::integer end as group_sort_order,
  case when coalesce(e.is_fur, false) then 9999 else coalesce(v.sort_order, 9999)::integer end as variety_sort_order,
  case
    when coalesce(e.is_fur, false) then 1000
    when lower(coalesce(e.class_name, '')) like '%senior%' then 0
    when lower(coalesce(e.class_name, '')) like '%intermediate%' then 1
    when lower(coalesce(e.class_name, '')) like '%junior%' then 2
    else 99
  end::integer as class_sort_order
from page_entries e
left join public.exhibitors ex on ex.id = e.exhibitor_id
left join lateral (
  select sen.* from public.show_exhibitor_numbers sen
  where sen.show_id = e.show_id and sen.exhibitor_id = e.exhibitor_id
  order by sen.exhibitor_number nulls last, sen.id limit 1
) sen on true
left join lateral (
  select b.* from public.breeds b
  where b.is_active = true
    and lower(trim(b.name)) = lower(trim(e.breed))
    and lower(b.species::text) = lower(e.species::text)
  order by b.name, b.id limit 1
) b on true
left join lateral (
  select v.* from public.varieties v
  where v.breed_id = b.id and lower(trim(v.name)) = lower(trim(e.variety))
  order by v.sort_order nulls last, v.name, v.id limit 1
) v on true
left join public.variety_groups vg on vg.id = v.group_id
left join public.show_sections s on s.id = e.section_id
order by e.id
 )
 select to_jsonb(r) || coalesce(public.entry_recognition_context(r.entry_id),'{}'::jsonb)
   || jsonb_build_object('animal_id',e.animal_id,'species',e.species,'animal_name',e.animal_name,
      'coop_number',coalesce(c.coop_number,''),
      '_awards',coalesce((select jsonb_agg(a.award_code order by a.award_code) from public.entry_awards a where a.entry_id=e.id and a.show_id=e.show_id),'[]'::jsonb))
 from projection r join page_entries e on e.id=r.entry_id
 join public.shows sh on sh.id=e.show_id join public.show_sections s on s.id=e.section_id
 left join lateral (
   select cn.coop_number::text as coop_number from public.show_animal_coop_numbers cn
   where cn.show_id=e.show_id and cn.animal_id=e.animal_id
     and cn.scope=case when sh.coop_numbering_mode='combined' then 'all' else s.kind::text end
   order by cn.coop_number limit 1
 ) c on true order by r.entry_id;
end $$;

create or replace function public.get_qr_fur_eligibility(p_show_id uuid,p_entry_id uuid)
returns table(entry_id uuid,blocked_reason text) language plpgsql stable security definer set search_path='' as $$
declare e public.entries;
begin
 select * into e from public.entries where id=p_entry_id and show_id=p_show_id;
 if not found then raise exception 'Entry not found'; end if;
 perform qr_results_private.assert_scope(e.show_id,e.section_id,e.breed);
 return query select * from public.report_fur_breed_eligibility(p_show_id,array[p_entry_id]);
end $$;

create or replace function public.set_qr_results_judge(p_show_id uuid,p_section_id uuid,p_breed text,p_entry_ids uuid[],p_judge_id uuid,p_writer_name text,p_writer_phone text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if nullif(trim(p_writer_name),'') is null or nullif(trim(p_writer_phone),'') is null then
   raise exception 'Writer name and phone number are required.' using errcode='23514';
 end if;
 perform qr_results_private.assert_editable(p_show_id,p_section_id,p_breed);
 if p_judge_id is not null and not exists(select 1 from public.judge_assignments where show_id=p_show_id and judge_id=p_judge_id) then
   raise exception 'Judge is not assigned to this show.' using errcode='23514';
 end if;
 if cardinality(p_entry_ids)>1000 or exists(select 1 from unnest(p_entry_ids) x where not exists(
   select 1 from public.entries e where e.id=x and e.show_id=p_show_id and e.section_id=p_section_id and lower(trim(e.breed))=lower(trim(p_breed)))) then
   raise exception 'Entries must belong to this QR breed and section.' using errcode='23514';
 end if;
 update public.entries set judged_by_show_judge_id=p_judge_id,updated_at=now()
 where id=any(p_entry_ids) and show_id=p_show_id and section_id=p_section_id and lower(trim(breed))=lower(trim(p_breed));
end $$;
-- QR correction requests still require the existing staff PIN, and the QR
-- deadline applies before invoking that separately audited correction path.
create or replace function public.apply_qr_entry_correction(
 p_show_id uuid,p_entry_id uuid,p_field_name text,p_new_value text,p_reason text,
 p_writer_name text,p_writer_phone text,p_pin_code text
) returns void language plpgsql security definer set search_path='' as $$
declare e public.entries;
begin
 select * into e from public.entries where id=p_entry_id and show_id=p_show_id;
 if not found then raise exception 'Entry not found'; end if;
 if nullif(trim(p_writer_name),'') is null or nullif(trim(p_writer_phone),'') is null then
   raise exception 'Writer name and phone number are required.' using errcode='23514';
 end if;
 perform qr_results_private.assert_editable(e.show_id,e.section_id,e.breed);
 perform public.apply_entry_correction(p_show_id,p_entry_id,p_field_name,p_new_value,p_reason,p_writer_name,p_writer_phone,p_pin_code);
end $$;
revoke all on function public.apply_qr_entry_correction(uuid,uuid,text,text,text,text,text,text) from public;
grant execute on function public.apply_qr_entry_correction(uuid,uuid,text,text,text,text,text,text) to anon,authenticated,service_role;

create or replace function public.save_results_entry(
  p_show_id uuid,
  p_entry_id uuid,
  p_placement text,
  p_result_status text,
  p_disqualified_reason text,
  p_is_shown boolean,
  p_is_disqualified boolean,
  p_judged_by_show_judge_id uuid,
  p_result_entered_by_name text,
  p_result_entered_by_phone text,
  p_awards text[],
  p_is_qr_entry_mode boolean
)
returns table(
  id uuid,
  placement integer,
  result_status text,
  judged_by_show_judge_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_section_id uuid;
  v_breed text;
  v_is_fur boolean;
  v_deadline timestamptz;
  v_placement integer := nullif(trim(p_placement), '')::integer;
begin
  select e.section_id, e.breed, coalesce(e.is_fur, false)
    into v_section_id, v_breed, v_is_fur
  from public.entries e
  where e.id = p_entry_id
    and e.show_id = p_show_id;

  if not found then
    raise exception 'Entry not found';
  end if;

  if coalesce(p_is_qr_entry_mode,false) then
    if nullif(trim(p_result_entered_by_name),'') is null or nullif(trim(p_result_entered_by_phone),'') is null then
      raise exception 'Writer name and phone number are required.' using errcode='23514';
    end if;
    perform qr_results_private.assert_editable(p_show_id,v_section_id,v_breed);
    if p_judged_by_show_judge_id is not null and not exists(select 1 from public.judge_assignments where show_id=p_show_id and judge_id=p_judged_by_show_judge_id) then
      raise exception 'Judge is not assigned to this show.' using errcode='23514';
    end if;
  elsif coalesce(auth.jwt()->>'role','')<>'service_role' and
    (auth.uid() is null or not (public.user_can_enter_results(p_show_id) or public.user_can_manage_entries(p_show_id))) then
    raise exception 'You do not have permission to enter results for this show.' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('qr-results:'||p_show_id::text||':'||v_section_id::text||':'||lower(trim(v_breed)),0));
  -- Persist an existing deadline before removing/replacing BOB. Corrections
  -- must never reset or erase the correction window.
  v_deadline := qr_results_private.deadline(p_show_id,v_section_id,v_breed);
  if v_deadline is null and not v_is_fur and exists(select 1 from unnest(p_awards) a where upper(trim(a))='BOB') then
    v_deadline := clock_timestamp()+interval '20 minutes';
  end if;
  if v_deadline is not null then
    insert into public.show_result_entry_locks(show_id,section_id,breed_id,lock_starts_at)
    values(p_show_id,v_section_id,v_breed,v_deadline)
    on conflict(show_id,section_id,breed_id) do update
      set lock_starts_at=least(show_result_entry_locks.lock_starts_at,excluded.lock_starts_at),updated_at=now();
  end if;

  update public.entries as e
  set
    placement = case when v_is_fur then e.placement else v_placement::text end,
    fur_placement = case when v_is_fur then v_placement else e.fur_placement end,
    result_status = p_result_status,
    disqualified_reason = p_disqualified_reason,
    is_shown = p_is_shown,
    is_disqualified = p_is_disqualified,
    judged_by_show_judge_id = p_judged_by_show_judge_id,
    result_entered_by_user_id = auth.uid(),
    result_entered_by_name = p_result_entered_by_name,
    result_entered_by_phone = p_result_entered_by_phone,
    result_entered_at = now(),
    updated_at = now()
  where e.id = p_entry_id
    and e.show_id = p_show_id;

  delete from public.entry_awards ea
  where ea.show_id = p_show_id
    and ea.entry_id = p_entry_id
    and not (
      upper(trim(ea.award_code)) = any(
        select upper(trim(x)) from unnest(coalesce(p_awards, array[]::text[])) as x
      )
    );

  if p_awards is not null and array_length(p_awards, 1) > 0 then
    insert into public.entry_awards (show_id, entry_id, award_code)
    select distinct p_show_id, p_entry_id, upper(trim(award_code))
    from unnest(p_awards) as award_code
    where trim(award_code) <> ''
    on conflict (entry_id, award_code) do nothing;
  end if;

  return query
  select
    e.id,
    case
      when coalesce(e.is_fur, false) then e.fur_placement
      else nullif(trim(e.placement), '')::integer
    end,
    e.result_status,
    e.judged_by_show_judge_id
  from public.entries e
  where e.id = p_entry_id
    and e.show_id = p_show_id;
end;
$$;


revoke all on all functions in schema qr_results_private from public,anon,authenticated;
revoke all on function public.get_qr_results_context(uuid,uuid,text),public.get_qr_results_entry_rows(uuid,uuid,text,uuid,integer),public.get_qr_fur_eligibility(uuid,uuid),public.set_qr_results_judge(uuid,uuid,text,uuid[],uuid,text,text) from public;
grant execute on function public.get_qr_results_context(uuid,uuid,text),public.get_qr_results_entry_rows(uuid,uuid,text,uuid,integer),public.get_qr_fur_eligibility(uuid,uuid),public.set_qr_results_judge(uuid,uuid,text,uuid[],uuid,text,text) to anon,authenticated,service_role;
revoke all on function public.save_results_entry(uuid,uuid,text,text,text,boolean,boolean,uuid,text,text,text[],boolean) from public;
grant execute on function public.save_results_entry(uuid,uuid,text,text,text,boolean,boolean,uuid,text,text,text[],boolean) to anon,authenticated,service_role;
notify pgrst,'reload schema';
