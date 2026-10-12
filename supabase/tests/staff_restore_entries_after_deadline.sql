begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table restore_fixture(key text primary key,id uuid default gen_random_uuid());
insert into restore_fixture(key) values('owner'),('secretary'),('exhibitor'),('stranger'),('superadmin'),('show'),('section'),('entry');
insert into auth.users(id,email,email_confirmed_at)
select id,id::text||'@example.invalid',now() from restore_fixture where key in ('owner','secretary','exhibitor','stranger','superadmin');
insert into public.shows(id,name,owner_user_id,created_by,start_date,end_date,entry_close_at)
select id,'Restore deadline test',(select id from restore_fixture where key='owner'),(select id from restore_fixture where key='owner'),current_date-2,current_date-2,now()-interval '3 days'
from restore_fixture where key='show';
insert into public.role_assignments(user_id,show_id,role)
select (select id from restore_fixture where key='secretary'),id,'admin' from restore_fixture where key='show';
insert into public.super_admins(user_id) select id from restore_fixture where key='superadmin';
insert into public.show_sections(id,show_id,kind,letter,judging_date)
select id,(select id from restore_fixture where key='show'),'open','A',current_date-2 from restore_fixture where key='section';
insert into public.entries(id,show_id,section_id,exhibitor_user_id,species,breed,variety,sex,class_name,status,scratched_at)
select id,(select id from restore_fixture where key='show'),(select id from restore_fixture where key='section'),(select id from restore_fixture where key='exhibitor'), 'rabbit','Rex','Black','Buck','Senior','scratched',now() from restore_fixture where key='entry';
grant select on restore_fixture to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from restore_fixture where key='exhibitor'),true);
set local role authenticated;
select throws_ok($$select public.set_entry_scratch_state((select id from restore_fixture where key='entry'),false)$$,'22023','Entry deadline passed. Scratched entries can no longer be restored.','exhibitor cannot restore after deadline');
reset role;
select set_config('request.jwt.claim.sub',(select id::text from restore_fixture where key='stranger'),true);
set local role authenticated;
select throws_ok($$select public.set_entry_scratch_state((select id from restore_fixture where key='entry'),false)$$,'42501','You do not have permission to update this entry','unrelated user denied');
reset role;
select set_config('request.jwt.claim.sub',(select id::text from restore_fixture where key='secretary'),true);
set local role authenticated;
select lives_ok($$select public.set_entry_scratch_state((select id from restore_fixture where key='entry'),false)$$,'assigned secretary restores after show');
reset role;
select ok((select scratched_at is null and status='entered' from public.entries where id=(select id from restore_fixture where key='entry')),'scratch status restored consistently');
select ok(exists(select 1 from public.show_checkin_audit_events where show_id=(select id from restore_fixture where key='show') and event_type='entry_restored' and actor_type='secretary' and actor_user_id=(select id from restore_fixture where key='secretary')),'restore is audited');
select set_config('request.jwt.claim.sub',(select id::text from restore_fixture where key='owner'),true);
set local role authenticated;
select lives_ok($$select public.set_entry_scratch_state((select id from restore_fixture where key='entry'),false)$$,'owner restores after show');
reset role;
select set_config('request.jwt.claim.sub',(select id::text from restore_fixture where key='superadmin'),true);
set local role authenticated;
select lives_ok($$select public.set_entry_scratch_state((select id from restore_fixture where key='entry'),false)$$,'superadmin restores after show');
reset role;
update public.shows set is_locked=true where id=(select id from restore_fixture where key='show');
set local role authenticated;
select throws_ok($$select public.set_entry_scratch_state((select id from restore_fixture where key='entry'),false)$$,'55000','Show is locked. Changes are not allowed.','explicit show lock still enforced');
reset role;
update public.shows set is_locked=false,entry_close_at=now()+interval '1 day' where id=(select id from restore_fixture where key='show');
select set_config('request.jwt.claim.sub',(select id::text from restore_fixture where key='exhibitor'),true);
set local role authenticated;
select lives_ok($$select public.set_entry_scratch_state((select id from restore_fixture where key='entry'),false)$$,'exhibitor can restore before deadline');
reset role;
select * from finish();
rollback;
