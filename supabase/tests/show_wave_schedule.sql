begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table wave_fixture(key text primary key,id uuid default gen_random_uuid());
insert into wave_fixture(key) values ('show'),('other_show'),('other'),('exhibitor'),('later_exhibitor'),('section'),('youth'),('wave1'),('wave2'),('rabbit1'),('rabbit1_youth'),('rabbit2'),('cavy1'),('later_entry');
grant select on wave_fixture to authenticated,anon,service_role;
insert into auth.users(id) select id from wave_fixture where key='other';
insert into public.shows(id,name,created_by,owner_user_id,timezone,start_date,end_date)
select id,'Wave fixture',
 case when key='show' then '3e8dddf9-3a17-4ebb-aeab-9b51d31e7871'::uuid else (select id from wave_fixture where key='other') end,
 case when key='show' then '3e8dddf9-3a17-4ebb-aeab-9b51d31e7871'::uuid else (select id from wave_fixture where key='other') end,
 'America/Chicago',current_date,current_date+3 from wave_fixture where key in ('show','other_show');
insert into public.exhibitors(id,first_name,last_name,exhibitor_number,email)
select id,'Wave','Tester',case when key='exhibitor' then 991001 else 991002 end,'fixture@example.invalid'
from wave_fixture where key in ('exhibitor','later_exhibitor');
insert into public.show_sections(id,show_id,kind,letter)
select id,(select id from wave_fixture where key='show'),case when key='youth' then 'youth' else 'open' end,'A' from wave_fixture where key in ('section','youth');
insert into public.entries(id,show_id,section_id,exhibitor_id,species,breed,sex,class_name,tattoo)
select id,(select id from wave_fixture where key='show'),(select id from wave_fixture where key=case when f.key='rabbit1_youth' then 'youth' else 'section' end),
 (select id from wave_fixture where key=case when f.key='later_entry' then 'later_exhibitor' else 'exhibitor' end),
 case when key='cavy1' then 'cavy' else 'rabbit' end,
 case when key in ('rabbit2','later_entry') then 'Himalayan' else 'American' end,
 case when key='cavy1' then 'Boar' else 'Buck' end,'Senior','W-'||key
from wave_fixture f where key in ('rabbit1','rabbit1_youth','rabbit2','cavy1','later_entry');
create temporary table wave_payload as select
 jsonb_build_array(
   jsonb_build_object('id',(select id from wave_fixture where key='wave1'),'wave_number',1,
     'checkin_start_local',to_char((now()-interval '1 hour') at time zone 'America/Chicago','YYYY-MM-DD"T"HH24:MI:SS'),
     'checkin_end_local',to_char((now()+interval '1 hour') at time zone 'America/Chicago','YYYY-MM-DD"T"HH24:MI:SS'),
     'show_date',current_date+1,'checkout_date',current_date+2,'email_lead_hours',24),
   jsonb_build_object('id',(select id from wave_fixture where key='wave2'),'wave_number',2,
     'checkin_start_local',to_char((now()+interval '2 days') at time zone 'America/Chicago','YYYY-MM-DD"T"HH24:MI:SS'),
     'checkin_end_local',to_char((now()+interval '2 days 2 hours') at time zone 'America/Chicago','YYYY-MM-DD"T"HH24:MI:SS'),
     'show_date',current_date+2,'checkout_date',current_date+3,'email_lead_hours',24)
 ) waves,
 jsonb_build_array(
   jsonb_build_object('species','rabbit','breed_name','American','wave_id',(select id from wave_fixture where key='wave1')),
   jsonb_build_object('species','cavy','breed_name','American','wave_id',(select id from wave_fixture where key='wave1')),
   jsonb_build_object('species','rabbit','breed_name','Himalayan','wave_id',(select id from wave_fixture where key='wave2')),
   jsonb_build_object('species','rabbit','breed_name','Lionhead','wave_id',(select id from wave_fixture where key='wave1'))
 ) breeds;
grant select on wave_payload to authenticated;
select set_config('request.jwt.claims','{"sub":"3e8dddf9-3a17-4ebb-aeab-9b51d31e7871","role":"authenticated"}',true);
set local role authenticated;
select lives_ok($$select public.save_show_wave_schedule((select id from wave_fixture where key='show'),true,waves,breeds) from wave_payload$$,'selected secretary saves wave schedule');
select is((select count(*)::integer from jsonb_array_elements(public.get_show_wave_schedule((select id from wave_fixture where key='show'))->'breeds') b where (b->>'has_entries')::boolean),3,'entered breeds are distinct across Open and Youth with separate rabbit and cavy choices');
select ok(exists(select 1 from jsonb_array_elements(public.get_show_wave_schedule((select id from wave_fixture where key='show'))->'breeds') b where b->>'breed_name'='Lionhead' and not (b->>'has_entries')::boolean and b->>'wave_id' is not null),'saved assignments without entries remain available to preserve on save');
select is((public.get_show_wave_schedule((select id from wave_fixture where key='show'))->>'active_wave_id')::uuid,(select id from wave_fixture where key='wave1'),'active wave is resolved in show timezone');
select throws_ok($$select public.save_show_wave_schedule((select id from wave_fixture where key='other_show'),true,waves,breeds) from wave_payload$$,'42501','Wave Schedule is only available for selected secretaries’ shows.','allowlisted user cannot configure an unrelated show');
select throws_ok($$update public.show_waves set email_lead_hours=1$$,'42501',null,'direct table mutation cannot bypass restricted save RPC');
select throws_ok($$select public.save_show_wave_schedule((select id from wave_fixture where key='show'),true,jsonb_set(waves,'{1,checkin_start_local}',waves#>'{0,checkin_start_local}'),breeds) from wave_payload$$,'P0001','Wave check-in windows cannot overlap.','overlapping windows rejected');
select throws_ok($$select public.save_show_wave_schedule((select id from wave_fixture where key='show'),true,jsonb_set(waves,'{0,email_lead_hours}','4'),breeds) from wave_payload$$,'23514',null,'unsupported lead times rejected');
select throws_ok($$select public.save_show_wave_schedule((select id from wave_fixture where key='show'),true,waves,breeds-2) from wave_payload$$,'P0001','Assign every entered breed to a wave before enabling the schedule.','entered breeds cannot be left unassigned');
select is((select count(*)::integer from public.report_wave_checkin_entries((select id from wave_fixture where key='show'),(select id from wave_fixture where key='wave1'))),3,'wave one check-in report excludes later breeds');
select is((select count(*)::integer from public.report_wave_checkin_entries((select id from wave_fixture where key='show'),(select id from wave_fixture where key='wave2'))),2,'future wave sheet can be prepared with only its animals');
select is((select count(*)::integer from public.report_wave_checkin_entries((select id from wave_fixture where key='show'),(select id from wave_fixture where key='wave1'),false,null,(select id from wave_fixture where key='exhibitor'),array[(select id from wave_fixture where key='youth')])),1,'wave report preserves exhibitor and section scope');
reset role;
set local role service_role;
select is((select count(*)::integer from public.report_wave_checkin_entries((select id from wave_fixture where key='show'),(select id from wave_fixture where key='wave1'),false,null,(select id from wave_fixture where key='exhibitor'),array[(select id from wave_fixture where key='youth')])),1,'trusted report worker uses the same exact wave and section scope');
reset role;
select ok(not has_function_privilege('authenticated','public.begin_wave_checkin_email(uuid)','execute'),'ordinary users cannot trigger email preparation');
select is((select checkin_starts_at from public.show_waves where id=(select id from wave_fixture where key='wave1')),(select (waves#>>'{0,checkin_start_local}')::timestamp at time zone 'America/Chicago' from wave_payload),'local Chicago time is stored as the correct instant');
select is((select count(*)::integer from public.due_checkin_email_waves() where show_id=(select id from wave_fixture where key='show')),1,'only the due wave is scheduled for sheets');
select lives_ok($$insert into public.entries(show_id,section_id,exhibitor_id,species,breed,sex,class_name,tattoo)
select (select id from wave_fixture where key='show'),(select id from wave_fixture where key='youth'),(select id from wave_fixture where key='exhibitor'),'rabbit','Polish','Buck','Senior','UNASSIGNED'$$,
'new breeds can be entered after waves are enabled');
select ok(exists(select 1 from jsonb_array_elements(public.get_show_wave_schedule((select id from wave_fixture where key='show'))->'breeds') b where b->>'breed_name'='Polish' and (b->>'has_entries')::boolean),'a newly entered Youth-only breed appears for assignment across the full show');
select ok(not show_waves_private.entry_allowed((select id from wave_fixture where key='show'),'rabbit','Polish'),'new unassigned breed cannot check in');
select is((select count(*)::integer from public.report_wave_checkin_entries((select id from wave_fixture where key='show'),(select id from wave_fixture where key='wave1'))),3,'unassigned entries stay out of wave sheets');
delete from public.entries where show_id=(select id from wave_fixture where key='show') and tattoo='UNASSIGNED';
insert into wave_fixture(key) values('cart');
insert into public.entry_carts(id,user_id,show_id,status,payment_status,subtotal_cents,total_cents,currency)
select (select id from wave_fixture where key='cart'),(select id from wave_fixture where key='other'),(select id from wave_fixture where key='show'),'active','unpaid',0,0,'usd';
select lives_ok($$insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,breed,sex,class_name,tattoo)
select (select id from wave_fixture where key='cart'),(select id from wave_fixture where key='section'),(select id from wave_fixture where key='exhibitor'),'rabbit','Mini Rex','Buck','Senior','CART-UNASSIGNED'$$,
'new breeds can be added to carts before they have been entered');
select ok(not exists(select 1 from jsonb_array_elements(public.get_show_wave_schedule((select id from wave_fixture where key='show'))->'breeds') b where b->>'breed_name'='Mini Rex'),'cart-only and catalog-only breeds are excluded');
set local role authenticated;
select lives_ok($$select public.save_show_wave_schedule((select id from wave_fixture where key='show'),true,waves,breeds) from wave_payload$$,'unentered saved carts do not block enabling the schedule');
reset role;
select lives_ok($$insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,breed,sex,class_name,tattoo)
select (select id from wave_fixture where key='cart'),(select id from wave_fixture where key='section'),(select id from wave_fixture where key='exhibitor'),'rabbit','American','Buck','Senior','CART-ASSIGNED'$$,
'assigned breeds can still be added to carts');
select lives_ok($$insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,is_checkin_fee_carrier)
select (select id from wave_fixture where key='cart'),(select id from wave_fixture where key='section'),(select id from wave_fixture where key='exhibitor'),'rabbit','CHECKIN-FEE',true$$,
'check-in fee carriers do not require a breed wave');
select is((select count(*)::integer from public.begin_wave_checkin_email((select id from wave_fixture where key='wave2'))),0,'future wave preparation is not started early');
select is((select count(*)::integer from public.begin_wave_checkin_email((select id from wave_fixture where key='wave1'))),1,'due wave preparation begins before reading animals');
set local role authenticated;
select throws_ok($$select public.save_show_wave_schedule((select id from wave_fixture where key='show'),true,waves,jsonb_set(breeds,'{0,wave_id}',breeds#>'{2,wave_id}')) from wave_payload$$,
'P0001','Breed assignments cannot change after wave sheets have been prepared or check-in has begun.','email preparation freezes existing assignments');
reset role;
insert into public.show_checkin_settings(show_id,is_enabled,portal_token_hash,entry_edit_permissions)
values((select id from wave_fixture where key='show'),true,encode(extensions.digest('wave-fixture-token','sha256'),'hex'),'{"breed":"automatic","ear_number":"automatic","add_entry":"automatic"}');
create temporary table wave_session as select public.authenticate_exhibitor_checkin('wave-fixture-token','991001','Tester') value;
grant select on wave_session to anon;
select is((select wave_id from public.show_checkin_sessions where show_id=(select id from wave_fixture where key='show')),(select id from wave_fixture where key='wave1'),'session is pinned to its wave');
set local role anon;
select is(jsonb_array_length(public.get_exhibitor_checkin_portal_data((select value->>'session_token' from wave_session))->'entries'),3,'portal includes only active-wave rabbits and cavies across Open and Youth');
select throws_ok($$select public.authenticate_exhibitor_checkin('wave-fixture-token','991002','Tester')$$,'P0001','We could not verify those check-in details','exhibitor with only later-wave breeds cannot enter active check-in');
select throws_ok($$select public.submit_exhibitor_checkin_change_request((select value->>'session_token' from wave_session),(select id from wave_fixture where key='rabbit2'),'entry_edit','{"ear_number":"BYPASS"}')$$,'42501','This animal is not in the active check-in wave.','direct API edit cannot access another wave');
select throws_ok($$select public.submit_exhibitor_checkin_change_request((select value->>'session_token' from wave_session),(select id from wave_fixture where key='rabbit1'),'entry_edit','{"breed":"Himalayan"}')$$,'42501','Choose a breed assigned to the active check-in wave.','breed changes cannot move into a later wave');
select throws_ok($$select public.submit_exhibitor_checkin_add_entry((select value->>'session_token' from wave_session),'{"species":"rabbit","breed":"Himalayan"}')$$,'42501','Choose a breed assigned to the active check-in wave.','add entry API cannot bypass wave restrictions');
select lives_ok($$select public.complete_exhibitor_checkin((select value->>'session_token' from wave_session),true)$$,'active wave can complete check-in');
reset role;
select is((select count(*)::integer from public.show_checkin_records where show_id=(select id from wave_fixture where key='show') and status='completed' and wave_id=(select id from wave_fixture where key='wave1')),1,'completion belongs to wave one');
update public.show_waves set checkin_starts_at=now()-interval '4 hours',checkin_ends_at=now()-interval '3 hours' where id=(select id from wave_fixture where key='wave1');
update public.show_waves set checkin_starts_at=now()-interval '1 hour',checkin_ends_at=now()+interval '1 hour' where id=(select id from wave_fixture where key='wave2');
set local role anon;
select throws_ok($$select public.complete_exhibitor_checkin((select value->>'session_token' from wave_session),true)$$,'42501','This wave is not currently open for check-in.','old session cannot cross into a new wave');
reset role;
update wave_session set value=public.authenticate_exhibitor_checkin('wave-fixture-token','991001','Tester');
set local role anon;
select is(jsonb_array_length(public.get_exhibitor_checkin_portal_data((select value->>'session_token' from wave_session))->'entries'),1,'later wave reveals only its assigned breed');
select is(public.get_exhibitor_checkin_portal_data((select value->>'session_token' from wave_session))#>>'{checkin,status}','in_progress','wave one completion does not check in wave two');
select lives_ok($$select public.complete_exhibitor_checkin((select value->>'session_token' from wave_session),true)$$,'same exhibitor can complete later wave');
reset role;
select is((select count(*)::integer from public.show_checkin_records where show_id=(select id from wave_fixture where key='show') and status='completed'),2,'two waves retain separate completion records');
insert into public.auto_checkin_email_deliveries(show_id,exhibitor_id,wave_id,status)
select (select id from wave_fixture where key='show'),(select id from wave_fixture where key='exhibitor'),id,'sent' from wave_fixture where key in ('wave1','wave2');
select is((select count(*)::integer from public.auto_checkin_email_deliveries where show_id=(select id from wave_fixture where key='show')),2,'same exhibitor can have one delivery per wave');
select throws_ok($$insert into public.auto_checkin_email_deliveries(show_id,exhibitor_id,wave_id,status) select (select id from wave_fixture where key='show'),(select id from wave_fixture where key='exhibitor'),id,'sent' from wave_fixture where key='wave1'$$,'23505',null,'duplicate delivery in same wave is rejected');

insert into public.show_checkin_settings(show_id,is_enabled,portal_token_hash)
values((select id from wave_fixture where key='other_show'),true,encode(extensions.digest('legacy-wave-test','sha256'),'hex'));
insert into public.show_sections(id,show_id,kind,letter) values(gen_random_uuid(),(select id from wave_fixture where key='other_show'),'open','A');
insert into public.entries(show_id,section_id,exhibitor_id,species,breed,sex,class_name,tattoo)
select (select id from wave_fixture where key='other_show'),id,(select id from wave_fixture where key='exhibitor'),'rabbit','American','Buck','Senior','LEGACY'
from public.show_sections where show_id=(select id from wave_fixture where key='other_show');
update wave_session set value=public.authenticate_exhibitor_checkin('legacy-wave-test','991001','Tester');
set local role anon;
select is(jsonb_array_length(public.get_exhibitor_checkin_portal_data((select value->>'session_token' from wave_session))->'entries'),1,'show without waves retains all its entries');
select lives_ok($$select public.complete_exhibitor_checkin((select value->>'session_token' from wave_session),true)$$,'ordinary show still completes check-in');
reset role;
select is((select count(*)::integer from public.show_checkin_records where show_id=(select id from wave_fixture where key='other_show') and wave_id is null and status='completed'),1,'ordinary show retains legacy completion scope');
update public.show_waves set checkin_ends_at=now() where id=(select id from wave_fixture where key='wave2');
select is(show_waves_private.active_wave((select id from wave_fixture where key='show')),null::uuid,'check-in closes exactly at the end of the wave window');
select * from finish();
rollback;
