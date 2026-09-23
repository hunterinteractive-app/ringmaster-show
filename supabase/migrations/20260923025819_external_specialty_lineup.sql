-- Outside specialties are logistics only, never host-show entries or balances.
create table public.workspace_specialties (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.superintendent_workspaces(id) on delete cascade,
 name text not null check (length(trim(name)) between 1 and 160),
 breed text not null check (length(trim(breed)) between 1 and 100),
 judge_name text not null default '' check (length(judge_name)<=160),
 entry_count integer not null check (entry_count>=0),
 table_number text not null check (length(trim(table_number)) between 1 and 40),
 sort_order integer not null check (sort_order>=0),
 status text not null default 'draft' check (status in ('draft','in_progress','completed')),
 updated_at timestamptz not null default clock_timestamp()
);
create index workspace_specialties_workspace_idx on public.workspace_specialties(workspace_id);
alter table public.workspace_specialties enable row level security;
revoke all on public.workspace_specialties from public,anon,authenticated;
grant select on public.workspace_specialties to authenticated;
grant all on public.workspace_specialties to service_role;
create policy workspace_specialties_read on public.workspace_specialties for select to authenticated
 using (exists(select 1 from public.superintendent_workspaces w where w.id=workspace_id));
create trigger touch_specialty_version before update on public.workspace_specialties
 for each row execute function public.touch_lineup_assignment_version();

create or replace function public.workspace_lineup_versions(p_workspace_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'updated_at',a.updated_at,
 'workspace_marker_id',a.workspace_marker_id) order by a.id),'[]'::jsonb)
 from (
 select a.id,a.updated_at,a.workspace_marker_id from public.superintendent_workspaces w
 join public.show_judging_assignments a on a.show_id=any(w.show_ids) where w.id=p_workspace_id
 union all select s.id,s.updated_at,null::uuid from public.workspace_specialties s where s.workspace_id=p_workspace_id
 ) a;
$$;

alter function private.mutate_workspace_lineup(uuid,jsonb,text,jsonb) rename to mutate_workspace_lineup_core;
revoke all on function private.mutate_workspace_lineup_core(uuid,jsonb,text,jsonb) from public,anon,authenticated;
create function private.mutate_workspace_lineup(p_workspace_id uuid,p_expected jsonb,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_shows uuid[]; v_id uuid; v_item jsonb; v_regular jsonb:='[]'::jsonb;
begin
 select show_ids into v_shows from public.superintendent_workspaces where id=p_workspace_id;
 if auth.uid() is null or v_shows is null or exists(select 1 from unnest(v_shows) s(id)
 where not coalesce(public.user_can_manage_show_lineup(s.id),false)) then
 raise exception 'You need superintendent access to both shows.' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_workspace_id::text,0));
 perform id from public.show_judging_assignments where show_id=any(v_shows) order by id for update;
 if p_expected is distinct from public.workspace_lineup_versions(p_workspace_id) then
 raise exception 'The line-up changed. Refresh before making another change.' using errcode='40001'; end if;
 if p_action='specialty_save' then
 v_id:=nullif(p_payload->>'id','')::uuid;
 if v_id is null then
 insert into public.workspace_specialties(workspace_id,name,breed,judge_name,entry_count,table_number,sort_order,status)
 values(p_workspace_id,trim(p_payload->>'name'),trim(p_payload->>'breed'),trim(coalesce(p_payload->>'judge_name','')),
 (p_payload->>'entry_count')::integer,trim(p_payload->>'table_number'),(p_payload->>'sort_order')::integer,p_payload->>'status');
 else
 update public.workspace_specialties set name=trim(p_payload->>'name'),breed=trim(p_payload->>'breed'),
 judge_name=trim(coalesce(p_payload->>'judge_name','')),entry_count=(p_payload->>'entry_count')::integer,
 table_number=trim(p_payload->>'table_number'),sort_order=(p_payload->>'sort_order')::integer,status=p_payload->>'status'
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
revoke all on function private.mutate_workspace_lineup(uuid,jsonb,text,jsonb) from public,anon;
grant execute on function private.mutate_workspace_lineup(uuid,jsonb,text,jsonb) to authenticated;
-- Rebind the invoker wrapper after renaming its implementation.
create or replace function public.mutate_workspace_lineup(p_workspace_id uuid,p_expected jsonb,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.mutate_workspace_lineup(p_workspace_id,p_expected,p_action,p_payload);
$$;
