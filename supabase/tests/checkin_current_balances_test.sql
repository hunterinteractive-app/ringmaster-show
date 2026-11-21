begin;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
create temporary table ids(k text primary key,id uuid default gen_random_uuid());
insert into ids(k) values('show'),('other'),('A'),('B'),('exhibitor'),('entry1'),('entry2'),('receipt'),('credit');
create function pg_temp.id(text) returns uuid language sql as $$select id from ids where k=$1$$;
create function pg_temp.due() returns numeric language sql as $$select balance_due_all_shows from report_checkin_entries(pg_temp.id('show')) limit 1$$;
insert into shows(id,name) values(pg_temp.id('show'),'Check-in fixture'),(pg_temp.id('other'),'Other show');
insert into exhibitors(id,display_name) values(pg_temp.id('exhibitor'),'Check-in Exhibitor');
insert into show_sections(id,show_id,kind,letter,is_enabled,sort_order)
 select id,pg_temp.id('show'),'open',k,true,1 from ids where k in ('A','B');
insert into show_fee_settings(show_id,currency) values(pg_temp.id('show'),'usd');
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee,fee_per_show) select id,5,1,0 from ids where k in ('A','B');
insert into entries(id,show_id,section_id,exhibitor_id,species,tattoo,status,is_fur)
 values(pg_temp.id('entry1'),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('exhibitor'),'rabbit','ONE','entered',false),
 (pg_temp.id('entry2'),pg_temp.id('show'),pg_temp.id('B'),pg_temp.id('exhibitor'),'rabbit','TWO','entered',false);
select is((select count(*)::int from report_checkin_entries(pg_temp.id('show'))),2,'all sections return every active entry');
select is(pg_temp.due(),10::numeric,'initial report reads current entry charges in dollars');
select is((select count(*)::int from report_checkin_entries(pg_temp.id('show'),false,pg_temp.id('A'))),1,'section filtering retained');
select is((select balance_due_all_shows from report_checkin_entries(pg_temp.id('show'),false,pg_temp.id('A'))),10::numeric,'section sheet retains whole-event balance');
select is((select count(*)::int from report_checkin_entries(pg_temp.id('other'))),0,'other show entries excluded');
select public.record_show_finance_payment(pg_temp.id('show'),pg_temp.id('exhibitor'),400,'cash',now(),'Check-in test receipt',pg_temp.id('receipt'));
select is(pg_temp.due(),6::numeric,'next report immediately reflects newly recorded payment');
select public.credit_show_finance_balance(pg_temp.id('show'),pg_temp.id('exhibitor'),100,'Check-in test credit',pg_temp.id('credit'));
select is(pg_temp.due(),5::numeric,'next report immediately reflects new credit');
select is(pg_temp.due()*100,(select (r->>'due_cents')::numeric from jsonb_array_elements(public.get_show_finances(pg_temp.id('show'))->'exhibitors') r where r->>'exhibitor_id'=pg_temp.id('exhibitor')::text),'report agrees with Show Finances');
create temporary table balances_before as select to_jsonb(b) row from show_exhibitor_balances b;
create temporary table audit_before as select count(*) n from show_finances_private.events;
select count(*) from report_checkin_entries(pg_temp.id('show')) limit 1;
select count(*) from report_checkin_entries(pg_temp.id('show')) offset 1;
select is((select count(*)::int from ((select to_jsonb(b) row from show_exhibitor_balances b except select row from balances_before) union all (select row from balances_before except select to_jsonb(b) row from show_exhibitor_balances b)) diff),0,'repeated report pages do not rewrite balances or timestamps');
select is((select count(*) from show_finances_private.events),(select n from audit_before),'report reads do not create finance events');
update entries set scratched_at=now() where id=pg_temp.id('entry2');
select is((select count(*)::int from report_checkin_entries(pg_temp.id('show'))),1,'scratches excluded by default');
select is((select count(*)::int from report_checkin_entries(pg_temp.id('show'),true)),2,'include scratched option retained');
select is(pg_temp.due()*100,(select (r->>'due_cents')::numeric from jsonb_array_elements(public.get_show_finances(pg_temp.id('show'))->'exhibitors') r where r->>'exhibitor_id'=pg_temp.id('exhibitor')::text),'entry changes stay in sync with Show Finances');
-- Isolate fallback selection from maintenance: historical submitted carts must
-- be summed once; an existing authoritative entries balance takes precedence.
select set_config('ringmaster.manual_balance_refresh','on',true);
insert into entry_carts(id,show_id,status) values(pg_temp.id('receipt'),pg_temp.id('show'),'submitted'),(pg_temp.id('credit'),pg_temp.id('show'),'active');
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,balance_due_cents)
 values(gen_random_uuid(),pg_temp.id('show'),pg_temp.id('exhibitor'),pg_temp.id('receipt'),'cart',1200),
 (gen_random_uuid(),pg_temp.id('show'),pg_temp.id('exhibitor'),pg_temp.id('receipt'),'cart',300),
 (gen_random_uuid(),pg_temp.id('show'),pg_temp.id('exhibitor'),pg_temp.id('credit'),'cart',9900);
select is((select count(*)::int from report_checkin_entries(pg_temp.id('show'))),1,'multiple carts never duplicate entries');
select is(pg_temp.due(),(select balance_due_cents::numeric/100 from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('exhibitor')),'authoritative aggregate wins over cart totals');
delete from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('exhibitor');
select is(pg_temp.due(),15::numeric,'fallback sums submitted carts and excludes active cart');
select set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000099"}',true);
select throws_ok(format('select * from report_checkin_entries(%L)',pg_temp.id('show')),'42501',null,'unrelated user cannot read contact details or balances');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select lives_ok(format('select * from report_checkin_entries(%L)',pg_temp.id('show')),'server report worker remains authorized');
select ok(not has_function_privilege('anon','public.report_checkin_entries(uuid,boolean,uuid)','execute'),'anonymous access revoked');
select * from finish();
rollback;
