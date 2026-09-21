-- One visible judge change is mirrored into each source show so existing
-- judge sync, reports and exhibitor publishing continue using their own IDs.
alter table public.show_judging_assignments add column workspace_marker_id uuid;
create index show_judging_assignments_workspace_marker_idx
  on public.show_judging_assignments(workspace_marker_id) where workspace_marker_id is not null;

create function public.workspace_lineup_versions(p_workspace_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'updated_at',a.updated_at,
   'workspace_marker_id',a.workspace_marker_id) order by a.id),'[]'::jsonb)
 from public.superintendent_workspaces w
 join public.show_judging_assignments a on a.show_id=any(w.show_ids)
 where w.id=p_workspace_id;
$$;
revoke all on function public.workspace_lineup_versions(uuid) from public,anon;
grant execute on function public.workspace_lineup_versions(uuid) to authenticated;

-- The narrowly scoped definer performs publishing/sync for superintendents
-- without granting them general show-settings or entry-editing permissions.
create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;

-- Internal mapping used only by the authorized shared mutation. Preserve
-- explicit manual judge choices and all entries with recorded results.
create function private.workspace_lineup_entry_judges(p_show_ids uuid[])
returns table(entry_id uuid,judge_id uuid) language sql stable security invoker set search_path='' as $$
 select e.id, (
   select jc.judge_id from public.show_judging_assignments a
   cross join lateral (
     select m.judge_id from public.show_judging_assignments m
     where m.show_id=a.show_id and m.table_number=a.table_number
       and (m.is_judge_change or m.breed_id='__judge_change__')
       and m.sort_order<=a.sort_order and m.judge_id is not null
     order by m.sort_order desc,m.id limit 1
   ) jc
   where a.show_id=e.show_id and a.section_id=e.section_id
     and not coalesce(a.is_judge_change,false) and a.breed_id<>'__judge_change__'
     and lower(trim(a.breed_id))=lower(trim(e.breed::text))
     and (coalesce(a.variety_key,'')='' or lower(trim(a.variety_key))=lower(trim(coalesce(e.variety::text,''))))
   order by a.sort_order,a.id limit 1
 ) from public.entries e where e.show_id=any(p_show_ids) and e.result_entered_at is null;
$$;
revoke all on function private.workspace_lineup_entry_judges(uuid[]) from public,anon,authenticated;
create function private.mutate_workspace_lineup(
 p_workspace_id uuid, p_expected jsonb, p_action text, p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_shows uuid[]; v_row public.show_judging_assignments; v_item jsonb;
 v_params jsonb; v_show uuid; v_section uuid; v_judge uuid; v_marker uuid;
 v_id uuid; v_items jsonb; v_count integer; v_previous jsonb;
begin
 select show_ids into v_shows from public.superintendent_workspaces where id=p_workspace_id;
 if auth.uid() is null or v_shows is null or exists (
   select 1 from unnest(v_shows) s(id) where not coalesce(public.user_can_manage_show_lineup(s.id),false)
 ) then raise exception 'You need superintendent access to both shows.' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_workspace_id::text,0));
 perform id from public.show_judging_assignments where show_id=any(v_shows) order by id for update;
 if p_expected is distinct from public.workspace_lineup_versions(p_workspace_id) then
   raise exception 'The line-up changed. Refresh before making another change.' using errcode='40001';
 end if;
 select coalesce(jsonb_object_agg(entry_id::text,judge_id),'{}'::jsonb) into v_previous from private.workspace_lineup_entry_judges(v_shows);
 if p_action in ('add','replace') then
   v_items:=case when p_action='add' then jsonb_build_array(p_payload) else p_payload->'rows' end;
   if jsonb_typeof(v_items) is distinct from 'array' then raise exception 'Missing line-up rows.'; end if;
   if p_action='replace' then delete from public.show_judging_assignments where show_id=any(v_shows); end if;
   for v_params in select value from jsonb_array_elements(v_items) loop
     v_judge:=nullif(v_params->>'p_judge_id','')::uuid;
     if coalesce((v_params->>'p_is_judge_change')::boolean,false) then
       if v_judge is null or exists(select 1 from unnest(v_shows) s(id) where not exists(
         select 1 from public.get_show_lineup_judges(s.id) j where j.judge_id=v_judge and j.is_enabled
       )) then raise exception 'Choose a judge enabled for both shows.'; end if;
       v_marker:=gen_random_uuid();
       foreach v_show in array v_shows loop
         select r.id into v_id from public.upsert_show_judging_assignment(
           p_show_id=>v_show,p_breed_id=>'__judge_change__',p_judge_id=>v_judge,
           p_table_number=>v_params->>'p_table_number',p_sort_order=>(v_params->>'p_sort_order')::integer,
           p_is_judge_change=>true,p_entry_count_actual=>0,p_notes=>v_params->>'p_notes') r;
         update public.show_judging_assignments set workspace_marker_id=v_marker where id=v_id;
       end loop;
     else
       v_section:=nullif(v_params->>'p_section_id','')::uuid;
       select show_id into v_show from public.show_sections where id=v_section;
       if v_show is null or not (v_show=any(v_shows)) then
         raise exception 'This section does not belong to the shared line-up.' using errcode='42501'; end if;
       if nullif(v_params->>'p_breed_id','') is null or v_params->>'p_breed_id'='__judge_change__' then raise exception 'Choose a breed.'; end if;
       perform public.upsert_show_judging_assignment(
         p_show_id=>v_show,p_section_id=>v_section,p_breed_id=>v_params->>'p_breed_id',
         p_variety_key=>v_params->>'p_variety_key',p_judge_id=>null,
         p_table_number=>v_params->>'p_table_number',p_sort_order=>(v_params->>'p_sort_order')::integer,
         p_scope=>v_params->>'p_scope',p_entry_count_actual=>(v_params->>'p_entry_count_actual')::integer,
         p_notes=>v_params->>'p_notes');
     end if;
   end loop;
 elsif p_action in ('delete','move','reorder') then
   v_items:=case when p_action='reorder' then p_payload->'rows' else jsonb_build_array(p_payload) end;
   for v_item in select value from jsonb_array_elements(v_items) loop
     select * into v_row from public.show_judging_assignments where id=(v_item->>'id')::uuid;
     if not found or not(v_row.show_id=any(v_shows)) then raise exception 'Assignment is outside this workspace.' using errcode='42501'; end if;
     if p_action='delete' then
       delete from public.show_judging_assignments where show_id=any(v_shows)
         and (id=v_row.id or (v_row.workspace_marker_id is not null and workspace_marker_id=v_row.workspace_marker_id));
     else
       update public.show_judging_assignments set sort_order=(v_item->>'sort_order')::integer,
         table_number=case when p_action='move' then v_item->>'table_number' else table_number end
         where show_id=any(v_shows) and (id=v_row.id or (v_row.workspace_marker_id is not null and workspace_marker_id=v_row.workspace_marker_id));
     end if;
   end loop;
 elsif p_action='publish' then
   update public.shows set superintendent_judge_order_published=(p_payload->>'published')::boolean,
     superintendent_judge_order_published_at=case when (p_payload->>'published')::boolean then now() end,
     superintendent_judge_order_published_by=case when (p_payload->>'published')::boolean then auth.uid() end
     where id=any(v_shows);
   get diagnostics v_count=row_count;
   if v_count<>cardinality(v_shows) then raise exception 'Could not publish both shows.' using errcode='42501'; end if;
 elsif p_action<>'sync' or p_action is null then
   raise exception 'Unknown shared line-up operation.';
 end if;
 -- This is part of the same transaction. A failure in either show rolls back
 -- the entire operation, including Auto Fill and publishing.
 update public.entries e set judged_by_show_judge_id=current_lineup.judge_id,updated_at=now()
 from private.workspace_lineup_entry_judges(v_shows) current_lineup
 where e.id=current_lineup.entry_id and e.show_id=any(v_shows) and e.result_entered_at is null
   and (e.judged_by_show_judge_id is null or e.judged_by_show_judge_id=(v_previous->>e.id::text)::uuid)
   and e.judged_by_show_judge_id is distinct from current_lineup.judge_id;
 return public.workspace_lineup_versions(p_workspace_id);
end;
$$;
revoke all on function private.mutate_workspace_lineup(uuid,jsonb,text,jsonb) from public,anon;
grant execute on function private.mutate_workspace_lineup(uuid,jsonb,text,jsonb) to authenticated;
create function public.mutate_workspace_lineup(p_workspace_id uuid,p_expected jsonb,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.mutate_workspace_lineup(p_workspace_id,p_expected,p_action,p_payload);
$$;
revoke all on function public.mutate_workspace_lineup(uuid,jsonb,text,jsonb) from public,anon;
grant execute on function public.mutate_workspace_lineup(uuid,jsonb,text,jsonb) to authenticated;
