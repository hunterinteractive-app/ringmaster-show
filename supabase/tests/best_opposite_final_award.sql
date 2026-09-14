begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
create temporary table bbos_fixture(key text primary key, id uuid default gen_random_uuid());
insert into bbos_fixture(key) values ('other'),('staff'),('show'),('other_show'),('section'),('section_b'),
  ('r_bis'),('r_ris'),('r_bos'),('r_other_bos'),('c_bis'),('c_ris'),('c_bos'),('r_section_b');
grant select on bbos_fixture to authenticated;
insert into auth.users(id) select id from bbos_fixture where key in ('other','staff');
insert into public.shows(id,name,owner_user_id,created_by,final_award_mode,start_date,end_date)
select id,'Synthetic BBOS test',
  case when key='show' then '3e8dddf9-3a17-4ebb-aeab-9b51d31e7871'::uuid else (select id from bbos_fixture where key='other') end,
  case when key='show' then '3e8dddf9-3a17-4ebb-aeab-9b51d31e7871'::uuid else (select id from bbos_fixture where key='other') end,
  'bis_1ris_2ris','2026-09-14','2026-09-14'
from bbos_fixture where key in ('show','other_show');
select set_config('request.jwt.claims','{"sub":"3e8dddf9-3a17-4ebb-aeab-9b51d31e7871","role":"authenticated"}',true);
set local role authenticated;
select ok(public.can_configure_best_opposite_final_award((select id from bbos_fixture where key='show')),
  'allowlisted owner can configure the new format');
select ok(not public.can_configure_best_opposite_final_award((select id from bbos_fixture where key='other_show')),
  'allowlisted account does not enable unrelated shows');
reset role;
select lives_ok($$update public.shows set final_award_mode='bis_1ris_2ris_bbos'
  where id=(select id from bbos_fixture where key='show')$$,'selected show accepts the format');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from bbos_fixture where key='other'),'role','authenticated')::text,true);
select throws_ok($$update public.shows set final_award_mode='bis_1ris_2ris_bbos'
  where id=(select id from bbos_fixture where key='other_show')$$,'42501',
  'This final award format is only available for selected secretaries’ shows.',
  'non-allowlisted owner cannot enable the restricted format through a direct save');
insert into public.role_assignments(user_id,role,show_id)
select (select id from bbos_fixture where key='staff'),'admin',id from bbos_fixture where key='show';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from bbos_fixture where key='staff'),'role','authenticated')::text,true);
set local role authenticated;
select ok(public.can_configure_best_opposite_final_award((select id from bbos_fixture where key='show')),
  'another authorized secretary can manage the selected secretary’s show');
select ok(not public.can_configure_best_opposite_final_award((select id from bbos_fixture where key='other_show')),
  'staff membership does not enable unrelated shows');
reset role;
select set_config('request.jwt.claims','{"sub":"3e8dddf9-3a17-4ebb-aeab-9b51d31e7871","role":"authenticated"}',true);
insert into public.show_sections(id,show_id,kind,letter,judging_date)
select id,(select id from bbos_fixture where key='show'),'open',case when key='section' then 'A' else 'B' end,'2026-09-14'
from bbos_fixture where key in ('section','section_b');
insert into public.entries(id,show_id,section_id,species,breed,sex,class_name,placement,result_status,judged_by_show_judge_id)
select id,(select id from bbos_fixture where key='show'),
 (select id from bbos_fixture where key=case when f.key='r_section_b' then 'section_b' else 'section' end),
 case when key like 'c_%' then 'cavy' else 'rabbit' end,
 'Synthetic ' || key, case when key like 'c_%' then 'Sow' else 'Doe' end,
 'Senior','1','Shown',gen_random_uuid()
from bbos_fixture f where key in ('r_bis','r_ris','r_bos','r_other_bos','c_bis','c_ris','c_bos','r_section_b');
insert into public.entry_awards(show_id,entry_id,award_code)
select (select id from bbos_fixture where key='show'),f.id,v.award
from bbos_fixture f cross join lateral unnest(
 case when key in ('r_bis','c_bis') then array['BOB','BIS']
 when key in ('r_ris','c_ris') then array['BOB','1RIS']
 else array['BOSB'] end) v(award)
where key in ('r_bis','r_ris','r_bos','r_other_bos','c_bis','c_ris','c_bos','r_section_b');
set constraints all immediate;
create temporary table bbos_readiness as select public.show_results_readiness_scoped(
 (select id from bbos_fixture where key='show'),array[(select id from bbos_fixture where key='section')]) value;
select ok((select (value->>'ready')::boolean from bbos_readiness),'missing BBOS does not block closeout');
select is((select (value->>'missing_final_award_count')::int from bbos_readiness),0,'BIS and first RIS retain their existing required behavior');
select is((select count(*)::int from bbos_readiness,jsonb_array_elements(value->'suggested_final_awards') a where a->>'award_code'='BBOS'),2,
  'missing BBOS warns separately for rabbits and cavies');
select is((select count(*)::int from bbos_readiness,jsonb_array_elements(value->'suggested_final_awards') a where a->>'award_code'='2RIS'),2,
  'second RIS remains advisory exactly as in the original format');
select throws_ok($$insert into public.entry_awards(show_id,entry_id,award_code)
 values ((select id from bbos_fixture where key='show'),(select id from bbos_fixture where key='r_bis'),'BBOS')$$,
 'P0001','Best of the Best Opposite requires Best Opposite Sex of Breed (BOS) first.','BOB alone is not eligible');
select lives_ok($$insert into public.entry_awards(show_id,entry_id,award_code)
 select (select id from bbos_fixture where key='show'),id,'BBOS' from bbos_fixture where key in ('r_bos','c_bos','r_section_b')$$,
 'one rabbit and one cavy winner plus a winner in another section can coexist');
select throws_ok($$insert into public.entry_awards(show_id,entry_id,award_code)
 values ((select id from bbos_fixture where key='show'),(select id from bbos_fixture where key='r_other_bos'),'BBOS')$$,
 'P0001','Best of the Best Opposite is already assigned for this species in this section.','duplicate winner is rejected across breeds');
select throws_ok($$delete from public.entry_awards where entry_id=(select id from bbos_fixture where key='r_bos') and award_code='BOSB'$$,
 'P0001','Best of the Best Opposite requires Best Opposite Sex of Breed (BOS) first.','removing BOS cannot leave BBOS behind');
select throws_ok($$update public.entries set result_status='No Show' where id=(select id from bbos_fixture where key='c_bos')$$,
 'P0001','Best of the Best Opposite requires an eligible first-place rabbit or cavy.','making a BBOS winner ineligible is rejected');
select throws_ok($$update public.shows set final_award_mode='bis_1ris_2ris' where id=(select id from bbos_fixture where key='show')$$,
 'P0001','Remove Best of the Best Opposite awards before changing the final award format.','format change cannot strand BBOS awards');
select is((public.show_results_readiness_scoped((select id from bbos_fixture where key='show'),
 array[(select id from bbos_fixture where key='section')])->>'suggested_final_award_count')::int,2,
 'saving BBOS clears its warnings and leaves only the existing second RIS suggestions');
-- A single save may clear both the dependent award and its BOS source.
set constraints all deferred;
delete from public.entry_awards where entry_id=(select id from bbos_fixture where key='r_bos') and award_code in ('BOSB','BBOS');
select lives_ok('set constraints all immediate','removing both awards in one save is allowed');
-- Verify order independence when BOS and the new award arrive in one result save.
set constraints all deferred;
insert into public.entry_awards(show_id,entry_id,award_code)
select (select id from bbos_fixture where key='show'),(select id from bbos_fixture where key='r_bos'),award from unnest(array['BBOS','BOSB']) award;
select lives_ok('set constraints all immediate','BBOS can precede BOS within the same transaction');
select ok(not has_function_privilege('anon','public.can_configure_best_opposite_final_award(uuid)','execute'),
 'anonymous callers cannot inspect the secretary feature gate');
-- Exercise the same RPC used by standard and QR results entry as a real client role.
set local role authenticated;
select lives_ok($$select * from public.save_results_entry(
 (select id from bbos_fixture where key='show'),(select id from bbos_fixture where key='r_bos'),
 '1','Shown',null,true,false,null,'Synthetic Clerk',null,array['BOSB','BBOS'],false)$$,
 'authenticated results save persists BOS and BBOS together');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from bbos_fixture where key='other'),'role','authenticated')::text,true);
set local role authenticated;
select throws_ok($$select * from public.save_results_entry(
 (select id from bbos_fixture where key='show'),(select id from bbos_fixture where key='r_other_bos'),
 '1','Shown',null,true,false,null,'Synthetic Clerk',null,array['BOSB','BBOS'],false)$$,
 '42501','You do not have permission to enter results for this show.',
 'unrelated authenticated user cannot use the results RPC to assign BBOS');
reset role;
insert into public.secretary_feature_access(feature_key,user_id)
select 'best_of_best_opposite',id from bbos_fixture where key='other';
set local role authenticated;
select ok(public.can_configure_best_opposite_final_award((select id from bbos_fixture where key='other_show')),
 'adding another secretary to the existing allowlist enables their show');
select ok(not has_table_privilege('authenticated','public.secretary_feature_access','insert'),
 'secretaries cannot grant themselves feature access');
reset role;
select ok(not (select prosecdef from pg_proc where oid='public.can_configure_best_opposite_final_award(uuid)'::regprocedure),
 'exposed feature RPC uses caller privileges');
select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc
 where oid='show_awards_private.can_configure_best_opposite(uuid)'::regprocedure),
 'privileged allowlist lookup stays private with a fixed empty search path');
select * from finish();
rollback;
