-- Private planning storage for a single show uses the same authorized operations.
alter table public.superintendent_workspaces drop constraint superintendent_workspaces_show_ids_check;
alter table public.superintendent_workspaces add constraint superintendent_workspaces_show_ids_check check (cardinality(show_ids)>=1);
create unique index superintendent_single_show_workspace on public.superintendent_workspaces((show_ids[1])) where cardinality(show_ids)=1;
create or replace function public.can_view_superintendent_workspace(p_show_ids uuid[])
returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and cardinality(p_show_ids)>=1
 and not exists(select 1 from unnest(p_show_ids) s(id) where not coalesce(public.user_can_view_show_lineup(s.id),false));
$$;
create function private.ensure_show_lineup_workspace(p_show_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_name text;
begin
 if auth.uid() is null or not coalesce(public.user_can_manage_show_lineup(p_show_id),false) then
 raise exception 'You need permission to manage this show line-up.' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('single-lineup:'||p_show_id::text,0));
 select id into v_id from public.superintendent_workspaces where show_ids=array[p_show_id];
 if v_id is null then
 select name into v_name from public.shows where id=p_show_id;
 if v_name is null then raise exception 'Show not found.'; end if;
 insert into public.superintendent_workspaces(name,show_ids) values(v_name,array[p_show_id]) returning id into v_id;
 end if;
 return v_id;
end;
$$;
revoke all on function private.ensure_show_lineup_workspace(uuid) from public,anon;
grant execute on function private.ensure_show_lineup_workspace(uuid) to authenticated;
create function public.ensure_show_lineup_workspace(p_show_id uuid)
returns uuid language sql security invoker set search_path='' as $$ select private.ensure_show_lineup_workspace(p_show_id) $$;
revoke all on function public.ensure_show_lineup_workspace(uuid) from public,anon;
grant execute on function public.ensure_show_lineup_workspace(uuid) to authenticated;
