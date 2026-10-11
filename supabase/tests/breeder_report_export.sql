begin;
set local role service_role;
do $$
declare owner uuid; r record;
begin
 select owner_user_id into owner from public.breeder_connections limit 1;
 for r in select * from public.breeder_report_export(owner,'reports') loop
  if not exists(select 1 from public.show_report_artifacts a join public.shows s on s.id=a.show_id
    where a.id=r.id and a.is_current and a.artifact_status::text='generated'
    and not coalesce(s.is_test,false) and not coalesce(s.is_demo,false)) then raise exception 'Unreleased or test report exported'; end if;
 end loop;
 for r in select * from public.breeder_report_export(owner,'results') loop
  if not exists(select 1 from public.entries e left join public.exhibitors x on x.id=e.exhibitor_id where e.id=r.id
   and (e.exhibitor_user_id=owner or x.owner_user_id=owner or x.claimed_by_user_id=owner)) then raise exception 'Foreign results exported'; end if;
 end loop;
 if exists(select 1 from public.breeder_report_export(gen_random_uuid(),'reports')) then raise exception 'Unknown account received reports'; end if;
 if has_function_privilege('anon','public.breeder_report_export(uuid,text,uuid)','execute')
  or has_function_privilege('authenticated','public.breeder_report_export(uuid,text,uuid)','execute') then raise exception 'Client can export arbitrary owner reports'; end if;
end $$;
rollback;
