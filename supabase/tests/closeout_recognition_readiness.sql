-- The local runner compares every result with the pre-migration function.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table readiness_fixture(key text primary key,id uuid default gen_random_uuid());
insert into readiness_fixture(key) values ('show'),('nov'),('dec');
insert into public.catalog_recognition_history(species,breed_name,variety_name,status,effective_date)
values ('rabbit','Readiness Fixture','Blue (COD)','cod','2026-01-01'),
       ('rabbit','Readiness Fixture','Blue (COD)','recognized','2026-12-01');
insert into public.shows(id,name,start_date,end_date,created_by,owner_user_id,final_award_mode)
select id,'Readiness regression','2026-11-30','2026-12-01',
 (select owner_user_id from public.shows where owner_user_id is not null limit 1),
 (select owner_user_id from public.shows where owner_user_id is not null limit 1),'bis_ris'
from readiness_fixture where key='show';
insert into public.show_sections(id,show_id,kind,letter,judging_date)
select id,(select id from readiness_fixture where key='show'),'open',
 case when key='nov' then 'A' else 'B' end,
 case when key='nov' then '2026-11-30'::date else '2026-12-01'::date end
from readiness_fixture where key in ('nov','dec');
insert into public.entries(show_id,section_id,species,breed,variety,sex,class_name,placement,judged_by_show_judge_id)
select (select id from readiness_fixture where key='show'),id,'rabbit',
 'Readiness Fixture','Blue (COD)','Doe','Senior','1',gen_random_uuid()
from readiness_fixture where key in ('nov','dec');
insert into public.entry_awards(show_id,entry_id,award_code)
select show_id,id,'BOB' from public.entries
where show_id=(select id from readiness_fixture where key='show');
select is((public.show_results_readiness_scoped(
 (select id from readiness_fixture where key='show'),
 array[(select id from readiness_fixture where key='nov')])->>'missing_final_award_count')::int,0,
 'COD section before recognition needs no final awards');
select ok((public.show_results_readiness_scoped(
 (select id from readiness_fixture where key='show'),
 array[(select id from readiness_fixture where key='dec')])->>'missing_final_award_count')::int>0,
 'Same catalog subject recognized on later section date requires finals');
-- Null catalog values and status exclusions must preserve existing behavior.
insert into public.entries(show_id,section_id,species,breed,variety,sex,class_name,result_status,scratched_at)
select (select id from readiness_fixture where key='show'),
 (select id from readiness_fixture where key='dec'),'rabbit','Readiness Fixture',null,'Buck','Senior',
 case when n=2 then 'No Show' when n=3 then 'Disqualified' else 'Shown' end,
 case when n=4 then now() else null end
from generate_series(1,4) n;
select is((public.show_results_readiness_scoped(
 (select id from readiness_fixture where key='show'),
 array(select id from readiness_fixture where key in ('nov','dec')))->>'missing_placement_count')::int,1,
 'Active placement remains required; no-show, disqualified and scratched entries excluded');
select is((public.show_results_readiness_scoped(
 (select id from readiness_fixture where key='show'),null)->>'missing_placement_count')::int,0,
 'Null section selection still selects no entries');
select is((public.show_results_readiness_scoped(
 (select id from readiness_fixture where key='show'),array[]::uuid[])->>'missing_placement_count')::int,0,
 'Empty section selection still selects no entries');
grant select on readiness_fixture to authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',
 (select owner_user_id from public.shows where id=(select id from readiness_fixture where key='show')))::text,true);
set local role authenticated;
select is((public.show_results_readiness_scoped(
 (select id from readiness_fixture where key='show'),
 array(select id from readiness_fixture where key in ('nov','dec')))->>'missing_placement_count')::int,1,
 'Authenticated owner receives the same complete readiness through RLS');
reset role;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"9f000000-0000-0000-0000-000000000001"}',true);
set local role authenticated;
select is((select count(*)::int from public.entries where show_id=(select id from readiness_fixture where key='show')),0,
 'Unrelated account cannot read fixture entries');
select is((public.show_results_readiness_scoped(
 (select id from readiness_fixture where key='show'),
 array(select id from readiness_fixture where key in ('nov','dec')))->>'missing_placement_count')::int,0,
 'Readiness does not expose hidden entries to unrelated accounts');
reset role;
select ok(not (select prosecdef from pg_proc where oid='public.show_results_readiness_scoped(uuid,uuid[])'::regprocedure),
 'Optimized function remains SECURITY INVOKER');
select * from finish();
rollback;
