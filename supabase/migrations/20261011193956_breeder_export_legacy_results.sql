-- Server-only export, using the same ownership and generated/current rules as
-- Show's exhibitor report inbox. Draft, test and demo reports are excluded.
create or replace function public.breeder_report_export(p_owner uuid, p_kind text, p_after uuid default null)
returns table(id uuid, payload jsonb) language plpgsql security invoker
set search_path = '' as $$
begin
 if p_kind = 'reports' then
  return query
  select a.id, jsonb_build_object('id',a.id,'show_id',s.id,'show_name',s.name,
   'show_start_date',s.start_date,'report_name',a.report_name,
   'exhibitor_id',a.metadata->>'exhibitor_id','exhibitor_name',a.metadata->>'exhibitor_name',
   'file_name',a.file_name,'generated_at',a.generated_at,'legs_count',a.metadata->'legs_count',
   'storage_bucket',a.storage_bucket,'storage_path',a.storage_path)
  from public.show_report_artifacts a join public.shows s on s.id=a.show_id
  left join public.exhibitors ex on ex.id::text=a.metadata->>'exhibitor_id'
  where a.report_name::text in ('exhibitor_report','legs') and a.artifact_status::text='generated'
   and a.is_current and a.storage_bucket is not null and a.storage_path is not null
   and not coalesce(s.is_test,false) and not coalesce(s.is_demo,false)
   and (p_after is null or a.id>p_after)
   and (ex.owner_user_id=p_owner or ex.claimed_by_user_id=p_owner or exists(
    select 1 from public.entries e where e.show_id=a.show_id
     and e.exhibitor_id::text=a.metadata->>'exhibitor_id' and e.exhibitor_user_id=p_owner and not coalesce(e.is_test,false)))
  order by a.id limit 500;
 elsif p_kind = 'results' then
  return query
  select e.id, jsonb_build_object('id',e.id,'animal_id',e.animal_id,
   'breeder_animal_id',l.breeder_animal_id,'exhibitor_id',e.exhibitor_id,'show_id',e.show_id,
   'species',e.species,'animal_name',e.animal_name,'tattoo',e.tattoo,'breed',e.breed,
   'variety',e.variety,'sex',e.sex,'class_name',e.class_name,'status',e.status,
   'result_details',(select coalesce(jsonb_agg(jsonb_build_object('placing_label',r.placing_label,'award',r.award,'legs_awarded',r.legs_awarded) order by r.created_at desc,r.id),'[]'::jsonb) from public.results r where r.entry_id=e.id and r.show_id=e.show_id),
   'placement',e.placement,'special_awards',e.special_awards,'is_shown',e.is_shown,
   'is_disqualified',e.is_disqualified,'disqualified_reason',e.disqualified_reason,
   'result_status',e.result_status,'is_fur',e.is_fur,'fur_placement',e.fur_placement,
   'fur_award',e.fur_award,'scratched_at',e.scratched_at,
   'shows',jsonb_build_object('name',s.name,'start_date',s.start_date,'location_name',s.location_name),
   'entry_awards',(select coalesce(jsonb_agg(jsonb_build_object('award_code',w.award_code) order by w.award_code),'[]'::jsonb) from public.entry_awards w where w.entry_id=e.id))
  from public.entries e join public.shows s on s.id=e.show_id
  left join public.exhibitors ex on ex.id=e.exhibitor_id
  left join public.breeder_connections c on c.owner_user_id=p_owner
  left join public.breeder_animal_links l on l.connection_id=c.id and l.animal_id=e.animal_id
  where not coalesce(e.is_test,false) and not coalesce(s.is_test,false) and not coalesce(s.is_demo,false)
   and (p_after is null or e.id>p_after)
   and (e.exhibitor_user_id=p_owner or ex.owner_user_id=p_owner or ex.claimed_by_user_id=p_owner)
   and exists(select 1 from public.show_report_artifacts a where a.show_id=e.show_id
    and a.metadata->>'exhibitor_id'=e.exhibitor_id::text and a.report_name::text='exhibitor_report'
    and a.artifact_status::text='generated' and a.is_current and a.storage_path is not null and a.storage_bucket is not null)
  order by e.id limit 500;
 else raise exception 'Unknown report export';
 end if;
end $$;
revoke all on function public.breeder_report_export(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.breeder_report_export(uuid,text,uuid) to service_role;
