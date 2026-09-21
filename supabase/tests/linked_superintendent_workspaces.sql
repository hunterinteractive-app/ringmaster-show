begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temp table ws_fixture(k text primary key,id uuid default gen_random_uuid());
insert into ws_fixture(k) values ('one'),('two'),('third'),('manager'),('partial'),('outsider'),('group'),('assignment'),('foreign');
grant select on ws_fixture to authenticated;
insert into auth.users(id) select id from ws_fixture where k in ('manager','partial','outsider');
insert into public.shows(id,name,start_date,end_date) select id,'Shared fixture '||k,current_date,current_date from ws_fixture where k in ('one','two','third');
insert into public.role_assignments(user_id,show_id,role)
select u.id,s.id,'superintendent' from ws_fixture u cross join ws_fixture s
where (u.k='manager' and s.k in ('one','two')) or (u.k='partial' and s.k='one');
insert into public.superintendent_workspaces(id,name,show_ids)
select id,'Shared fixture',array[(select id from ws_fixture where k='one'),(select id from ws_fixture where k='two')] from ws_fixture where k='group';
insert into public.show_judging_assignments(id,show_id,breed_id,status,updated_at)
select a.id,s.id,'Havana','draft','2026-09-20T00:00:00Z' from ws_fixture a join ws_fixture s on (a.k='assignment' and s.k='one') or (a.k='foreign' and s.k='third');
select ok(not has_table_privilege('anon','public.superintendent_workspaces','select'),'anonymous cannot read workspace');
select ok(not has_table_privilege('authenticated','public.superintendent_workspaces','update'),'clients cannot relink shows');
select ok(not has_function_privilege('anon','public.save_workspace_assignment(uuid,uuid,text,integer,text,timestamptz)','execute'),'anonymous cannot edit workspace');
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from ws_fixture where k='outsider'))::text,true);
select is((select count(*)::int from public.superintendent_workspaces),0,'unrelated user cannot see group');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from ws_fixture where k='partial'))::text,true);
select is((select count(*)::int from public.superintendent_workspaces),0,'one-show access cannot see group');
select throws_ok($$select public.save_workspace_assignment((select id from ws_fixture where k='group'),(select id from ws_fixture where k='assignment'),'2',1,'draft','2026-09-20T00:00:00Z')$$,'42501','You need superintendent access to both shows.','partial manager cannot edit combined workspace');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from ws_fixture where k='manager'))::text,true);
select is((select count(*)::int from public.superintendent_workspaces where name='Shared fixture'),1,'both-show manager sees group');
select lives_ok($$select public.save_workspace_assignment((select id from ws_fixture where k='group'),(select id from ws_fixture where k='assignment'),'2',1,'completed','2026-09-20T00:00:00Z')$$,'authorized table/progress update works');
select is((select table_number from public.show_judging_assignments where id=(select id from ws_fixture where k='assignment')),'2','shared table persisted');
select is((select show_id from public.show_judging_assignments where id=(select id from ws_fixture where k='assignment')),(select id from ws_fixture where k='one'),'source show unchanged');
select is((select completed_by from public.show_judging_assignments where id=(select id from ws_fixture where k='assignment')),(select id from ws_fixture where k='manager'),'completion actor recorded');
select throws_ok($$select public.save_workspace_assignment((select id from ws_fixture where k='group'),(select id from ws_fixture where k='assignment'),'9',1,'draft','2026-09-20T00:00:00Z')$$,'40001','Another superintendent changed this assignment. Refresh and try again.','stale editor cannot overwrite');
select throws_ok($$select public.save_workspace_assignment((select id from ws_fixture where k='group'),(select id from ws_fixture where k='foreign'),'9',1,'draft','2026-09-20T00:00:00Z')$$,'42501','Assignment does not belong to this workspace.','cannot edit unrelated show');
reset role;
delete from public.role_assignments where user_id=(select id from ws_fixture where k='manager') and show_id=(select id from ws_fixture where k='two');
set local role authenticated;
select is((select count(*)::int from public.superintendent_workspaces),0,'revoking one show removes shared access immediately');
reset role;
select * from finish();
rollback;
