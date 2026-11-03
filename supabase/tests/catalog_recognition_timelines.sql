begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table recognition_fixture(key text primary key,id uuid default gen_random_uuid());
insert into recognition_fixture(key) values ('show'),('nov'),('dec'),('early'),('late'),('retired'),('cavy');
insert into public.catalog_recognition_history(species,breed_name,variety_name,status,effective_date,source_note) values
 ('rabbit','Recognition Fixture','Blue (COD)','cod','2026-01-01','test'),
 ('rabbit','Recognition Fixture','Blue (COD)','recognized','2026-12-01','test'),
 ('rabbit','Recognition Fixture','Blue (COD)','retired','2028-01-01','test');
select is(public.catalog_recognition_status('rabbit','Recognition Fixture','Blue (COD)','2026-11-30'),'cod','COD before recognition');
select is(public.catalog_recognition_status('rabbit','Recognition Fixture','blue','2026-11-30'),'cod','unmarked alias cannot bypass COD');
select is(public.catalog_recognition_status('rabbit','Recognition Fixture','Blue (COD)','2026-12-01'),'recognized','recognition starts on effective day');
select is(public.catalog_recognition_status('rabbit','Recognition Fixture','Blue','2027-12-31'),'recognized','recognized until retirement');
select is(public.catalog_recognition_status('rabbit','Recognition Fixture','Blue','2028-01-01'),'retired','retirement starts on effective day');
select is(public.catalog_recognition_status('rabbit','Recognition Fixture','Black','2026-11-30'),'recognized','unrelated varieties unchanged');
select is(public.catalog_recognition_status('cavy','Recognition Fixture','Blue','2026-11-30'),'recognized','species isolated');
select is(public.catalog_recognition_status('rabbit','Recognition Fixture','Blue',null),'unrecognized','missing date fails closed');
select throws_ok($$insert into public.catalog_recognition_history(species,breed_name,variety_name,status,effective_date) values ('rabbit','Recognition Fixture','BLUE','retired','2026-12-01')$$,'23505',null,'duplicate canonical date blocked');
insert into public.catalog_recognition_history(species,breed_name,status,effective_date) values ('rabbit','Parent (COD)','cod','2026-01-01');
insert into public.catalog_recognition_history(species,breed_name,variety_name,status,effective_date) values ('rabbit','Parent (COD)','Solid','recognized','2026-01-01');
select is(public.catalog_recognition_status('rabbit','Parent','Solid','2026-12-01'),'cod','recognized variety cannot override COD breed');
insert into public.catalog_recognition_history(species,breed_name,status,effective_date) values ('rabbit','Parent (COD)','recognized','2026-12-01');
select is(public.catalog_recognition_status('rabbit','Parent (COD)','Solid','2026-12-01'),'recognized','recognized breed overrides its old marker');
insert into public.shows(id,name,start_date,end_date,created_by,owner_user_id) select id,'Recognition local test','2026-11-30','2028-01-01',
 (select owner_user_id from public.shows where owner_user_id is not null limit 1),(select owner_user_id from public.shows where owner_user_id is not null limit 1)
 from recognition_fixture where key='show';
insert into public.show_sections(id,show_id,kind,letter,judging_date) select id,(select id from recognition_fixture where key='show'),'open',case when key='nov' then 'A' else 'B' end,
 case when key='nov' then '2026-11-30'::date else '2026-12-01'::date end from recognition_fixture where key in ('nov','dec');
insert into public.entries(id,show_id,section_id,species,breed,variety,sex,class_name,placement,result_status,judged_by_show_judge_id)
 select id,(select id from recognition_fixture where key='show'),(select id from recognition_fixture where key=case when f.key='early' then 'nov' else 'dec' end),
 'rabbit','Recognition Fixture','Blue (COD)','Doe','Senior','1','Shown',gen_random_uuid() from recognition_fixture f where key in ('early','late');
set constraints all immediate;
select is(public.entry_recognition_status((select id from recognition_fixture where key='early')),'cod','November section stays COD');
select is(public.entry_recognition_status((select id from recognition_fixture where key='late')),'recognized','December section uses recognition not show start');
select throws_ok($$insert into public.entry_awards(show_id,entry_id,award_code) values ((select id from recognition_fixture where key='show'),(select id from recognition_fixture where key='early'),'BOB')$$,
 '23514','COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.','COD BOB blocked at database boundary');
select lives_ok($$insert into public.entry_awards(show_id,entry_id,award_code) values ((select id from recognition_fixture where key='show'),(select id from recognition_fixture where key='early'),'BOSV')$$,'COD BOSV remains allowed');
select lives_ok($$insert into public.entry_awards(show_id,entry_id,award_code) values ((select id from recognition_fixture where key='show'),(select id from recognition_fixture where key='late'),'BOB')$$,'recognized BOB saves despite COD label');
select throws_ok($$insert into public.catalog_recognition_history(species,breed_name,variety_name,status,effective_date) values ('rabbit','Recognition Fixture','Blue','retired','2026-11-15')$$,
 '23514','This effective date overlaps judged entries. Historical results require a separate review.','backdating across judged results blocked');
select throws_ok($$delete from public.catalog_recognition_history where breed_name='Recognition Fixture' and effective_date='2026-01-01'$$,
 '23514','Effective status history cannot be deleted. Add a new dated transition.','effective history cannot be deleted');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select r->>'recognition_status' from public.report_results_entry_rows_dated_page((select id from recognition_fixture where key='show'),p_entry_ids=>array[(select id from recognition_fixture where key='late')]) r),'recognized','paged reports include dated status');
select is((select r->>'recognition_status' from public.get_judging_entry_rows_page((select id from recognition_fixture where key='show'),p_entry_ids=>array[(select id from recognition_fixture where key='early')]) r),'cod','judging reader includes dated status');
select ok(public.get_report_result_revision_scoped((select id from recognition_fixture where key='show'),null) like '%:recognition:%','snapshot revisions include catalog changes');
-- Move an unjudged section into retirement: new entry is rejected server-side.
insert into public.show_sections(id,show_id,kind,letter,judging_date) select id,(select id from recognition_fixture where key='show'),'open','C','2028-01-01' from recognition_fixture where key='retired';
select throws_ok($$insert into public.entries(show_id,section_id,species,breed,variety,sex,class_name) values ((select id from recognition_fixture where key='show'),(select id from recognition_fixture where key='retired'),'rabbit','Recognition Fixture','Blue','Doe','Senior')$$,
 '23514','This breed or variety is not eligible on the section judging date.','retired new entries blocked');
select ok(not has_table_privilege('anon','public.catalog_recognition_history','SELECT'),'anonymous cannot read timelines');
select ok(not has_table_privilege('authenticated','public.catalog_recognition_history','UPDATE'),'cannot silently rewrite transitions');
select ok(not has_table_privilege('authenticated','public.catalog_recognition_audit','INSERT'),'audit cannot be forged by browser');
select ok(exists(select 1 from public.catalog_recognition_audit where event->>'breed_name'='Recognition Fixture'),'changes audited');
grant select on recognition_fixture to authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select owner_user_id from public.shows where id=(select id from recognition_fixture where key='show')))::text,true);
set local role authenticated;
select is((select r->>'recognition_status' from public.report_results_entry_rows_dated_page((select id from recognition_fixture where key='show'),p_entry_ids=>array[(select id from recognition_fixture where key='late')]) r),'recognized','authorized show owner can read dated status through RLS');
reset role;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"9f000000-0000-0000-0000-000000000001"}',true);
set local role authenticated;
select throws_ok($$insert into public.catalog_recognition_history(species,breed_name,status,effective_date) values ('rabbit','No Access','cod','2026-12-01')$$,'42501',null,'ordinary account cannot change status history');
reset role;
insert into public.catalog_recognition_history(species,breed_name,status,effective_date) values ('rabbit','Future cancellation','retired',current_date+365);
select lives_ok($$delete from public.catalog_recognition_history where breed_name='Future cancellation'$$,'unjudged future transition can be cancelled');
select ok(not exists(select 1 from public.catalog_recognition_history where breed_name='Future cancellation'),'cancelled transition is removed');
select ok(exists(select 1 from public.catalog_recognition_audit where event->>'breed_name'='Future cancellation' and action='DELETE'),'future cancellation stays in audit');
select * from finish();
rollback;
