-- Synthetic registrations and mocked payment completion; always rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table addon_fixture(k text primary key,id uuid default gen_random_uuid());
insert into addon_fixture(k) values('secretary'),('buyer'),('other'),('show'),('section'),('ex'),('other_ex'),('cart'),('later_cart'),('free_cart'),('contest'),('extra'),('free');
grant select on addon_fixture to authenticated;
create function pg_temp.fx(k text) returns uuid language sql as $$select id from addon_fixture where addon_fixture.k=$1$$;
create function pg_temp.actor(k text, service boolean default false) returns void language plpgsql as $$begin
  perform set_config('request.jwt.claim.sub',pg_temp.fx(k)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fx(k),'role',case when service then 'service_role' else 'authenticated' end)::text,true);
end;$$;
create function pg_temp.expect_error(statement text, fragment text) returns void language plpgsql as $$begin
  begin execute statement; exception when others then
    if position(lower(fragment) in lower(sqlerrm))>0 then return; end if;
    raise exception 'Unexpected error: %',sqlerrm;
  end;
  raise exception 'Expected error: %',fragment;
end;$$;
create function pg_temp.check_true(v boolean,message text) returns void language plpgsql as $$begin
  if v is distinct from true then raise exception 'Assertion failed: %',message; end if;
end;$$;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',k||'-'||id||'@example.invalid','{}','{}' from addon_fixture where k in ('secretary','buyer','other');
insert into shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test,entry_close_at,payment_timing_mode,online_payment_fee_mode)
values(pg_temp.fx('show'),pg_temp.fx('secretary'),pg_temp.fx('secretary'),'Expansion fixture',current_date,current_date+2,true,true,now()+interval '1 day','online_or_at_show','club_absorbs');
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
values(pg_temp.fx('ex'),'Contest Exhibitor',pg_temp.fx('buyer'),996711,'contest@example.invalid',true,true),
 (pg_temp.fx('other_ex'),'Other Exhibitor',pg_temp.fx('other'),996712,'other@example.invalid',true,true);
insert into show_sections(id,show_id,kind,letter,display_name,sort_order) values(pg_temp.fx('section'),pg_temp.fx('show'),'open','A','Open A',1);
insert into show_fee_settings(show_id,currency) values(pg_temp.fx('show'),'USD');
insert into show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee) values(pg_temp.fx('section'),10,0,3)
on conflict(section_id) do update set fee_per_entry=10,fee_per_show=0,fur_fee=3;
insert into entry_carts(id,user_id,show_id) select id,pg_temp.fx('buyer'),pg_temp.fx('show') from addon_fixture where k in ('cart','later_cart','free_cart');
insert into show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider) values(pg_temp.fx('show'),true,false,false,'stripe');
insert into show_payment_account_links(show_id,provider,status,account_status,charges_enabled,stripe_account_id,provider_account_id)
values(pg_temp.fx('show'),'stripe','active','ready',true,'acct_contest_fixture','acct_contest_fixture');


insert into addon_fixture(k) values('project'),('team'),('age'),('session'),('animal'),('r1'),('r2'),('r3'),('r4'),('team1'),('team2'),('other_cart'),('draft');
insert into entry_carts(id,user_id,show_id) values(pg_temp.fx('other_cart'),pg_temp.fx('other'),pg_temp.fx('show'));
select pg_temp.actor('secretary');
set local role authenticated;
select set_show_addons_enabled(pg_temp.fx('show'),'contest',true);
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('project'),'kind','contest','price_cents',0,'name','Projects','max_per_exhibitor',4,'contest_config','{"entry_type":"project","categories":["Art","Photo"],"category_limit":2,"max_awarded_per_exhibitor":1,"awards":[{"name":"Champion","recipients":1,"scope":"contest"}]}'::jsonb))$$,'multiple projects and category/award limits configured');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('team'),'kind','contest','price_cents',0,'name','Team Judging','max_per_exhibitor',2,'contest_config','{"entry_type":"team","team_min":2,"team_max":3,"team_alternates":1}'::jsonb))$$,'team rules configured');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('age'),'kind','contest','price_cents',0,'name','Royalty','divisions','["Junior","Senior"]'::jsonb,'contest_config','{"age_as_of":"custom","age_date":"2026-09-16","age_rules":[{"division":"Junior","min":5,"max":10},{"division":"Senior","min":11,"max":18}]}'::jsonb))$$,'custom cutoff and age divisions configured');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('session'),'kind','contest','price_cents',0,'name','Two-day contest','contest_config','{"sessions":[{"id":"one","name":"Day 1","starts_at":"2030-01-01T12:00:00Z","ends_at":"2030-01-01T14:00:00Z","capacity":1},{"id":"two","name":"Day 2","starts_at":"2030-01-02T12:00:00Z","ends_at":"2030-01-02T14:00:00Z","capacity":1}]}'::jsonb))$$,'session capacity configured separately from entrant limit');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('animal'),'kind','contest','price_cents',0,'name','Breeder','animal_selection','required','contest_config','{"animal_sources":["own","provided"],"animal_roles":["Parent","Offspring"]}'::jsonb))$$,'multiple animal roles can be independent of show entry');
select pg_temp.actor('buyer');
select lives_ok($$select save_contest_draft(pg_temp.fx('cart'),pg_temp.fx('project'),pg_temp.fx('ex'),pg_temp.fx('draft'),'{"registration_data":{"category":"Art"}}')$$,'incomplete application can be saved privately');
select is(jsonb_array_length(get_contest_drafts(pg_temp.fx('cart'))),1,'draft can be resumed');
select is(jsonb_array_length(get_cart_addons(pg_temp.fx('cart'))),0,'draft does not create a charge or registration');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('project'),pg_temp.fx('other_ex'),1,'{}',null,null,'{"category":"Art","project_title":"Wrong owner"}',pg_temp.fx('r1'))$$,'42501','Choose an active exhibitor from this household.','new registration endpoint enforces household ownership');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('project'),pg_temp.fx('ex'),1,'{}',null,null,'{"category":"Art","project_title":"First"}',pg_temp.fx('draft'))$$,'draft becomes complete project registration');
select is(jsonb_array_length(get_contest_drafts(pg_temp.fx('cart'))),0,'converted draft removed');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('project'),pg_temp.fx('ex'),1,'{}',null,null,'{"category":"Art","project_title":"Second"}',pg_temp.fx('r2'))$$,'second distinct project keeps its own identity');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('project'),pg_temp.fx('ex'),1,'{}',null,null,'{"category":"Art","project_title":"Second edited"}',pg_temp.fx('r2'))$$,'editing a specific project is idempotent');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('project'),pg_temp.fx('ex'),1,'{}',null,null,'{"category":"Art","project_title":"Third"}',pg_temp.fx('r3'))$$,'P0001','The entry limit for this category has been reached.','category limit enforced');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('project'),pg_temp.fx('ex'),1,'{}',null,null,'{"category":"Photo","project_title":"Photo one"}',pg_temp.fx('r3'))$$,'different category remains available');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('team'),pg_temp.fx('ex'),1,'{}',null,null,'{"team":{"name":"Team A","authorized":true,"members":[{"name":"A","birthdate":"2015-01-01"}]}}',pg_temp.fx('team1'))$$,'P0001','The roster does not meet the contest team size.','team minimum enforced');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('team'),pg_temp.fx('ex'),1,'{}',null,null,'{"team":{"name":"Team A","authorized":true,"members":[{"name":"A","birthdate":"2015-01-01"},{"name":"B","birthdate":"2014-01-01"}]}}',pg_temp.fx('team1'))$$,'coordinator registers whole team once');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('team'),pg_temp.fx('ex'),1,'{}',null,null,'{"team":{"name":"Team B","authorized":true,"members":[{"name":"A","birthdate":"2015-01-01"},{"name":"C","birthdate":"2014-01-01"}]}}',pg_temp.fx('team2'))$$,'P0001','A member is already registered on another team in this contest.','team member cannot be entered twice');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('age'),pg_temp.fx('ex'),1,'{}','Junior',null,'{"birthdate":"2015-09-16"}')$$,'P0001','The selected division does not match the age requirements.','birthday exactly on cutoff uses new age');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('age'),pg_temp.fx('ex'),1,'{}','Senior',null,'{"birthdate":"2015-09-16"}')$$,'valid division accepted at birthday boundary');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('session'),pg_temp.fx('ex'),1,'{}',null,null,'{"session_id":"one"}')$$,'one session chosen');
select throws_ok($$select save_contest_registration(pg_temp.fx('later_cart'),pg_temp.fx('session'),pg_temp.fx('ex'),1,'{}',null,null,'{"session_id":"two"}')$$,'P0001','The limit for Two-day contest is 1 per exhibitor across the full show.','person limit spans sessions and carts');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('animal'),pg_temp.fx('ex'),1,'{}',null,null,'{"animals":[{"role":"Parent","source":"own","label":"D1"},{"role":"Offspring","source":"provided"}]}')$$,'P0001','Describe the animal you will bring.','own animal requires species');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('animal'),pg_temp.fx('ex'),1,'{}',null,null,'{"animals":[{"role":"Parent","source":"own","species":"rabbit","label":"D1"},{"role":"Offspring","source":"provided"}]}')$$,'own and organizer animals supported without animal show entries');
select lives_ok($$select commit_free_addon_cart(pg_temp.fx('cart'))$$,'expanded registrations complete existing free checkout');
select pg_temp.actor('other');
select throws_ok($$select get_contest_drafts(pg_temp.fx('cart'))$$,'42501','You do not have access to this cart.','drafts remain private');
select throws_ok($$select save_contest_registration(pg_temp.fx('other_cart'),pg_temp.fx('session'),pg_temp.fx('other_ex'),1,'{}',null,null,'{"session_id":"one"}')$$,'P0001','This contest session has reached its capacity.','completed entry holds session capacity');
select lives_ok($$select save_contest_registration(pg_temp.fx('other_cart'),pg_temp.fx('project'),pg_temp.fx('other_ex'),1,'{}',null,null,'{"category":"Art","project_title":"Other"}',pg_temp.fx('r4'))$$,'another household registers a project');
select commit_free_addon_cart(pg_temp.fx('other_cart'));
select throws_ok($$select update_contest_registration(pg_temp.fx('draft'),'{"checked_in":true}')$$,'42501','Only show secretaries and administrators can manage contests and add-ons.','exhibitor cannot check in or change results');
select pg_temp.actor('secretary');
select lives_ok($$select update_contest_registration(pg_temp.fx('draft'),'{"checked_in":true}')$$,'secretary checks in project independently of payment');
select lives_ok($$select update_contest_registration(pg_temp.fx('draft'),'{"result":{"status":"recorded","place":1,"awards":["Champion"]}}')$$,'secretary records placing and named award together');
select throws_ok($$select update_contest_registration(pg_temp.fx('r4'),'{"result":{"status":"recorded","place":1,"awards":[]}}')$$,'P0001','That place is already assigned in this division/category/session.','duplicate place prevented');
select throws_ok($$select update_contest_registration(pg_temp.fx('r4'),'{"result":{"status":"recorded","place":2,"awards":["Champion"]}}')$$,'P0001','The recipient limit for award Champion has been reached.','unique overall award protected');
select throws_ok($$select update_contest_registration(pg_temp.fx('r2'),'{"result":{"status":"recorded","place":2,"awards":[]}}')$$,'P0001','This exhibitor has reached the award limit in this category.','entry limits and award limits remain distinct');
select throws_ok($$select publish_contest_results(pg_temp.fx('project'),true)$$,'P0001','Record a result status for every accepted registration before publishing.','publishing cannot silently turn unrecorded entries into unplaced');
select pg_temp.actor('buyer');
select is((select value->'result' from jsonb_array_elements(get_show_addon_registrations(null,pg_temp.fx('buyer'))) where value->>'id'=pg_temp.fx('draft')::text),'null'::jsonb,'own draft results hidden');
select is(jsonb_array_length(get_contest_results(pg_temp.fx('show'))),0,'unpublished results excluded from shared results');
select pg_temp.actor('secretary');
select update_contest_registration(pg_temp.fx('r2'),'{"result":{"status":"recorded","awards":[]}}');
select update_contest_registration(pg_temp.fx('r3'),'{"result":{"status":"absent","awards":[]}}');
select update_contest_registration(pg_temp.fx('r4'),'{"result":{"status":"recorded","place":2,"awards":[]}}');
select lives_ok($$select publish_contest_results(pg_temp.fx('project'),true)$$,'reviewed results publish');
select throws_ok($$select update_contest_registration(pg_temp.fx('draft'),'{"result":{"status":"recorded","place":3,"awards":[]}}','correction')$$,'P0001','Reopen published results before making corrections.','published results immutable until reopened');
select lives_ok($$select update_contest_registration(pg_temp.fx('draft'),'{"checked_in":false}')$$,'check-in can be corrected without changing published results');
select pg_temp.actor('buyer');
select is((select value#>>'{result,place}' from jsonb_array_elements(get_show_addon_registrations(null,pg_temp.fx('buyer'))) where value->>'id'=pg_temp.fx('draft')::text),'1','published placing visible to exhibitor');
select ok(not exists(select 1 from jsonb_array_elements(get_contest_results(pg_temp.fx('show'))) r where r ?| array['email','answers','birthdate','config_snapshot','registration_data']),'shared results exclude private registration data');
select pg_temp.actor('secretary');
select throws_ok($$select publish_contest_results(pg_temp.fx('project'),false)$$,'P0001','Enter a reason to reopen results.','reopening requires reason');
select lives_ok($$select publish_contest_results(pg_temp.fx('project'),false,'Judge correction')$$,'secretary can reopen with reason');
select throws_ok($$select update_contest_registration(pg_temp.fx('draft'),'{"result":{"status":"recorded","place":3,"awards":[]}}')$$,'P0001','Enter a reason for the result correction.','individual correction reason required');
select lives_ok($$select update_contest_registration(pg_temp.fx('draft'),'{"result":{"status":"recorded","place":3,"awards":[]}}','Wrong place transcribed')$$,'result correction audited');
select ok(jsonb_array_length(get_contest_history(pg_temp.fx('project')))>6,'operation and publication history preserved');
reset role;
select ok(not has_table_privilege('authenticated','show_addons_private.contest_operations','SELECT'),'result tables are private');
select ok(not has_function_privilege('authenticated','show_addons_private.validate_registration_limits(public.entry_carts,show_addons_private.offerings,uuid,integer,jsonb,uuid)','EXECUTE'),'internal capacity helper not exposed');

-- Field dependency, upload, storage, and walk-up regression cases.
insert into addon_fixture(k) values('walk'),('walk_request'),('documents'),('doc_cart'),('doc_id'),('doc_staff');
insert into entry_carts(id,user_id,show_id) values(pg_temp.fx('doc_cart'),pg_temp.fx('buyer'),pg_temp.fx('show'));
select pg_temp.actor('secretary');
select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('walk'),'kind','contest','name','Walk-up','price_cents',725,'use_show_entry_dates',false,'registration_open_at',now()-interval '2 days','registration_close_at',now()-interval '1 day','contest_config','{"allow_walkup":true}'::jsonb));
select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('documents'),'kind','contest','name','Applications','price_cents',0,'max_per_exhibitor',2,'divisions','["Junior","Senior"]'::jsonb,'fields','[{"id":"file","label":"Application","type":"file","required":true,"only_division":"Senior"},{"id":"choice","label":"Choice","type":"multi_select","required":true,"options":["A","B"]}]'::jsonb));
set local role authenticated;
select lives_ok($$select get_contest_walkup_exhibitor(pg_temp.fx('walk'),996711)$$,'secretary finds exact exhibitor number for walk-up');
select lives_ok($$select register_contest_walkup(pg_temp.fx('walk'),pg_temp.fx('ex'),pg_temp.fx('walk_request'),'{}')$$,'walk-up can be entered after online registration closes');
select lives_ok($$select register_contest_walkup(pg_temp.fx('walk'),pg_temp.fx('ex'),pg_temp.fx('walk_request'),'{}')$$,'walk-up request replay is idempotent');
reset role;
select is((select balance_due_cents from show_exhibitor_balances where entry_cart_id=pg_temp.fx('walk_request')),725,'walk-up fee is an unpaid balance');
select is((select count(*)::integer from entries where source_cart_id=pg_temp.fx('walk_request')),0,'walk-up creates no fake animal');
select pg_temp.actor('buyer');
set local role authenticated;
select throws_ok($$select register_contest_walkup(pg_temp.fx('walk'),pg_temp.fx('ex'),gen_random_uuid(),'{}')$$,'42501','Only show secretaries and administrators can manage contests and add-ons.','exhibitor cannot invoke walk-up deadline override');
select lives_ok($$select save_contest_registration(pg_temp.fx('doc_cart'),pg_temp.fx('documents'),pg_temp.fx('ex'),1,'{"choice":["A","B"]}','Junior',null,'{}',pg_temp.fx('doc_id'))$$,'conditional file not required in unrelated division');
select throws_ok($$select save_contest_registration(pg_temp.fx('doc_cart'),pg_temp.fx('documents'),pg_temp.fx('ex'),1,'{"choice":["A"]}','Senior',null,'{}',pg_temp.fx('doc_id'))$$,'P0001','Application is required.','conditional file becomes required in configured division');
select throws_ok($$select save_contest_registration(pg_temp.fx('doc_cart'),pg_temp.fx('documents'),pg_temp.fx('ex'),1,'{"choice":["X"]}','Junior',null,'{}',pg_temp.fx('doc_id'))$$,'P0001','Choose valid options for Choice.','multi-select choices validated');
reset role;
insert into storage.objects(bucket_id,name) values('contest-submissions',pg_temp.fx('documents')||'/'||pg_temp.fx('buyer')||'/00000000-0000-0000-0000-000000000001.pdf');
-- Simulate a broad old policy and verify the new restrictive guard still wins.
create policy fixture_public_storage on storage.objects for select to authenticated using(true);
select pg_temp.actor('other');
set local role authenticated;
select is((select count(*)::integer from storage.objects where bucket_id='contest-submissions'),0,'private upload hidden even with a broad legacy storage policy');
select pg_temp.actor('secretary');
select is((select count(*)::integer from storage.objects where bucket_id='contest-submissions'),0,'unsubmitted private application not exposed to secretary');
select pg_temp.actor('buyer');
select is((select count(*)::integer from storage.objects where bucket_id='contest-submissions'),1,'uploader can read their file');
select lives_ok($$select save_contest_registration(pg_temp.fx('doc_cart'),pg_temp.fx('documents'),pg_temp.fx('ex'),1,jsonb_build_object('choice','["A"]'::jsonb,'file',jsonb_build_object('path',pg_temp.fx('documents')||'/'||pg_temp.fx('buyer')||'/00000000-0000-0000-0000-000000000001.pdf','name','Application.pdf')),'Senior',null,'{}',pg_temp.fx('doc_id'))$$,'file is verified and attached to registration');
select commit_free_addon_cart(pg_temp.fx('doc_cart'));
select pg_temp.actor('secretary');
select is((select count(*)::integer from storage.objects where bucket_id='contest-submissions'),1,'secretary can review submitted attachment');
select pg_temp.actor('other');
select is((select count(*)::integer from storage.objects where bucket_id='contest-submissions'),0,'submitted attachment still hidden from another household');
reset role;
select * from finish();
rollback;
