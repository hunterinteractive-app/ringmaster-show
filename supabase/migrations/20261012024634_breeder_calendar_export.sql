-- Read-only account-scoped calendar snapshot; only the trusted integration can call.
create function public.breeder_calendar_export(p_owner uuid,p_after uuid default null)
returns table(id uuid,payload jsonb) language sql security invoker set search_path='' as $$
 select s.id,jsonb_build_object('id',s.id,'name',s.name,'start_date',s.start_date,
 'end_date',s.end_date,'location_name',s.location_name,'location_address',s.location_address,
 'timezone',s.timezone,'entry_count',count(*),
 'entries',jsonb_agg(jsonb_build_object('id',e.id,'animal_name',e.animal_name,'tattoo',e.tattoo,
 'breed',e.breed,'variety',e.variety,'class_name',e.class_name,'sex',e.sex,'exhibitor_name',x.display_name)
 order by x.display_name,e.tattoo,e.id))
 from public.shows s join public.entries e on e.show_id=s.id
 left join public.exhibitors x on x.id=e.exhibitor_id
 where (e.exhibitor_user_id=p_owner or x.owner_user_id=p_owner or x.claimed_by_user_id=p_owner)
 and lower(trim(e.status)) in ('active','submitted','entered') and e.scratched_at is null
 and not e.is_test and not s.is_test and not s.is_demo and not s.is_closed
 and (p_after is null or s.id>p_after)
 group by s.id order by s.id limit 500;
$$;
revoke all on function public.breeder_calendar_export(uuid,uuid) from public,anon,authenticated;
grant execute on function public.breeder_calendar_export(uuid,uuid) to service_role;
