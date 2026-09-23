begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temp table unified_fixture(k text primary key,id uuid default gen_random_uuid());
insert into unified_fixture(k) values ('one'),('two'),('third'),('section1'),('section2'),('section3'),('manager'),('partial'),('outsider'),('group'),('judge'),('wrongjudge');
grant select on unified_fixture to authenticated;
insert into auth.users(id) select id from unified_fixture where k in ('manager','partial','outsider');
insert into public.shows(id,name,start_date,end_date) select id,'Unified fixture '||k,current_date,current_date from unified_fixture where k in ('one','two','third');
insert into public.show_sections(id,show_id,kind,letter,is_enabled)
select sec.id,s.id,'open','A',true from unified_fixture sec join unified_fixture s on (sec.k='section1' and s.k='one') or (sec.k='section2' and s.k='two') or (sec.k='section3' and s.k='third');
insert into public.role_assignments(user_id,show_id,role)
select u.id,s.id,'superintendent' from unified_fixture u cross join unified_fixture s where (u.k='manager' and s.k in ('one','two')) or (u.k='partial' and s.k='one');
insert into public.superintendent_workspaces(id,name,show_ids)
select id,'Unified fixture',array[(select id from unified_fixture where k='one'),(select id from unified_fixture where k='two')] from unified_fixture where k='group';
insert into public.judges(id,name) select id,k from unified_fixture where k in ('judge','wrongjudge');
insert into public.judge_assignments(show_id,judge_id,assignment_label)
select s.id,j.id,'All breeds' from unified_fixture s cross join unified_fixture j where (s.k in ('one','two') and j.k='judge') or (s.k='one' and j.k='wrongjudge');
-- Entry routing and results preservation are checked as part of real sync.
insert into public.entries(id,show_id,section_id,species,breed,sex,class_name,result_entered_at)
select gen_random_uuid(),s.id,sec.id,'rabbit','Havana','buck','Senior',case when v.result then now() else null end
from unified_fixture s join unified_fixture sec on (s.k='one' and sec.k='section1') or (s.k='two' and sec.k='section2')
cross join (values(false),(true)) v(result);
insert into public.entries(id,show_id,section_id,species,breed,sex,class_name,judged_by_show_judge_id)
select gen_random_uuid(),(select id from unified_fixture where k='two'),(select id from unified_fixture where k='section2'),'rabbit','Havana','buck','Senior',(select id from unified_fixture where k='wrongjudge');
create function pg_temp.unified_mutate(action text,payload jsonb default '{}'::jsonb) returns jsonb language sql as $$
 select public.mutate_workspace_lineup((select id from unified_fixture where k='group'),public.workspace_lineup_versions((select id from unified_fixture where k='group')),action,payload);
$$;
select ok(not has_function_privilege('anon','public.mutate_workspace_lineup(uuid,jsonb,text,jsonb)','execute'),'anonymous mutation denied');
select ok(not has_function_privilege('anon','private.mutate_workspace_lineup(uuid,jsonb,text,jsonb)','execute'),'private mutation denied to anonymous too');
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from unified_fixture where k='partial'))::text,true);
select throws_ok($$select pg_temp.unified_mutate('sync')$$,'42501','You need superintendent access to both shows.','partial manager denied');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from unified_fixture where k='outsider'))::text,true);
select throws_ok($$select pg_temp.unified_mutate('sync')$$,'42501','You need superintendent access to both shows.','unrelated user denied');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from unified_fixture where k='manager'))::text,true);
select lives_ok($$select pg_temp.unified_mutate('add',jsonb_build_object('p_is_judge_change',true,'p_judge_id',(select id from unified_fixture where k='judge'),'p_table_number','1','p_sort_order',0))$$,'shared judge can be added');
select is((select count(*)::int from public.show_judging_assignments where show_id in(select id from unified_fixture where k in('one','two'))),2,'judge marker saved once per source show');
select is((select count(distinct workspace_marker_id)::int from public.show_judging_assignments where show_id in(select id from unified_fixture where k in('one','two'))),1,'both markers share one visible identity');
select throws_ok($$select public.mutate_workspace_lineup((select id from unified_fixture where k='group'),'[]','sync','{}')$$,'40001','The line-up changed. Refresh before making another change.','stale snapshot rejected');
select lives_ok($$select pg_temp.unified_mutate('add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section2'),'p_show_id',(select id from unified_fixture where k='one'),'p_breed_id','Havana','p_scope','open','p_table_number','1','p_sort_order',1,'p_entry_count_actual',2))$$,'breed addition resolves show from actual section');
select is((select count(*)::int from public.show_judging_assignments where section_id=(select id from unified_fixture where k='section2') and show_id=(select id from unified_fixture where k='two')),1,'breed never written to wrong source show');
select throws_ok($$select pg_temp.unified_mutate('add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section3'),'p_breed_id','Havana','p_table_number','1','p_sort_order',2))$$,'42501','This section does not belong to the shared line-up.','outside section rejected');
select throws_ok($$select pg_temp.unified_mutate('replace',jsonb_build_object('rows',jsonb_build_array(jsonb_build_object('p_is_judge_change',true,'p_judge_id',(select id from unified_fixture where k='wrongjudge'),'p_table_number','1','p_sort_order',0))))$$,'P0001','Choose a judge enabled for both shows.','invalid Auto Fill rolls back whole replacement');
select is((select count(*)::int from public.show_judging_assignments where show_id in(select id from unified_fixture where k in('one','two'))),3,'failed replacement preserves all existing rows');
select lives_ok($$select pg_temp.unified_mutate('move',jsonb_build_object('id',(select id from public.show_judging_assignments where show_id=(select id from unified_fixture where k='one') and is_judge_change),'table_number','2','sort_order',0))$$,'judge can move across shared table board');
select is((select count(*)::int from public.show_judging_assignments where workspace_marker_id is not null and table_number='2' and show_id in(select id from unified_fixture where k in('one','two'))),2,'moving a judge moves both mirrored markers');
reset role;
select is((select count(*)::int from public.entries where show_id=(select id from unified_fixture where k='two') and judged_by_show_judge_id=(select id from unified_fixture where k='judge')),0,'moving judge away clears only its prior unjudged assignments');
set local role authenticated;
select lives_ok($$select pg_temp.unified_mutate('move',jsonb_build_object('id',(select id from public.show_judging_assignments where section_id=(select id from unified_fixture where k='section2')),'table_number','2','sort_order',1))$$,'moving breed under shared judge updates sync');
select lives_ok($$select pg_temp.unified_mutate('publish','{"published":true}')$$,'one publish action works for both shows');
reset role;
select is((select count(*)::int from public.shows where id in(select id from unified_fixture where k in('one','two')) and superintendent_judge_order_published),2,'both shows published');
select is((select count(*)::int from public.entries where show_id=(select id from unified_fixture where k='two') and result_entered_at is null and judged_by_show_judge_id=(select id from unified_fixture where k='judge')),1,'sync updates intended show entry');
select is((select count(*)::int from public.entries where show_id in(select id from unified_fixture where k in('one','two')) and result_entered_at is not null and judged_by_show_judge_id is not null),0,'entered results never overwritten');
select is((select count(*)::int from public.entries where show_id=(select id from unified_fixture where k='one') and judged_by_show_judge_id is not null),0,'other show entries not assigned by wrong section');
select is((select count(*)::int from public.entries where show_id=(select id from unified_fixture where k='two') and judged_by_show_judge_id=(select id from unified_fixture where k='wrongjudge')),1,'explicit manual judge choice preserved');

set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from unified_fixture where k='manager'),true);
select lives_ok($$select pg_temp.unified_mutate('specialty_save','{"name":"IDDRC","breed":"Dutch","judge_name":"Guest Judge","entry_count":40,"table_number":"1","sort_order":5,"status":"draft"}')$$,'add outside specialty');
select is((select count(*)::int from public.workspace_specialties),1,'specialty visible to shared manager');
select throws_ok($$select pg_temp.unified_mutate('specialty_save','{"name":"Invalid","breed":"Dutch","entry_count":-1,"table_number":"1","sort_order":0,"status":"draft"}')$$,'23514',null,'negative counts rejected');
select lives_ok($$select pg_temp.unified_mutate('specialty_save',jsonb_build_object('id',(select id from public.workspace_specialties),'name','IDDRC','breed','Dutch','judge_name','Guest Judge','entry_count',45,'table_number','1','sort_order',5,'status','in_progress'))$$,'update count and progress');
select is((select entry_count from public.workspace_specialties),45,'updated count stored');
select lives_ok($$select pg_temp.unified_mutate('replace','{"rows":[]}')$$,'Auto Fill can replace host assignments');
select is((select count(*)::int from public.workspace_specialties),1,'Auto Fill preserves specialty');
select lives_ok($$select pg_temp.unified_mutate('move',jsonb_build_object('id',(select id from public.workspace_specialties),'table_number','3','sort_order',2))$$,'move specialty to another table');
select is((select table_number from public.workspace_specialties),'3','specialty table updated');
select throws_ok($$select public.mutate_workspace_lineup((select id from unified_fixture where k='group'),'[]','specialty_save','{}')$$,'40001','The line-up changed. Refresh before making another change.','stale specialty edit rejected');
select throws_ok($$update public.workspace_specialties set entry_count=99$$,'42501',null,'direct update denied');
select set_config('request.jwt.claim.sub',(select id::text from unified_fixture where k='partial'),true);
select is((select count(*)::int from public.workspace_specialties),0,'partial manager cannot read specialties');
select throws_ok($$select pg_temp.unified_mutate('specialty_save','{}')$$,'42501','You need superintendent access to both shows.','partial manager cannot change specialties');
select set_config('request.jwt.claim.sub',(select id::text from unified_fixture where k='manager'),true);
select throws_ok($$select pg_temp.unified_mutate('reorder',jsonb_build_object('rows',jsonb_build_array(jsonb_build_object('id',(select id from public.workspace_specialties),'sort_order',10),jsonb_build_object('id',(select id from unified_fixture where k='outsider'),'sort_order',11))))$$,'42501','Assignment is outside this workspace.','mixed reorder rejects invalid rows atomically');
select is((select sort_order from public.workspace_specialties),2,'failed reorder leaves specialty unchanged');
select ok(not has_table_privilege('anon','public.workspace_specialties','select'),'anonymous specialty reads denied');
select ok(not has_function_privilege('authenticated','private.mutate_workspace_lineup_core(uuid,jsonb,text,jsonb)','execute'),'internal mutation core cannot be called directly');
select lives_ok($$select pg_temp.unified_mutate('specialty_save',jsonb_build_object('id',(select id from public.workspace_specialties),'name','IDDRC','breed','Dutch','entry_count',45,'table_number','3','status','draft','scope','youth'))$$,'scope saves without order or judge');
select is((select scope from public.workspace_specialties),'youth','youth persisted');
select is((select sort_order from public.workspace_specialties),2,'editing preserves dragged order');
select throws_ok($$select pg_temp.unified_mutate('specialty_save','{"scope":"invalid"}')$$,'P0001','Choose Open or Youth.','invalid scope rejected');
select lives_ok($$select pg_temp.unified_mutate('specialty_save','{"name":"Second","breed":"Dutch","entry_count":10,"table_number":"3","status":"draft","scope":"open"}')$$,'new specialty gets automatic position');
select is((select sort_order from public.workspace_specialties where name='Second'),3,'appends after existing specialty');
select pg_temp.unified_mutate('delete',jsonb_build_object('id',(select id from public.workspace_specialties where name='Second')));
select lives_ok($$select pg_temp.unified_mutate('delete',jsonb_build_object('id',(select id from public.workspace_specialties)))$$,'delete specialty');
select is((select count(*)::int from public.workspace_specialties),0,'specialty removed');
reset role;

update public.shows set final_award_mode='four_six_bis' where id=(select id from unified_fixture where k='one');
update public.shows set final_award_mode='bis_1ris_2ris' where id=(select id from unified_fixture where k='two');
set local role authenticated;
select lives_ok($$select pg_temp.unified_mutate('add',jsonb_build_object('p_is_judge_change',true,'p_judge_id',(select id from unified_fixture where k='judge'),'p_table_number','1','p_sort_order',0))$$,'assign judge for award plans');
select lives_ok($$select pg_temp.unified_mutate('award_add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section1'),'p_award_code','BEST4','p_table_number','1','p_sort_order',1))$$,'Best 4 available for four/six mode');
select lives_ok($$select pg_temp.unified_mutate('award_add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section1'),'p_award_code','BEST6','p_table_number','1','p_sort_order',2))$$,'Best 6 separate assignment');
select lives_ok($$select pg_temp.unified_mutate('award_add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section1'),'p_award_code','BIS','p_table_number','1','p_sort_order',3))$$,'BIS separate assignment');
select lives_ok($$select pg_temp.unified_mutate('award_add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section2'),'p_award_code','FINALS','p_table_number','1','p_sort_order',4))$$,'ranked reserves one combined assignment');
select is((select count(*)::int from public.workspace_specialties where award_code is not null),4,'three individual plus one combined plan');
select is((select sum(entry_count)::int from public.workspace_specialties),0,'award plans have no head count');
select is((select count(*)::int from public.show_judging_assignments where show_id in(select id from unified_fixture where k in ('one','two')) and not is_judge_change),0,'award plans never enter published breed order');
select throws_ok($$select pg_temp.unified_mutate('award_add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section2'),'p_award_code','BEST4','p_table_number','1','p_sort_order',5))$$,'P0001','Award option does not match the show settings. Refresh and try again.','reject option incompatible with club settings');
select throws_ok($$select pg_temp.unified_mutate('award_add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section2'),'p_award_code','FINALS','p_table_number','1','p_sort_order',5))$$,'23505',null,'one combined judge assignment per section');
select throws_ok($$select pg_temp.unified_mutate('award_add',jsonb_build_object('p_section_id',(select id from unified_fixture where k='section3'),'p_award_code','BIS','p_table_number','1','p_sort_order',5))$$,'42501','Award section is outside this workspace or disabled.','cannot plan awards for unauthorized show');
select lives_ok($$select pg_temp.unified_mutate('publish','{"published":true}')$$,'publish still works');
select is((select count(*)::int from public.workspace_specialties where award_code is not null),4,'private plans retained through publish');
reset role;
-- Even when a user may view a published workspace, private award plans remain hidden.
create or replace function public.can_view_superintendent_workspace(p_show_ids uuid[]) returns boolean language sql stable security invoker set search_path='' as $$ select true $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from unified_fixture where k='outsider'),true);
select is((select count(*)::int from public.superintendent_workspaces where id=(select id from unified_fixture where k='group')),1,'published workspace viewer can see workspace');
select is((select count(*)::int from public.workspace_specialties where award_code is not null),0,'published workspace viewer cannot read award plans');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from unified_fixture where k='partial'),true);
select lives_ok($$select public.ensure_show_lineup_workspace((select id from unified_fixture where k='one'))$$,'single-show superintendent gets own planning workspace');
select is(public.ensure_show_lineup_workspace((select id from unified_fixture where k='one')),public.ensure_show_lineup_workspace((select id from unified_fixture where k='one')),'single workspace reused');
select throws_ok($$select public.ensure_show_lineup_workspace((select id from unified_fixture where k='two'))$$,'42501','You need permission to manage this show line-up.','cannot create workspace for another club');
select lives_ok($$select public.mutate_workspace_lineup(w.id,public.workspace_lineup_versions(w.id),'specialty_save','{"name":"Club specialty","breed":"Dutch","scope":"open","entry_count":10,"table_number":"1","status":"draft"}') from public.superintendent_workspaces w where w.show_ids=array[(select id from unified_fixture where k='one')]$$,'specialty works for a single show');
reset role;
select * from finish();
rollback;
