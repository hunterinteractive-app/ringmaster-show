begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temp table nd_ids(key text primary key,id uuid default gen_random_uuid());
insert into nd_ids(key) values('owner'),('other'),('show'),('section'),('othersection'),('noemail'),('blankemail'),('email'),('pack');
grant all on nd_ids to authenticated,service_role;
insert into auth.users(id) select id from nd_ids where key in ('owner','other');
insert into shows(id,name,owner_user_id,created_by,start_date,end_date)
select s.id,'Synthetic no-email delivery',u.id,u.id,'2027-01-01','2027-01-01' from nd_ids s join nd_ids u on u.key='owner' where s.key='show';
insert into role_assignments(user_id,show_id,role) select (select id from nd_ids where key='owner'),(select id from nd_ids where key='show'),'admin';
-- Local foundation uses show_managers for finalization authorization.
do $$begin
 if to_regclass('public.show_managers') is not null then
  insert into public.show_managers(show_id,user_id) select (select id from nd_ids where key='show'),(select id from nd_ids where key='owner');
 end if;
end$$;
insert into show_sections(id,show_id,kind,letter,judging_date)
select id,(select id from nd_ids where key='show'),'open',case when key='section' then 'A' else 'B' end,'2027-01-01' from nd_ids where key in ('section','othersection');
insert into exhibitors(id,display_name,showing_name,first_name,last_name,email,phone,address_line1,city,state,zip,owner_user_id,is_local_only,created_for_show_id)
select id,key,key,key,'Fixture',case when key='email' then 'fixture@example.test' when key='blankemail' then '  ' else null end,
'5551234567','10 Test St','Test City','IN','46000',null,true,(select id from nd_ids where key='show') from nd_ids where key in ('noemail','blankemail','email');
select is((select count(*)::int from exhibitors where id in(select id from nd_ids where key in ('noemail','blankemail')) and owner_user_id is null and nullif(trim(email),'') is null),2,'no-email exhibitors save unowned with contact details');
insert into show_report_artifacts(id,show_id,report_name,artifact_status,metadata,storage_bucket,storage_path,section_ids,scope_key)
select gen_random_uuid(),(select id from nd_ids where key='show'),r::report_type,'generated',
jsonb_build_object('exhibitor_id',e.id,'exhibitor_email','STALE@example.test'), 'show-files',e.id::text||r||'.pdf',array[(select id from nd_ids where key='section')],'fixture'
from nd_ids e cross join unnest(array['exhibitor_report','legs','checkin_sheet']) r where e.key in ('noemail','blankemail','email');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from nd_ids where key='owner'),'role','authenticated')::text,true);
set local role authenticated;
select lives_ok($$insert into exhibitors(id,display_name,is_local_only,created_for_show_id,email,owner_user_id)
 values(gen_random_uuid(),'Staff-created no-email fixture',true,(select id from nd_ids where key='show'),null,null)$$,
 'assigned staff can save a no-email exhibitor');
update nd_ids set id=public.queue_manual_report_print_pack((select id from nd_ids where key='show'),null,'results') where key='pack';
select is((select jsonb_array_length(sources) from exhibitor_print_packs where id=(select id from nd_ids where key='pack')),4,'only current no-email exhibitor reports and legs enter packet');
select ok(not public.can_download_exhibitor_print_pack((select storage_path from exhibitor_print_packs where id=(select id from nd_ids where key='pack'))),'queued packet cannot be downloaded');
select ok((select manual_delivery from exhibitor_print_packs where id=(select id from nd_ids where key='pack')),'manual pack is separate from allowlisted full pack');
select is(public.queue_manual_report_print_pack((select id from nd_ids where key='show'),null,'results'),(select id from nd_ids where key='pack'),'repeated prepare reuses exact current packet');
select throws_ok($$select public.queue_exhibitor_print_pack((select id from nd_ids where key='show'))$$,'42501','This report is restricted to selected accounts.','staff no-email access does not grant full-pack access');
select throws_ok($$select public.queue_manual_report_print_pack((select id from nd_ids where key='show'),gen_random_uuid(),'results')$$,'22023','Invalid report scope.','foreign scope rejected');
select throws_ok($$select public.queue_manual_report_print_pack((select id from nd_ids where key='show'),null,'wrong')$$,'22023','Invalid report scope.','unknown report family rejected');
select lives_ok($$select public.queue_manual_report_print_pack((select id from nd_ids where key='show'),null,'checkin')$$,'check-in packet available separately');
select is((select jsonb_array_length(sources) from exhibitor_print_packs where show_id=(select id from nd_ids where key='show') and report_family='checkin'),2,'check-in packet contains no results or email recipients');
select lives_ok($$select public.mark_report_manual_delivery((select id from nd_ids where key='show'),
(select sources from exhibitor_print_packs where id=(select id from nd_ids where key='pack')),'mailed')$$,'record mailed for exact report revisions');
select is((select count(*)::int from report_manual_deliveries where show_id=(select id from nd_ids where key='show') and method='mailed'),4,'four revisions marked mailed');
select ok((select bool_and(recorded_by=(select id from nd_ids where key='owner')) from report_manual_deliveries where show_id=(select id from nd_ids where key='show')),'recorder derived from signed-in staff');
select throws_ok($$select public.mark_report_manual_delivery((select id from nd_ids where key='show'),
(select sources from exhibitor_print_packs where id=(select id from nd_ids where key='pack')),'printed')$$,'22023','Choose reports and a delivery method.','printing cannot masquerade as delivery');
reset role;
update show_report_artifacts set generation=generation+1 where show_id=(select id from nd_ids where key='show') and report_name='legs';
set local role authenticated;
select throws_ok($$select public.mark_report_manual_delivery((select id from nd_ids where key='show'),
(select sources from exhibitor_print_packs where id=(select id from nd_ids where key='pack')),'handed_out')$$,'22023','Reports changed. Refresh before recording delivery.','stale dialog cannot mark regenerated reports delivered');
select is((select count(*)::int from report_manual_deliveries d join show_report_artifacts a on a.id=d.artifact_id and a.generation=d.generation where a.show_id=(select id from nd_ids where key='show')),2,'regenerated leg revisions are outstanding');
reset role;
update exhibitor_print_packs set artifact_status='generated' where id=(select id from nd_ids where key='pack');
set local role authenticated;
select ok(public.can_download_exhibitor_print_pack((select storage_path from exhibitor_print_packs where id=(select id from nd_ids where key='pack'))),'authorized staff can download generated manual packet');
reset role;
set local role service_role;
select is(jsonb_array_length(public.manual_print_pack_current_sources((select id from nd_ids where key='pack'))),4,'worker reads current manifest under original staff authorization');
reset role;
update exhibitors set email='new@example.test' where id=(select id from nd_ids where key='noemail');
set local role service_role;
select is(jsonb_array_length(public.manual_print_pack_current_sources((select id from nd_ids where key='pack'))),2,'worker detects email contact added after queueing');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from nd_ids where key='other'),'role','authenticated')::text,true);
set local role authenticated;
select throws_ok($$insert into exhibitors(id,display_name,is_local_only,created_for_show_id,email,owner_user_id)
 values(gen_random_uuid(),'Unauthorized fixture',true,(select id from nd_ids where key='show'),null,null)$$,
 '42501',null,'unassigned user cannot create an unowned exhibitor for this show');
select throws_ok($$select public.queue_manual_report_print_pack((select id from nd_ids where key='show'),null,'results')$$,'42501','Show staff access required.','unrelated user cannot queue');
select throws_ok($$select public.mark_report_manual_delivery((select id from nd_ids where key='show'),'[]','mailed')$$,'42501','Show staff access required.','unrelated user cannot mark delivery');
select is((select count(*)::int from report_manual_deliveries where show_id=(select id from nd_ids where key='show')),0,'delivery records hidden from unrelated users');
select is((select count(*)::int from exhibitor_print_packs where show_id=(select id from nd_ids where key='show')),0,'print packets hidden from unrelated users');
reset role;
select ok(not has_function_privilege('anon','public.queue_manual_report_print_pack(uuid,uuid,text)','execute'),'anonymous cannot queue');
select ok(not has_function_privilege('authenticated','public.manual_print_pack_current_sources(uuid)','execute'),'worker manifest restricted to service role');
select * from finish();
rollback;
