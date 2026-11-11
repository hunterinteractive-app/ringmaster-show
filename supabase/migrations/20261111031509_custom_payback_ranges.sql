-- Custom premium editing uses the same show entitlement as BBOS and waves.
-- Existing ordinary-show schedules and their save RPC are unchanged.
create or replace function show_awards_private.save_custom_paybacks(p_show_id uuid,p_section_id uuid,p_rows jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_schedule_id uuid;
begin
 if (select auth.uid()) is null or not public.can_configure_best_opposite_final_award(p_show_id) then
   raise exception 'Custom premium ranges are only available for eligible shows.' using errcode='42501';
 end if;
 if p_section_id is not null and not exists(select 1 from public.show_sections where id=p_section_id and show_id=p_show_id) then
   raise exception 'Section does not belong to show.' using errcode='22023';
 end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' then
   raise exception 'A premium row list is required.' using errcode='22023';
 end if;
 if jsonb_array_length(p_rows)>1000 then raise exception 'Too many premium rows.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_to_recordset(p_rows) as r(applies_to_species text,min_shown integer,max_shown integer,placement integer,amount_cents integer)
   where r.applies_to_species is null or r.applies_to_species not in ('rabbit','cavy')
     or r.min_shown is null or r.min_shown<1 or r.max_shown<r.min_shown
     or r.placement is null or r.placement<1 or r.placement>r.max_shown
     or r.amount_cents is null or r.amount_cents<0) then
   raise exception 'Invalid class-size range, placement, or premium amount.' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_to_recordset(p_rows) as r(applies_to_species text,min_shown integer,max_shown integer,placement integer)
   group by r.applies_to_species,r.min_shown,r.max_shown,r.placement having count(*)>1) then
   raise exception 'Duplicate premium placement in a class-size range.' using errcode='22023';
 end if;
 if exists(
   with ranges as (select distinct r.applies_to_species,r.min_shown,r.max_shown
     from jsonb_to_recordset(p_rows) as r(applies_to_species text,min_shown integer,max_shown integer)),
   numbered as (select *,row_number() over() n from ranges)
   select 1 from numbered a join numbered b on a.n<b.n and a.applies_to_species=b.applies_to_species
     and (a.max_shown is null or b.min_shown<=a.max_shown)
     and (b.max_shown is null or a.min_shown<=b.max_shown)
 ) then raise exception 'Class-size ranges overlap for the same species.' using errcode='22023'; end if;

 perform pg_advisory_xact_lock(hashtextextended('custom-payback:'||p_show_id::text,0));
 if (select count(*) from public.show_payback_schedules s where s.show_id=p_show_id
     and s.section_id is not distinct from p_section_id and s.applies_to='class_placements')>1 then
   raise exception 'Duplicate saved schedules need review before replacing premiums.' using errcode='22023';
 end if;
 select s.id into v_schedule_id from public.show_payback_schedules s where s.show_id=p_show_id
   and s.section_id is not distinct from p_section_id and s.applies_to='class_placements' for update;
 if v_schedule_id is null then
   v_schedule_id:=gen_random_uuid();
   insert into public.show_payback_schedules(id,show_id,section_id,applies_to,is_enabled)
     values(v_schedule_id,p_show_id,p_section_id,'class_placements',true);
 else
   update public.show_payback_schedules set is_enabled=true, updated_at=now() where id=v_schedule_id;
 end if;
 delete from public.show_payback_schedule_rows r where r.schedule_id=v_schedule_id;
 insert into public.show_payback_schedule_rows(schedule_id,applies_to_species,min_shown,max_shown,placement,amount_cents)
   select v_schedule_id,r.applies_to_species,r.min_shown,r.max_shown,r.placement,r.amount_cents
   from jsonb_to_recordset(p_rows) as r(applies_to_species text,min_shown integer,max_shown integer,placement integer,amount_cents integer)
   where r.amount_cents>0;
 return v_schedule_id;
end $$;
revoke all on function show_awards_private.save_custom_paybacks(uuid,uuid,jsonb) from public,anon;
grant execute on function show_awards_private.save_custom_paybacks(uuid,uuid,jsonb) to authenticated;

create or replace function public.save_show_custom_payback_schedule(p_show_id uuid,p_section_id uuid,p_rows jsonb)
returns uuid language sql security invoker set search_path='' as $$
 select show_awards_private.save_custom_paybacks(p_show_id,p_section_id,p_rows);
$$;
revoke all on function public.save_show_custom_payback_schedule(uuid,uuid,jsonb) from public,anon;
grant execute on function public.save_show_custom_payback_schedule(uuid,uuid,jsonb) to authenticated;
