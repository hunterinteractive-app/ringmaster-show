-- All synthetic data is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
create temporary table cod_fixture(key text primary key, id uuid default gen_random_uuid());
insert into cod_fixture(key) values ('show'),('section'),('cod'),('normal');
insert into public.shows(id,name,owner_user_id,created_by,final_award_mode,start_date,end_date)
select id,'COD regression fixture', (select owner_user_id from public.shows where owner_user_id is not null limit 1),
 (select owner_user_id from public.shows where owner_user_id is not null limit 1),'bis_1ris_2ris',current_date,current_date
from cod_fixture where key='show';
insert into public.show_sections(id,show_id,kind,letter,judging_date)
select id,(select id from cod_fixture where key='show'),'youth','B',current_date from cod_fixture where key='section';
insert into public.entries(id,show_id,section_id,species,breed,variety,sex,class_name,placement,result_status,judged_by_show_judge_id)
select id,(select id from cod_fixture where key='show'),(select id from cod_fixture where key='section'),
 'rabbit','Silver Fox','Blue (COD)','Doe','Senior','1','Shown',gen_random_uuid()
from cod_fixture where key='cod';
set constraints all immediate;
select ok(public.is_cod_entry('Velveteen Lop (COD)','Solid'),'COD breed recognized');
select ok(public.is_cod_entry('Silver Fox','cod blue'),'COD variety is case insensitive');
select ok(not public.is_cod_entry('Codsworth','Chocolate'),'whole COD marker required');
select lives_ok($$update public.entries set placement='2' where id=(select id from cod_fixture where key='cod')$$,'COD class placement saves');
select throws_ok($$insert into public.entry_awards(show_id,entry_id,award_code)
 values ((select id from cod_fixture where key='show'),(select id from cod_fixture where key='cod'),'BOSB')$$,
 '23514','COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.','COD BOS rejected');
select throws_ok($$update public.entries set special_awards='BOG' where id=(select id from cod_fixture where key='cod')$$,
 '23514','COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.','legacy special awards rejected');
select is((public.show_results_readiness_scoped((select id from cod_fixture where key='show'),array[(select id from cod_fixture where key='section')])->>'missing_final_award_count')::int,0,'COD only section needs no finals');

select lives_ok($$insert into public.entry_awards(show_id,entry_id,award_code)
 values ((select id from cod_fixture where key='show'),(select id from cod_fixture where key='cod'),'BOV')$$,'COD BOV saves');
select lives_ok($$update public.entry_awards set award_code='BOSV' where entry_id=(select id from cod_fixture where key='cod')$$,'COD BOSV saves');
select lives_ok($$update public.entries set special_awards='BOSV' where id=(select id from cod_fixture where key='cod')$$,'legacy COD BOSV saves');
select lives_ok($$update public.entries set special_awards='BOV' where id=(select id from cod_fixture where key='cod')$$,'legacy COD BOV saves');
select is((public.show_results_readiness_scoped((select id from cod_fixture where key='show'),array[(select id from cod_fixture where key='section')])->>'invalid_final_award_count')::int,0,'COD BOV is not a readiness error');
select throws_ok($$update public.entries set special_awards='BOV,BOSB' where id=(select id from cod_fixture where key='cod')$$,
 '23514','COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.','mixed COD BOV and higher awards rejected');
delete from public.entry_awards where entry_id=(select id from cod_fixture where key='cod');
update public.entries set special_awards=null where id=(select id from cod_fixture where key='cod');
update public.entries set placement=null where id=(select id from cod_fixture where key='cod');
select is((public.show_results_readiness_scoped((select id from cod_fixture where key='show'),array[(select id from cod_fixture where key='section')])->>'missing_placement_count')::int,1,'COD still requires placement');
update public.entries set variety='Black',placement='1' where id=(select id from cod_fixture where key='cod');
select lives_ok($$insert into public.entry_awards(show_id,entry_id,award_code)
 values ((select id from cod_fixture where key='show'),(select id from cod_fixture where key='cod'),'BOB')$$,'recognized variety may receive BOB');
select throws_ok($$update public.entries set variety='Blue (COD)' where id=(select id from cod_fixture where key='cod')$$,
 '23514','COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.','cannot reclassify awarded entry as COD');
-- Simulate a historical error predating the safeguard, then verify reporting
-- and an atomic correction without modifying historical records in migration.
alter table public.entries disable trigger validate_cod_entry_results;
update public.entries set variety='Blue (COD)' where id=(select id from cod_fixture where key='cod');
alter table public.entries enable trigger validate_cod_entry_results;
select is((public.show_results_readiness_scoped((select id from cod_fixture where key='show'),array[(select id from cod_fixture where key='section')])->>'invalid_final_award_count')::int,1,'historical COD award flagged');
set constraints all deferred;
update public.entries set special_awards=null where id=(select id from cod_fixture where key='cod');
delete from public.entry_awards where entry_id=(select id from cod_fixture where key='cod');
set constraints all immediate;
select ok((public.show_results_readiness_scoped((select id from cod_fixture where key='show'),array[(select id from cod_fixture where key='section')])->>'ready')::boolean,'removing incorrect award preserves completed placement');
select * from finish();

rollback;
