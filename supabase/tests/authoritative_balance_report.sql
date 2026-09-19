begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table balance_fixture(k text primary key,id uuid default gen_random_uuid());
insert into balance_fixture(k) values ('show'),('section'),('ex'),('fallback'),('paid');
insert into public.shows(id,name,start_date,end_date)
select id,'Balance duplicate regression',current_date,current_date from balance_fixture where k='show';
insert into public.show_sections(id,show_id,kind,letter,is_enabled)
select id,(select id from balance_fixture where k='show'),'open','A',true from balance_fixture where k='section';
insert into public.exhibitors(id,display_name,type,email)
select id,'Same display name','adult',id::text || '@example.invalid' from balance_fixture where k in ('ex','fallback','paid');
insert into public.show_exhibitor_balances(show_id,exhibitor_id,source,entry_count,balance_due_cents)
select (select id from balance_fixture where k='show'),f.id,v.source,v.entries,v.due
from balance_fixture f join (values
 ('ex','cart',6,2400),('ex','cart',2,800),('ex','entries',8,3200),
 ('fallback','cart',3,1200),('paid','cart',4,1600),('paid','entries',4,0)
) v(k,source,entries,due) on v.k=f.k;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
create temporary table result as select r from public.report_show_exhibitor_balances_scoped(
 (select id from balance_fixture where k='show'),array[(select id from balance_fixture where k='section')]) r;
select is((select count(*)::int from result),3,'one authoritative balance per exhibitor; cart-only fallback preserved');
select is((select sum((r->>'balance_due_cents')::int)::int from result),4400,'superseded cart amounts do not inflate total');
select is((select sum((r->>'entry_count')::int)::int from result),15,'entry counts are not duplicated');
select is((select count(*)::int from result where (r->>'balance_due_cents')::int>0),2,'paid authoritative balance hides stale unpaid cart');
select is((select r->>'source' from result where r->>'exhibitor_id'=(select id::text from balance_fixture where k='fallback')),'cart','cart-only exhibitor remains');
select is((select count(distinct r->>'exhibitor_id')::int from result),3,'same display names are not merged');
select ok(not has_function_privilege('anon','public.report_show_exhibitor_balances_scoped(uuid,uuid[])','execute'),'anonymous access remains denied');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',gen_random_uuid())::text,true);
select throws_ok($$select * from public.report_show_exhibitor_balances_scoped(
 (select id from balance_fixture where k='show'),array[(select id from balance_fixture where k='section')])$$,
 '42501','You do not have access to this show','unrelated user remains denied');
select * from finish();
rollback;
