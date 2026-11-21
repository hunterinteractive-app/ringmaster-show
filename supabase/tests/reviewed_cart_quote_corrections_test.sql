begin;
set local search_path=public,extensions;
select no_plan();
create temporary table ids(k text primary key,id uuid default gen_random_uuid());
insert into ids(k) values('show'),('A'),('B'),('owner'),('recipient'),('cart'),('balance'),('class'),('fur'),('scratch'),('removed');
create function pg_temp.id(text) returns uuid language sql as $$select id from ids where k=$1$$;
select set_config('ringmaster.manual_balance_refresh','on',true);
insert into shows(id) values(pg_temp.id('show'));
insert into exhibitors(id) values(pg_temp.id('owner')),(pg_temp.id('recipient'));
insert into show_sections(id,show_id,kind,letter,is_enabled) select id,pg_temp.id('show'),'open',k,true from ids where k in('A','B');
insert into show_fee_settings(show_id,currency) values(pg_temp.id('show'),'usd');
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee) select id,4,2 from ids where k in('A','B');
insert into entry_carts(id,show_id,status,payment_status) values(pg_temp.id('cart'),pg_temp.id('show'),'submitted','unpaid');
insert into entry_cart_items(id,cart_id,exhibitor_id,section_id,is_fur) select id,pg_temp.id('cart'),pg_temp.id('owner'),pg_temp.id('A'),k='fur' from ids where k in('class','fur','scratch','removed');
insert into entries(id,show_id,section_id,exhibitor_id,source_cart_id,source_cart_item_id,is_fur,status,scratched_at)
 select gen_random_uuid(),pg_temp.id('show'),section_id,exhibitor_id,cart_id,id,is_fur,'submitted',case when id=pg_temp.id('scratch') then now() end from entry_cart_items where id<>pg_temp.id('removed');
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,currency,entry_count,fur_count,
 entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,addons_subtotal_cents,subtotal_before_discount_cents,
 discount_cents,calculated_total_cents,paid_online_cents,paid_manual_cents,refunded_cents,balance_due_cents,payment_status,section_breakdown)
 values(pg_temp.id('balance'),pg_temp.id('show'),pg_temp.id('owner'),pg_temp.id('cart'),'cart','usd',1,1,400,200,0,0,600,0,600,0,0,0,600,'unpaid',
 jsonb_build_array(jsonb_build_object('section_id',pg_temp.id('A'),'entry_count',1,'fur_count',1,'entries_subtotal_cents',400,'fur_subtotal_cents',200,'show_fee_cents',0)));
insert into show_finances_private.cart_quote_corrections(balance_id,show_id,original_balance,original_cart,quote_items,reason)
 select pg_temp.id('balance'),pg_temp.id('show'),'{"calculated_total_cents":0}','{}',jsonb_agg(to_jsonb(i)),'Reviewed active-only correction' from entry_cart_items i where id in(pg_temp.id('class'),pg_temp.id('fur'));
select set_config('ringmaster.manual_balance_refresh','off',true);
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('owner'));
select is((select balance_due_cents from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('owner')),600,'active class and fur billed at approved rates');
-- Paying a repaired quote must retain the existing replacement-credit rules.
savepoint replacement;
update entries set species='rabbit',created_at=now()-interval '1 day' where source_cart_item_id=pg_temp.id('class');
update show_exhibitor_balances set paid_online_cents=600 where id=pg_temp.id('balance');
update entries set scratched_at=clock_timestamp() where source_cart_item_id=pg_temp.id('class');
insert into entries(id,show_id,section_id,exhibitor_id,species,created_at,is_fur,status)
 values(gen_random_uuid(),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('owner'),'rabbit',clock_timestamp(),false,'entered');
select is((select (fee_snapshot->>'replacement_credit_cents')::int from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('owner')),400,'paid corrected quote still funds a class replacement');
select is((select balance_due_cents from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('owner')),0,'replacement does not charge again after corrected quote is paid');
rollback to replacement;
update entries set exhibitor_id=pg_temp.id('recipient'),section_id=pg_temp.id('B') where source_cart_item_id=pg_temp.id('class');
select is((select balance_due_cents from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('owner')),200,'original retains only fur charge');
select is((select balance_due_cents from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('recipient')),400,'class transfers at corrected price despite original extra items');
update entries set exhibitor_id=pg_temp.id('recipient') where source_cart_item_id=pg_temp.id('scratch');
select is((select sum(calculated_total_cents)::int from show_exhibitor_balances where source='entries'),600,'excluded scratch does not reappear when reassigned');
update show_exhibitor_balances set paid_online_cents=301,refunded_cents=7 where id=pg_temp.id('balance');
select is((select sum(paid_online_cents)::int from show_exhibitor_balances where source='entries'),301,'later receipt allocation conserves odd cents');
select is((select sum(refunded_cents)::int from show_exhibitor_balances where source='entries'),7,'refund allocation conserves odd cents');
update entries set exhibitor_id=pg_temp.id('recipient'),section_id=pg_temp.id('B') where source_cart_item_id=pg_temp.id('fur');
select is((select balance_due_cents from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('recipient')),306,'class and fur transfer carries exact receipt and refund');
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('recipient'));
select is((select balance_due_cents from show_exhibitor_balances where source='entries' and exhibitor_id=pg_temp.id('recipient')),306,'maintenance retains corrected balance');
select is((select count(*)::int from entry_cart_items),4,'original checkout items preserved including exclusions');
select is((select (original_balance->>'calculated_total_cents')::int from show_finances_private.cart_quote_corrections),0,'original zero quote preserved for audit');
select ok(not has_table_privilege('authenticated','show_finances_private.cart_quote_corrections','INSERT'),'clients cannot authorize their own repricing');
select ok(not has_table_privilege('anon','show_finances_private.cart_quote_corrections','SELECT'),'private audit unavailable anonymously');
select * from finish();
rollback;
