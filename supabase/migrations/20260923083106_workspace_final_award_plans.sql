-- Award plans live outside the published show_judging_assignments and entry sync.
alter table public.workspace_specialties
 add column award_section_id uuid references public.show_sections(id) on delete cascade,
 add column award_code text,
 add constraint specialty_award_fields check ((award_section_id is null and award_code is null) or (award_section_id is not null and award_code is not null and entry_count=0));
create unique index workspace_award_plan_unique on public.workspace_specialties(workspace_id,award_section_id,award_code) where award_code is not null;
-- Published-lineup viewers must never receive private award plans.
drop policy workspace_specialties_read on public.workspace_specialties;
create policy workspace_specialties_read on public.workspace_specialties for select to authenticated using (
 exists(select 1 from public.superintendent_workspaces w where w.id=workspace_id
 and (award_code is null or not exists(select 1 from unnest(w.show_ids) s(id) where not coalesce(public.user_can_manage_show_lineup(s.id),false))))
);
create or replace function private.mutate_workspace_lineup(p_workspace_id uuid,p_expected jsonb,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_shows uuid[]; v_id uuid; v_order integer; v_section public.show_sections; v_mode text; v_name text; v_award text; v_label text; v_item jsonb; v_regular jsonb:='[]'::jsonb;
begin
 select show_ids into v_shows from public.superintendent_workspaces where id=p_workspace_id;
 if auth.uid() is null or v_shows is null or exists(select 1 from unnest(v_shows) s(id)
 where not coalesce(public.user_can_manage_show_lineup(s.id),false)) then
 raise exception 'You need superintendent access to both shows.' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_workspace_id::text,0));
 perform id from public.show_judging_assignments where show_id=any(v_shows) order by id for update;
 if p_expected is distinct from public.workspace_lineup_versions(p_workspace_id) then
 raise exception 'The line-up changed. Refresh before making another change.' using errcode='40001'; end if;
 if p_action='award_add' then
 select * into v_section from public.show_sections where id=(p_payload->>'p_section_id')::uuid;
 if not found or not(v_section.show_id=any(v_shows)) or not coalesce(v_section.is_enabled,true) then
 raise exception 'Award section is outside this workspace or disabled.' using errcode='42501'; end if;
 select coalesce(final_award_mode,'four_six_bis'),name into v_mode,v_name from public.shows where id=v_section.show_id;
 v_award:=p_payload->>'p_award_code';
 if v_award is null or not (
 (v_mode='four_six_bis' and v_award in ('BEST4','BEST6','BIS')) or
 (v_mode in ('bis_ris','bis_1ris_2ris','bis_1ris_2ris_bbos') and v_award='FINALS')
 ) then raise exception 'Award option does not match the show settings. Refresh and try again.'; end if;
 if not exists(select 1 from public.show_judging_assignments a where a.show_id=v_section.show_id
 and a.table_number=p_payload->>'p_table_number' and a.is_judge_change and a.judge_id is not null
 and a.sort_order<=(p_payload->>'p_sort_order')::integer) then
 raise exception 'Add a judge to this table before assigning final awards.'; end if;
 v_label:=case v_award when 'BEST4' then 'Best 4' when 'BEST6' then 'Best 6' when 'BIS' then 'BIS'
 else case v_mode when 'bis_ris' then 'BIS / RIS' when 'bis_1ris_2ris_bbos' then 'BIS / RIS / 2RIS / BBOS' else 'BIS / RIS / 2RIS' end end;
 insert into public.workspace_specialties(workspace_id,name,breed,entry_count,table_number,sort_order,status,scope,award_section_id,award_code)
 values(p_workspace_id,v_name,v_label,0,p_payload->>'p_table_number',(p_payload->>'p_sort_order')::integer,'draft',lower(v_section.kind::text),v_section.id,v_award);
 elsif p_action='specialty_save' then
 v_id:=nullif(p_payload->>'id','')::uuid;
 if p_payload ? 'scope' and (p_payload->>'scope' is null or p_payload->>'scope' not in ('open','youth')) then
 raise exception 'Choose Open or Youth.'; end if;
 v_order:=nullif(p_payload->>'sort_order','')::integer;
 if v_order is null and v_id is not null then
 select sort_order into v_order from public.workspace_specialties where id=v_id and workspace_id=p_workspace_id and table_number=trim(p_payload->>'table_number');
 end if;
 if v_order is null then
 select coalesce(max(position),-1)+1 into v_order from (
 select sort_order as position from public.show_judging_assignments where show_id=any(v_shows) and table_number=trim(p_payload->>'table_number')
 union all select sort_order from public.workspace_specialties where workspace_id=p_workspace_id and table_number=trim(p_payload->>'table_number')
 ) positions;
 end if;
 if v_id is not null and exists(select 1 from public.workspace_specialties where id=v_id and award_code is not null) then
 raise exception 'Use the line-up to manage award assignments.'; end if;
 if v_id is null then
 insert into public.workspace_specialties(workspace_id,name,breed,judge_name,entry_count,table_number,sort_order,status,scope)
 values(p_workspace_id,trim(p_payload->>'name'),trim(p_payload->>'breed'),trim(coalesce(p_payload->>'judge_name','')),
 (p_payload->>'entry_count')::integer,trim(p_payload->>'table_number'),v_order,p_payload->>'status',p_payload->>'scope');
 else
 update public.workspace_specialties set name=trim(p_payload->>'name'),breed=trim(p_payload->>'breed'),
 judge_name=trim(coalesce(p_payload->>'judge_name','')),entry_count=(p_payload->>'entry_count')::integer,
 table_number=trim(p_payload->>'table_number'),sort_order=v_order,status=p_payload->>'status',
 scope=case when p_payload ? 'scope' then p_payload->>'scope' else scope end
 where id=v_id and workspace_id=p_workspace_id;
 if not found then raise exception 'Specialty is outside this workspace.' using errcode='42501'; end if;
 end if;
 elsif p_action in ('move','delete','reorder') then
 for v_item in select value from jsonb_array_elements(case when p_action='reorder' then p_payload->'rows' else jsonb_build_array(p_payload) end) loop
 v_id:=(v_item->>'id')::uuid;
 if exists(select 1 from public.workspace_specialties where id=v_id and workspace_id=p_workspace_id) then
 if p_action='delete' then delete from public.workspace_specialties where id=v_id;
 else update public.workspace_specialties set sort_order=(v_item->>'sort_order')::integer,
 table_number=case when p_action='move' then v_item->>'table_number' else table_number end where id=v_id; end if;
 else v_regular:=v_regular||jsonb_build_array(v_item); end if;
 end loop;
 if jsonb_array_length(v_regular)>0 then
 perform private.mutate_workspace_lineup_core(p_workspace_id,public.workspace_lineup_versions(p_workspace_id),p_action,
 case when p_action='reorder' then jsonb_build_object('rows',v_regular) else v_regular->0 end);
 end if;
 else
 -- Auto Fill replaces host assignments only. Specialty rows remain untouched.
 return private.mutate_workspace_lineup_core(p_workspace_id,p_expected,p_action,p_payload);
 end if;
 return public.workspace_lineup_versions(p_workspace_id);
end;
$$;
