create table public.show_favorites (
 user_id uuid not null references auth.users(id) on delete cascade,
 show_id uuid not null references public.shows(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(user_id,show_id)
);
alter table public.show_favorites enable row level security;
revoke all on public.show_favorites from anon,authenticated;
grant select,insert,delete on public.show_favorites to authenticated;
grant all on public.show_favorites to service_role;
create policy own_favorites_read on public.show_favorites for select to authenticated using(user_id=(select auth.uid()));
create policy own_favorites_add on public.show_favorites for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.shows s where s.id=show_id and s.is_published and not s.is_demo and not s.is_test and not s.is_closed));
create policy own_favorites_remove on public.show_favorites for delete to authenticated using(user_id=(select auth.uid()));
create index show_favorites_show_idx on public.show_favorites(show_id);

create or replace function public.breeder_calendar_export(p_owner uuid,p_after uuid default null)
returns table(id uuid,payload jsonb) language sql security invoker set search_path='' as $$
 with entered as (
 select e.show_id,count(*) as entry_count,jsonb_agg(jsonb_build_object('id',e.id,'animal_name',e.animal_name,'tattoo',e.tattoo,'breed',e.breed,'variety',e.variety,'class_name',e.class_name,'sex',e.sex,'exhibitor_name',x.display_name) order by x.display_name,e.tattoo,e.id) as entries
 from public.entries e left join public.exhibitors x on x.id=e.exhibitor_id
 where (e.exhibitor_user_id=p_owner or x.owner_user_id=p_owner or x.claimed_by_user_id=p_owner)
 and lower(trim(e.status)) in ('active','submitted','entered') and e.scratched_at is null and not e.is_test group by e.show_id
 )
 select s.id,jsonb_build_object('id',s.id,'name',s.name,'start_date',s.start_date,'end_date',s.end_date,'location_name',s.location_name,'location_address',s.location_address,'timezone',s.timezone,'entry_count',coalesce(e.entry_count,0),'entries',coalesce(e.entries,'[]'::jsonb),'is_favorite',f.user_id is not null and s.is_published,'entry_close_at',s.entry_close_at)
 from public.shows s left join entered e on e.show_id=s.id
 left join public.show_favorites f on f.show_id=s.id and f.user_id=p_owner
 where (e.show_id is not null or (f.user_id is not null and s.is_published))
 and not s.is_test and not s.is_demo and not s.is_closed
 and (p_after is null or s.id>p_after)
 order by s.id limit 500;
$$;
revoke all on function public.breeder_calendar_export(uuid,uuid) from public,anon,authenticated;
grant execute on function public.breeder_calendar_export(uuid,uuid) to service_role;
