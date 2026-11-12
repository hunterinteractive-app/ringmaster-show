-- Run in the isolated manual_entry_balances_fixture.sql database, with the
-- migration under test and the current scoped report function installed.
begin;
set local search_path=public,extensions;
select no_plan();
create temporary table ids(k text primary key,id uuid default gen_random_uuid());
insert into ids(k) values('show'),('A'),('B'),('Margie'),('Richard'),('paid'),('cart'),('cartbalance'),('code');
create function pg_temp.id(text) returns uuid language sql as $$ select id from ids where k=$1 $$;
create function pg_temp.due(text) returns integer language sql as $$ select balance_due_cents from public.show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id($1) $$;
insert into shows(id,name) values(pg_temp.id('show'),'Manual entry regression');
insert into show_sections(id,show_id,kind,letter,sort_order,is_enabled) select id,pg_temp.id('show'),'open',k,case k when 'A' then 1 else 2 end,true from ids where k in ('A','B');
insert into show_fee_settings(show_id,currency) values(pg_temp.id('show'),'usd');
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee,fee_per_show) select id,5,1,0 from ids where k in ('A','B');
insert into exhibitors(id,display_name) select id,k from ids where k in ('Margie','Richard','paid');
insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) select gen_random_uuid(),pg_temp.id('show'),s.id,e.id,'entered',false from ids s cross join ids e cross join generate_series(1,5) n where s.k in ('A','B') and e.k='Margie';
insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) select gen_random_uuid(),pg_temp.id('show'),id,pg_temp.id('Richard'),'entered',false from ids where k in ('A','B');
select is(pg_temp.due('Margie'),5000,'10 manual entries produce $50 without email or checkout');
select is(pg_temp.due('Richard'),1000,'2 manual entries produce $10');
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Margie'));
select is(pg_temp.due('Margie'),5000,'repeated backfill is idempotent');
select is((select count(*)::int from show_exhibitor_balances),2,'one authoritative snapshot per exhibitor');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select sum((r->>'balance_due_cents')::int)::int from public.report_show_exhibitor_balances_scoped(pg_temp.id('show'),array[pg_temp.id('A'),pg_temp.id('B')],false) r),6000,'unpaid report includes both missing exhibitors');
select is((select sum((r->>'balance_due_cents')::int)::int from public.report_show_exhibitor_balances_scoped(pg_temp.id('show'),array[pg_temp.id('A')],false) r),3000,'section report includes only Open A fees');
update entries set scratched_at=now() where exhibitor_id=pg_temp.id('Richard') and section_id=pg_temp.id('B');
select is(pg_temp.due('Richard'),500,'scratch removes unpaid fee');
update entries set scratched_at=null where exhibitor_id=pg_temp.id('Richard');
select is(pg_temp.due('Richard'),1000,'unscratch restores unpaid fee');
delete from entries where exhibitor_id=pg_temp.id('Richard') and section_id=pg_temp.id('B');
select is(pg_temp.due('Richard'),500,'delete removes fee');
update entries set section_id=pg_temp.id('B') where exhibitor_id=pg_temp.id('Richard');
select is(pg_temp.due('Richard'),500,'moving section does not duplicate balance');
insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) values(gen_random_uuid(),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('Richard'),'entered',true);
select is(pg_temp.due('Richard'),600,'fur uses fur fee');
update show_section_fee_settings set fee_per_show=2 where section_id=pg_temp.id('B');
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Richard'));
select is(pg_temp.due('Richard'),800,'per-show fee assessed once per section');
insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) values(gen_random_uuid(),pg_temp.id('show'),pg_temp.id('B'),pg_temp.id('Richard'),'entered',false);
select is(pg_temp.due('Richard'),1300,'second entry does not duplicate per-section show fee');
-- Legacy check-in receipts must survive manual entry edits.
update show_exhibitor_balances set paid_manual_cents=500 where exhibitor_id=pg_temp.id('Richard');
select is(pg_temp.due('Richard'),800,'legacy manual receipt preserved and balance updated');
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Richard'));
select is(pg_temp.due('Richard'),800,'manual receipt not lost or counted twice on refresh');
-- Frozen paid quote plus new manual entries.
insert into entry_carts(id,show_id,status) values(pg_temp.id('cart'),pg_temp.id('show'),'submitted');
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,entry_count,discount_cents,paid_online_cents,paid_manual_cents,refunded_cents,addons_subtotal_cents,calculated_total_cents,balance_due_cents,section_breakdown)
values(pg_temp.id('cartbalance'),pg_temp.id('show'),pg_temp.id('paid'),pg_temp.id('cart'),'cart',2,100,900,0,0,0,900,0,
 jsonb_build_array(jsonb_build_object('section_id',pg_temp.id('A'),'kind','open','letter','A','entry_count',2,'entries_subtotal_cents',1000)));
create temporary table frozen as select to_jsonb(b) row from show_exhibitor_balances b where id=pg_temp.id('cartbalance');
insert into entries(id,show_id,section_id,exhibitor_id,source_cart_id,status,is_fur) select gen_random_uuid(),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('paid'),pg_temp.id('cart'),'entered',false from generate_series(1,2);
select is((select count(*)::int from show_exhibitor_balances where exhibitor_id=pg_temp.id('paid') and source='entries'),0,'cart-only checkout retains existing path');
insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) values(gen_random_uuid(),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('paid'),'entered',false);
select is(pg_temp.due('paid'),500,'paid cart plus manual entry owes only new fee');
select is((select to_jsonb(b) from show_exhibitor_balances b where id=pg_temp.id('cartbalance')),(select row from frozen),'manual refresh does not modify frozen cart quote');
insert into show_payments(id,show_id,exhibitor_id,balance_id,status,amount_cents,total_cents,provider,payment_type,refunded_cents)
select gen_random_uuid(),pg_temp.id('show'),pg_temp.id('paid'),id,'paid',300,300,'manual','manual',0 from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('paid');
-- Simulate the existing payment allocation write, which only sums its own ledger.
update show_exhibitor_balances set paid_online_cents=0,paid_manual_cents=300 where source='entries' and exhibitor_id=pg_temp.id('paid');
select is(pg_temp.due('paid'),200,'manual allocation retains credit from earlier paid cart');
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('paid'));
select is(pg_temp.due('paid'),200,'combined payments stay idempotent');
update show_payments set status='partially_refunded',refunded_cents=100 where exhibitor_id=pg_temp.id('paid');
update show_exhibitor_balances set refunded_cents=100 where source='entries' and exhibitor_id=pg_temp.id('paid');
select is(pg_temp.due('paid'),300,'partial refund is counted once');
update show_exhibitor_balances set paid_online_cents=1000 where id=pg_temp.id('cartbalance');
select is(pg_temp.due('paid'),200,'cart payment changes refresh combined balance');
-- Best cumulative code is shared with checkout, without repeating old savings.
insert into entry_discount_private.codes(id,discount_type,value,basis,enabled) values(pg_temp.id('code'),'amount',1,'per_entry',true);
insert into entry_discount_private.accepted_codes(show_id,exhibitor_id,code_id) values(pg_temp.id('show'),pg_temp.id('paid'),pg_temp.id('code'));
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('paid'));
select is(pg_temp.due('paid'),0,'best cumulative discount deducts only remaining savings');
select is((select discount_cents from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('paid')),300,'discount combines existing $1 with remaining $2');
select is(pg_temp.due('Margie'),5000,'unrelated exhibitor balance remains unchanged');
select ok(not has_function_privilege('authenticated','manual_entry_balances_private.refresh(uuid,uuid)','execute'),'clients cannot call private balance maintenance');
select ok(not has_schema_privilege('anon','manual_entry_balances_private','usage'),'anonymous users cannot access private schema');
select set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000002"}',true);
select throws_ok($$select * from public.report_show_exhibitor_balances_scoped(pg_temp.id('show'),array[pg_temp.id('A')],false)$$,'42501','You do not have access to this show','unrelated users cannot read balances');
delete from entries where exhibitor_id=pg_temp.id('Margie');
select is(pg_temp.due('Margie'),0,'deleting last manual entry clears snapshot');
select * from finish();
rollback;
