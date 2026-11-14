begin;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
create temporary table ids(k text primary key,id uuid default gen_random_uuid());
insert into ids(k) values('show'),('other show'),('A'),('B'),('Youth'),('Lindy'),('Shane'),('Sara'),('Shellie'),('Manual'),('cart1'),('cart2'),('cart3'),('b1'),('b2'),('b3'),('receipt'),('credit');
create function pg_temp.id(text) returns uuid language sql as $$select id from ids where k=$1$$;
create function pg_temp.balance(text) returns jsonb language sql as $$select to_jsonb(b) from show_exhibitor_balances b where b.source='entries' and b.exhibitor_id=pg_temp.id($1)$$;
insert into shows(id,name) select id,k from ids where k in ('show','other show');
insert into exhibitors(id,display_name) select id,k from ids where k in ('Lindy','Shane','Sara','Shellie','Manual');
insert into show_sections(id,show_id,kind,letter,is_enabled,sort_order) select id,pg_temp.id('show'),case when k='Youth' then 'youth' else 'open' end,k,true,1 from ids where k in ('A','B','Youth');
insert into show_fee_settings(show_id,currency) values(pg_temp.id('show'),'usd');
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee,fee_per_show) select id,5,1,0 from ids where k in ('A','B','Youth');
insert into entry_carts(id,show_id,status) select id,pg_temp.id('show'),'submitted' from ids where k like 'cart%';
-- Reproduce the verified payment provenance without storing customer details.
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,is_fur)
 select gen_random_uuid(),pg_temp.id('cart1'),s.id,pg_temp.id('Shane'),false from ids s cross join generate_series(1,8) n where s.k in ('A','B');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,is_fur)
 select gen_random_uuid(),pg_temp.id('cart2'),s.id,pg_temp.id('Shellie'),n>8 from ids s cross join generate_series(1,14) n where s.k in ('A','B');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,is_fur)
 select gen_random_uuid(),pg_temp.id('cart3'),s.id,pg_temp.id('Sara'),n>3 from ids s cross join generate_series(1,5) n where s.k in ('A','B');
insert into show_payment_sessions(id,cart_id,status,quote_snapshot)
 select gen_random_uuid(),cart_id,'paid',jsonb_build_object('cart_items',jsonb_agg(to_jsonb(i))) from entry_cart_items i group by cart_id;
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,currency,entry_count,fur_count,
 entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,subtotal_before_discount_cents,discount_cents,calculated_total_cents,
 paid_online_cents,paid_manual_cents,refunded_cents,addons_subtotal_cents,balance_due_cents,section_breakdown)
 select pg_temp.id(case cart_id when pg_temp.id('cart1') then 'b1' when pg_temp.id('cart2') then 'b2' else 'b3' end),pg_temp.id('show'),exhibitor_id,cart_id,'cart','usd',
 sum(ec),sum(fc),sum(ec)*500,sum(fc)*100,0,sum(ec)*500+sum(fc)*100,0,sum(ec)*500+sum(fc)*100,sum(ec)*500+sum(fc)*100,0,0,0,0,
 jsonb_agg(jsonb_build_object('section_id',section_id,'entry_count',ec,'fur_count',fc,'entries_subtotal_cents',ec*500,'fur_subtotal_cents',fc*100,'show_fee_cents',0))
 from (select cart_id,exhibitor_id,section_id,count(*) filter(where not is_fur) ec,count(*) filter(where is_fur) fc from entry_cart_items group by cart_id,exhibitor_id,section_id) q group by cart_id,exhibitor_id;
insert into show_payments(id,show_id,exhibitor_id,balance_id,cart_id,provider,payment_method,payment_type,status,amount_cents,total_cents,refunded_cents)
 select gen_random_uuid(),show_id,exhibitor_id,id,entry_cart_id,'stripe','stripe','entry','paid',calculated_total_cents,calculated_total_cents,0 from show_exhibitor_balances where source='cart';
insert into entries(id,show_id,section_id,exhibitor_id,source_cart_id,source_cart_item_id,is_fur,status)
 select gen_random_uuid(),pg_temp.id('show'),section_id,exhibitor_id,cart_id,id,is_fur,'entered' from entry_cart_items;
select is((pg_temp.balance('Shane')->>'paid_online_cents')::int,8000,'original payer received the $80 credit');
update entries set exhibitor_id=pg_temp.id('Lindy') where source_cart_id=pg_temp.id('cart1');
select is((pg_temp.balance('Lindy')->>'paid_online_cents')::int,8000,'Lindy receives the existing $80 allocation');
select is((pg_temp.balance('Lindy')->>'balance_due_cents')::int,0,'Lindy owes $0');
select is((pg_temp.balance('Shane')->>'paid_online_cents')::int,0,'original payer does not retain the transferred $80');
select is((pg_temp.balance('Shane')->>'calculated_total_cents')::int,0,'original payer no longer carries transferred charges');
with picked as (select id,row_number() over(partition by section_id,is_fur order by id) rn from entries where source_cart_id=pg_temp.id('cart2'))
 update entries set exhibitor_id=pg_temp.id('Sara') where id in (select id from picked where rn=1);
select is((pg_temp.balance('Sara')->>'calculated_total_cents')::int,4600,'Sara has $46 of charges including reassigned fur');
select is((pg_temp.balance('Sara')->>'paid_online_cents')::int,4600,'Sara receives $12 from prior checkout plus her $34 receipt');
select is((pg_temp.balance('Sara')->>'balance_due_cents')::int,0,'Sara owes $0');
select is((pg_temp.balance('Shellie')->>'paid_online_cents')::int,8000,'Shellie retains exactly $80');
select is((select sum(paid_online_cents)::int from show_exhibitor_balances where source='entries'),20600,'aggregate paid conserves the $206 actually collected');
select is((select sum(amount_cents)::int from show_payments),20600,'receipt ledger is unchanged');
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Sara'));
select is((pg_temp.balance('Sara')->>'paid_online_cents')::int,4600,'repeated refresh is idempotent');
update show_section_fee_settings set fee_per_entry=20;
update entries set section_id=pg_temp.id('Youth') where exhibitor_id=pg_temp.id('Sara') and section_id=pg_temp.id('A');
select is((pg_temp.balance('Sara')->>'calculated_total_cents')::int,4600,'Open to Youth carries original price rather than charging again');
select is((pg_temp.balance('Sara')->>'balance_due_cents')::int,0,'Open to Youth keeps payment');
-- Round trip uses the actual entries update path used by both admin Move and My Entries.
create temporary table saved_links as select id,source_cart_id,source_cart_item_id,payment_session_id from entries;
update entries set section_id=pg_temp.id('A') where exhibitor_id=pg_temp.id('Sara') and section_id=pg_temp.id('Youth');
select is((pg_temp.balance('Sara')->>'balance_due_cents')::int,0,'Youth to Open keeps payment');
select is((pg_temp.balance('Sara')->>'calculated_total_cents')::int,4600,'Youth to Open retains frozen price');
select is((select count(*)::int from entries e join saved_links s using(id) where (e.source_cart_id,e.source_cart_item_id,e.payment_session_id) is distinct from (s.source_cart_id,s.source_cart_item_id,s.payment_session_id)),0,'round-trip section moves retain every checkout link');
select throws_ok(format('update entries set source_cart_id=null,source_cart_item_id=null where exhibitor_id=%L',pg_temp.id('Sara')),'23514',null,'cannot detach checkout while moving an entry');
select throws_ok(format('update entries set source_cart_item_id=gen_random_uuid() where exhibitor_id=%L',pg_temp.id('Sara')),'23514',null,'cannot replace original checkout item');
select throws_ok(format('update entries set show_id=%L where exhibitor_id=%L',pg_temp.id('other show'),pg_temp.id('Sara')),'23514',null,'cannot move a paid checkout entry into another show');
update entries set section_id=pg_temp.id('Youth') where exhibitor_id=pg_temp.id('Sara') and section_id=pg_temp.id('A');
update show_section_fee_settings set fee_per_entry=5;
-- Refunds and partial payments conserve cents and refresh all recipients.
update show_exhibitor_balances set refunded_cents=901 where id=pg_temp.id('b2');
select is((select sum(refunded_cents)::int from show_exhibitor_balances where source='entries'),901,'partial refund allocated exactly once');
update show_exhibitor_balances set paid_online_cents=4601 where id=pg_temp.id('b2');
select is((select sum(paid_online_cents)::int from show_exhibitor_balances where source='entries'),16001,'odd-cent partial receipt conserved');
-- Manual payments are receipts, credits are not receipts.
insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) select gen_random_uuid(),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('Manual'),'entered',false from generate_series(1,2);
select public.record_show_finance_payment(pg_temp.id('show'),pg_temp.id('Manual'),400,'venmo','2026-01-01T12:00:00Z','Received from member',pg_temp.id('receipt'));
select is((pg_temp.balance('Manual')->>'paid_manual_cents')::int,400,'Venmo is classified as an external manual receipt');
select is((pg_temp.balance('Manual')->>'balance_due_cents')::int,600,'partial external receipt reduces due');
select public.record_show_finance_payment(pg_temp.id('show'),pg_temp.id('Manual'),400,'venmo','2026-01-01T12:00:00Z','Received from member',pg_temp.id('receipt'));
select is((pg_temp.balance('Manual')->>'paid_manual_cents')::int,400,'retry does not duplicate receipt');
select throws_ok(format('select public.record_show_finance_payment(%L,%L,401,%L,%L,%L,%L)',pg_temp.id('show'),pg_temp.id('Manual'),'venmo','2026-01-01T12:00:00Z','Received from member',pg_temp.id('receipt')),'22023',null,'idempotency key cannot be reused for a different amount');
select throws_ok(format('select public.record_show_finance_payment(%L,%L,700,%L,now(),%L,gen_random_uuid())',pg_temp.id('show'),pg_temp.id('Manual'),'zelle','receipt'),'22023',null,'overpayment blocked');
select public.credit_show_finance_balance(pg_temp.id('show'),pg_temp.id('Manual'),100,'Secretary waived charge',pg_temp.id('credit'));
select is((pg_temp.balance('Manual')->>'balance_due_cents')::int,500,'audited credit reduces amount owed');
select is((pg_temp.balance('Manual')->>'paid_manual_cents')::int,400,'credit is not counted as money collected');
select public.credit_show_finance_balance(pg_temp.id('show'),pg_temp.id('Manual'),100,'Secretary waived charge',pg_temp.id('credit'));
select is((pg_temp.balance('Manual')->>'balance_due_cents')::int,500,'credit retry is idempotent');
select public.record_checkin_manual_payment(pg_temp.id('show'),pg_temp.id('Manual'),500,'paypal','Final receipt');
select is((pg_temp.balance('Manual')->>'balance_due_cents')::int,0,'existing Check-In writer uses corrected authoritative balance');
select is((pg_temp.balance('Manual')->>'paid_manual_cents')::int,900,'PayPal remains a manual receipt');
update entries set section_id=pg_temp.id('Youth') where exhibitor_id=pg_temp.id('Manual');
select is((pg_temp.balance('Manual')->>'balance_due_cents')::int,0,'manual receipt survives Open to Youth');
update entries set section_id=pg_temp.id('A') where exhibitor_id=pg_temp.id('Manual');
select is((pg_temp.balance('Manual')->>'paid_manual_cents')::int,900,'manual receipt survives Youth to Open without duplication');

select is((public.get_show_checkin_payment_context(pg_temp.id('show'),pg_temp.id('Lindy'))->>'balance_due_cents')::int,0,'Check-In does not double-count carts and aggregates');
select is(jsonb_array_length(public.get_show_finances(pg_temp.id('show'))->'exhibitors'),5,'finances selects one authoritative row per exhibitor');
select ok(jsonb_array_length(public.get_show_finance_history(pg_temp.id('show'),pg_temp.id('Lindy'))->'payments')=1,'history exposes the original payer receipt through its allocation');
select is((select sum((r->>'paid_online_cents')::int)::int from report_show_exhibitor_balances_scoped(pg_temp.id('show'),array[pg_temp.id('A'),pg_temp.id('B'),pg_temp.id('Youth')],false) r),16001,'reports agree with finance receipt allocation');
-- Invalid writes, explicit credits, and upgrade from a reviewed live repair.
select throws_ok(format('select public.record_show_finance_payment(%L,%L,1,%L,now(),null,gen_random_uuid())',pg_temp.id('show'),pg_temp.id('Manual'),'invalid'),'22023',null,'invalid method rejected');
select throws_ok(format('select public.record_show_finance_payment(%L,%L,1,%L,now()+interval ''1 day'',null,gen_random_uuid())',pg_temp.id('show'),pg_temp.id('Manual'),'zelle'),'22023',null,'future receipt date rejected');
select throws_ok(format('select public.credit_show_finance_balance(%L,%L,1,%L,gen_random_uuid())',pg_temp.id('show'),pg_temp.id('Manual'),'x'),'22023',null,'credit requires an explanatory reason');
select is((select (r->>'balance_due_cents')::integer from report_show_exhibitor_balances_scoped(pg_temp.id('show'),array[pg_temp.id('A'),pg_temp.id('B'),pg_temp.id('Youth')],false) r where r->>'exhibitor_id'=pg_temp.id('Manual')::text),0,'full-show report includes the credit');
delete from show_finances_private.legacy_receipts where exhibitor_id in (pg_temp.id('Sara'),pg_temp.id('Lindy'));
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Sara'));
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Lindy'));
select is((select sum(paid_online_cents)::integer from show_exhibitor_balances where source='entries'),16001,'deployment after an earlier repaired allocation cannot duplicate credit');
select is((select sum(online_cents)::integer from show_finances_private.legacy_receipts),0,'allocated receipts are never captured as legacy money');
-- Fully transferred cart with a frozen entry discount and a show fee: the
-- per-exhibitor show fee stays with the original payer, entry discount follows entries.
update show_exhibitor_balances set discount_cents=1600,subtotal_before_discount_cents=8500,
 calculated_total_cents=6900,paid_online_cents=6900,show_fee_subtotal_cents=500,
 section_breakdown=(select jsonb_agg(s||jsonb_build_object('show_fee_cents',250)) from jsonb_array_elements(section_breakdown) s)
 where id=pg_temp.id('b1');
select is((pg_temp.balance('Lindy')->>'calculated_total_cents')::integer,6400,'frozen entry discount follows transferred entries');
select is((pg_temp.balance('Shane')->>'calculated_total_cents')::integer,500,'one-time section fees remain with original exhibitor');
select is((pg_temp.balance('Lindy')->>'balance_due_cents')::integer,0,'discounted transfer is still fully paid');
-- A full refunded checkout's matching credit must not create a new debt.
update show_exhibitor_balances set discount_cents=8000,subtotal_before_discount_cents=8000,
 calculated_total_cents=0,paid_online_cents=8000,refunded_cents=8000,show_fee_subtotal_cents=0,
 section_breakdown=(select jsonb_agg(s||jsonb_build_object('show_fee_cents',0)) from jsonb_array_elements(section_breakdown) s)
 where id=pg_temp.id('b1');
select is((pg_temp.balance('Lindy')->>'balance_due_cents')::integer,0,'fully refunded credited entries owe nothing');
select is((select sum(refunded_cents)::integer from show_exhibitor_balances where source='entries'),8901,'full and partial refunds still conserved');
-- Existing refund writer order: balance credit, receipt refund, entry removal.
-- No intermediate refresh may erase the just-recorded refund credit.
insert into exhibitors(id,display_name) values(gen_random_uuid(),'Refund fixture');
insert into ids(k,id) select 'Refund',id from exhibitors where display_name='Refund fixture';
insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) select gen_random_uuid(),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('Refund'),'entered',false from generate_series(1,2);
select public.record_show_finance_payment(pg_temp.id('show'),pg_temp.id('Refund'),1000,'cash','2026-01-01T12:00:00Z',null,gen_random_uuid());
select set_config('ringmaster.payment_state_write','on',true);
update show_exhibitor_balances set discount_cents=500,calculated_total_cents=500,refunded_cents=500,
 fee_snapshot=fee_snapshot||jsonb_build_object('entry_refund_credit_cents',500) where exhibitor_id=pg_temp.id('Refund');
select is((pg_temp.balance('Refund')->>'refunded_cents')::integer,500,'refund credit survives intermediate balance update');
update show_payments set refunded_cents=500,status='partially_refunded' where exhibitor_id=pg_temp.id('Refund');
delete from entries where id=(select id from entries where exhibitor_id=pg_temp.id('Refund') limit 1);
select set_config('ringmaster.payment_state_write','off',true);
select is((pg_temp.balance('Refund')->>'calculated_total_cents')::integer,500,'refunded entry removal reduces the charge once');
select is((pg_temp.balance('Refund')->>'balance_due_cents')::integer,0,'manual refund completion does not create debt');
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Refund'));
select is((pg_temp.balance('Refund')->>'balance_due_cents')::integer,0,'manual refund stays correct on later refresh');
-- Six recreated Youth entries regain their original Open checkout; obsolete
-- unpaid cart line is removed without fabricating a receipt or touching siblings.
insert into ids(k) values('Parent'),('Child'),('Sibling'),('repaircart'),('stale');
insert into exhibitors(id,display_name) select id,k from ids where k in ('Parent','Child','Sibling');
insert into entry_carts(id,show_id,status) values(pg_temp.id('repaircart'),pg_temp.id('show'),'submitted');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,is_fur)
 select gen_random_uuid(),pg_temp.id('repaircart'),pg_temp.id('A'),e.id,false from ids e cross join generate_series(1,6) n where k in ('Parent','Sibling');
insert into show_payment_sessions(id,cart_id,status,quote_snapshot)
 select gen_random_uuid(),pg_temp.id('repaircart'),'paid',jsonb_build_object('cart_items',jsonb_agg(to_jsonb(i))) from entry_cart_items i where cart_id=pg_temp.id('repaircart');
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,currency,entry_count,fur_count,
 entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,subtotal_before_discount_cents,discount_cents,calculated_total_cents,
 paid_online_cents,paid_manual_cents,refunded_cents,addons_subtotal_cents,balance_due_cents,section_breakdown)
 select gen_random_uuid(),pg_temp.id('show'),id,pg_temp.id('repaircart'),'cart','usd',6,0,3000,0,0,3000,0,3000,3000,0,0,0,0,
 jsonb_build_array(jsonb_build_object('section_id',pg_temp.id('A'),'entry_count',6,'fur_count',0,'entries_subtotal_cents',3000,'fur_subtotal_cents',0,'show_fee_cents',0))
 from ids where k in ('Parent','Sibling');
insert into show_payments(id,show_id,exhibitor_id,balance_id,cart_id,provider,payment_method,payment_type,status,amount_cents,total_cents,refunded_cents)
 select gen_random_uuid(),show_id,exhibitor_id,id,entry_cart_id,'stripe','stripe','entry','paid',3000,3000,0 from show_exhibitor_balances where entry_cart_id=pg_temp.id('repaircart');
insert into entries(id,show_id,section_id,exhibitor_id,source_cart_id,source_cart_item_id,is_fur,status)
 select gen_random_uuid(),pg_temp.id('show'),section_id,exhibitor_id,cart_id,id,false,'entered' from entry_cart_items where exhibitor_id=pg_temp.id('Sibling');
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,currency,entry_count,fur_count,entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,subtotal_before_discount_cents,discount_cents,calculated_total_cents,paid_online_cents,paid_manual_cents,refunded_cents,addons_subtotal_cents,balance_due_cents,section_breakdown)
 values(pg_temp.id('stale'),pg_temp.id('show'),pg_temp.id('Child'),pg_temp.id('repaircart'),'cart','usd',1,0,500,0,0,500,0,500,0,0,0,0,500,jsonb_build_array(jsonb_build_object('section_id',pg_temp.id('Youth'),'entry_count',1,'entries_subtotal_cents',500)));
create temporary table repair_links as select gen_random_uuid() entry_id,id item_id from entry_cart_items where exhibitor_id=pg_temp.id('Parent');
insert into entries(id,show_id,section_id,exhibitor_id,is_fur,status) select entry_id,pg_temp.id('show'),pg_temp.id('Youth'),pg_temp.id('Child'),false,'entered' from repair_links;
select is((pg_temp.balance('Child')->>'balance_due_cents')::int,3500,'recreated entries plus stale cart reproduce $35 balance');
create temporary table repair_receipts as select to_jsonb(p) data from show_payments p;
select set_config('ringmaster.manual_balance_refresh','on',true);
update show_exhibitor_balances set entry_count=0,entries_subtotal_cents=0,subtotal_before_discount_cents=0,calculated_total_cents=0,balance_due_cents=0,section_breakdown='[]' where id=pg_temp.id('stale');
update entries e set source_cart_id=pg_temp.id('repaircart'),source_cart_item_id=r.item_id from repair_links r where e.id=r.entry_id;
select set_config('ringmaster.manual_balance_refresh','off',true);
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Child'));
select manual_entry_balances_private.refresh(pg_temp.id('show'),pg_temp.id('Parent'));
select is((pg_temp.balance('Child')->>'entry_count')::int,6,'repair counts the six entries once');
select is((pg_temp.balance('Child')->>'calculated_total_cents')::int,3000,'repair removes the obsolete $5');
select is((pg_temp.balance('Child')->>'paid_online_cents')::int,3000,'repair restores original $30 payment');
select is((pg_temp.balance('Child')->>'balance_due_cents')::int,0,'repaired child owes zero');
select is((pg_temp.balance('Parent')->>'paid_online_cents')::int,0,'original payer does not keep duplicate allocated credit');
select is((pg_temp.balance('Sibling')->>'paid_online_cents')::int,3000,'sibling payment remains unchanged');
select is(jsonb_array_length(public.get_show_finance_history(pg_temp.id('show'),pg_temp.id('Child'))->'payments'),1,'shared-cart history excludes sibling receipts with zero allocation');
select is(jsonb_array_length(public.get_show_finance_history(pg_temp.id('show'),pg_temp.id('Child'))->'allocations'),1,'history includes only nonzero allocated payments');
select is((select count(*)::int from ((select to_jsonb(p) from show_payments p except select data from repair_receipts) union all (select data from repair_receipts except select to_jsonb(p) from show_payments p)) d),0,'repair leaves original receipts byte-for-byte intact');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
select throws_ok(format('select public.get_show_finances(%L)',pg_temp.id('show')),'42501',null,'unauthorized finance read denied');
select throws_ok(format('select public.get_show_finance_history(%L,%L)',pg_temp.id('show'),pg_temp.id('Lindy')),'42501',null,'unauthorized history denied');
select throws_ok(format('select public.record_show_finance_payment(%L,%L,100,%L,now(),null,gen_random_uuid())',pg_temp.id('show'),pg_temp.id('Manual'),'cash'),'42501',null,'unauthorized receipt denied');
select throws_ok(format('select public.credit_show_finance_balance(%L,%L,100,%L,gen_random_uuid())',pg_temp.id('show'),pg_temp.id('Manual'),'waiver'),'42501',null,'unauthorized credit denied');
select ok(not has_function_privilege('anon','public.get_show_finances(uuid)','execute'),'anonymous RPC execution revoked');
select ok(not has_schema_privilege('authenticated','show_finances_private','usage'),'private ledger inaccessible directly');
select * from finish();
rollback;
