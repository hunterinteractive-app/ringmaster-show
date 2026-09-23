-- Apply the assistant and household migrations in a disposable DB first.
-- Runner may wrap this file in the same transaction as migrations.
\set ON_ERROR_STOP on
insert into auth.users(id,email,email_confirmed_at) values
 ('91000000-0000-0000-0000-000000000001','assistant-owner@example.invalid',now()),
 ('91000000-0000-0000-0000-000000000002','assistant-member@example.invalid',now()),
 ('91000000-0000-0000-0000-000000000003','assistant-stranger@example.invalid',now());
insert into public.shows(id,name,owner_user_id,is_published) values
 ('92000000-0000-0000-0000-000000000001','Assistant Test Show','91000000-0000-0000-0000-000000000001',true);
insert into public.exhibitors(id,owner_user_id,display_name,showing_name,type,email) values
 ('93000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','Child A','Child A','youth','assistant-owner@example.invalid'),
 ('93000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000003','Private Jim','Private Jim','adult','assistant-stranger@example.invalid');
insert into public.entries(show_id,exhibitor_id,exhibitor_user_id,tattoo,breed,species) values
 ('92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','MY-RABBIT','Mini Rex','rabbit'),
 ('92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000003','JIMS-RABBIT','Mini Rex','rabbit');
insert into household_private.invitations(owner_user_id,email,member_user_id,accepted_at)
 values('91000000-0000-0000-0000-000000000001','assistant-member@example.invalid','91000000-0000-0000-0000-000000000002',now());
create function pg_temp.assert_true(v boolean,message text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',message; end if; end $$;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.assistant_read_context('entries',null,'92000000-0000-0000-0000-000000000001')->'rows')=1,'Only own entries even if show manager can read everyone');
select pg_temp.assert_true(public.assistant_read_context('entries',null,'92000000-0000-0000-0000-000000000001')::text not like '%JIMS%','No Jim entry leaked');
select pg_temp.assert_true(public.assistant_read_context('household')::text not like '%Private Jim%','No other exhibitor leaked despite broad legacy exhibitor SELECT policy');
select pg_temp.assert_true(public.assistant_read_context('entries')->>'needs_show'='true','Explicit show required');
do $$begin
 begin perform public.assistant_read_context('entries','91000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000001');raise exception 'FAILED: stranger lookup';
 exception when raise_exception then if sqlerrm<>'Household unavailable' then raise;end if;end;
 begin perform public.assistant_admin(true,100000000);raise exception 'FAILED: changed budget';
 exception when raise_exception then if sqlerrm<>'Not authorized' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.assistant_read_context('entries','91000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001')->'rows')=1,'Accepted household can read entries');
do $$begin
 begin perform public.assistant_read_context('setup','91000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001');raise exception 'FAILED: inherited secretary access';
 exception when raise_exception then if sqlerrm<>'Show unavailable' then raise;end if;end;
end $$;
reset role;
update household_private.invitations set revoked_at=now() where owner_user_id='91000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$begin
 begin perform public.assistant_read_context('household','91000000-0000-0000-0000-000000000001');raise exception 'FAILED: revoked access';
 exception when raise_exception then if sqlerrm<>'Household unavailable' then raise;end if;end;
end $$;
reset role;
select pg_temp.assert_true(not has_function_privilege('authenticated','public.assistant_reserve(uuid,uuid,uuid,text)','execute'),'Clients cannot bypass budget attribution');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.assistant_finish(uuid,bigint,bigint,integer,boolean)','execute'),'Clients cannot refund their usage');
select pg_temp.assert_true(not has_function_privilege('anon','public.assistant_read_context(text,uuid,uuid)','execute'),'Anonymous reads denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','assistant_private.usage','select'),'Usage rows private');
select pg_temp.assert_true(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='assistant_private' and c.relkind='r' and not c.relrowsecurity),'All assistant tables use RLS');
update assistant_private.settings set enabled=true,monthly_budget_microusd=60000;
set local role service_role;
select pg_temp.assert_true((public.assistant_reserve('91000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001','help')->>'allowed')::boolean,'First reservation fits budget');
select pg_temp.assert_true(public.assistant_reserve('91000000-0000-0000-0000-000000000003','94000000-0000-0000-0000-000000000002','95000000-0000-0000-0000-000000000002','help')->>'reason'='budget','Another user cannot spend reserved money');
select pg_temp.assert_true(public.assistant_reserve('91000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001','help')->>'reason'='duplicate','Retries not recharged');
select pg_temp.assert_true(public.assistant_reserve('91000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000003','95000000-0000-0000-0000-000000000001','help')->>'reason'='busy','One active question per actor');
select public.assistant_finish('94000000-0000-0000-0000-000000000001',10000,2000,2,true);
-- A second settlement cannot release money twice.
select public.assistant_finish('94000000-0000-0000-0000-000000000001',0,0,0,true);
reset role;
select pg_temp.assert_true((select charged_microusd=16500 from assistant_private.usage where request_id='94000000-0000-0000-0000-000000000001'),'Actual cost and idempotent settlement');
update assistant_private.settings set monthly_budget_microusd=1000000,minute_questions=1;
set local role service_role;
select pg_temp.assert_true(public.assistant_reserve('91000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000004','95000000-0000-0000-0000-000000000001','help')->>'reason'='rate_limit','Rolling minute limit');
reset role;
update assistant_private.usage set created_at=now()-interval '2 minutes';
update assistant_private.settings set daily_questions=1;
set local role service_role;
select pg_temp.assert_true(public.assistant_reserve('91000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000005','95000000-0000-0000-0000-000000000001','help')->>'reason'='daily_limit','Daily limit');
select pg_temp.assert_true((public.assistant_reserve('91000000-0000-0000-0000-000000000003','94000000-0000-0000-0000-000000000006','95000000-0000-0000-0000-000000000002','help')->>'allowed')::boolean,'Independent actor limit');
select public.assistant_finish('94000000-0000-0000-0000-000000000006',0,0,1,false);
reset role;
select pg_temp.assert_true((select charged_microusd=60000 and state='failed' from assistant_private.usage where request_id='94000000-0000-0000-0000-000000000006'),'Timeout retains full reservation');
update assistant_private.settings set enabled=false;
set local role service_role;
select pg_temp.assert_true(public.assistant_reserve('91000000-0000-0000-0000-000000000003',gen_random_uuid(),gen_random_uuid(),'help')->>'reason'='paused','Kill switch');
reset role;
select 'Assistant permission and budget checks passed' as result;
