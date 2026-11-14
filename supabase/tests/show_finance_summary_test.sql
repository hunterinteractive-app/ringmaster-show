begin;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
create function pg_temp.id(text) returns uuid language sql as $$select md5($1)::uuid$$;
insert into shows(id,name) values(pg_temp.id('summary show'),'Summary fixture');
insert into exhibitors(id,first_name,last_name,showing_name) values
 (pg_temp.id('Ada'),'Ada','Miller','AAA Rabbitry'),
 (pg_temp.id('Zoe'),'Zoe','Adams','ZZZ Rabbitry'),
 (pg_temp.id('Bea'),'Bea','Adams','Bea Adams'),
 (pg_temp.id('Nameless'),null,null,'Cedar Rabbitry');
insert into show_exhibitor_balances(id,show_id,exhibitor_id,source,currency,calculated_total_cents,
 paid_online_cents,paid_manual_cents,refunded_cents,balance_due_cents,fee_snapshot)
 select gen_random_uuid(),pg_temp.id('summary show'),id,'entries','usd',1000,0,0,0,1000,'{}'
 from exhibitors;
select is(public.get_show_finances(pg_temp.id('summary show'))->'exhibitors'->0->>'name','Bea Adams','last name then first name overrides showing name');
select is(public.get_show_finances(pg_temp.id('summary show'))->'exhibitors'->1->>'name','ZZZ Rabbitry','display name stays intact when sorting by saved surname');
select is(public.get_show_finances(pg_temp.id('summary show'))->'exhibitors'->2->>'name','Cedar Rabbitry','blank surname falls back to showing name');
select is(public.get_show_finances(pg_temp.id('summary show'))->'exhibitors'->3->>'last_name','Miller','RPC returns saved surname');

-- Discounts use the same authoritative rows as charges and never include credits.
update show_exhibitor_balances set discount_cents=250,fee_snapshot='{"finance_credit_cents":100}'
 where show_id=pg_temp.id('summary show') and source='entries';
insert into entry_carts(id,show_id,status) values
 (pg_temp.id('duplicate cart'),pg_temp.id('summary show'),'submitted'),
 (pg_temp.id('draft cart'),pg_temp.id('summary show'),'draft');
-- Seed legacy/draft balance snapshots without invoking allocation refresh.
alter table show_exhibitor_balances disable trigger user;
insert into show_exhibitor_balances(id,show_id,exhibitor_id,source,currency,cart_id,discount_cents)
 values(gen_random_uuid(),pg_temp.id('summary show'),pg_temp.id('Ada'),'cart','usd',pg_temp.id('duplicate cart'),9000),
 (gen_random_uuid(),pg_temp.id('summary show'),pg_temp.id('Zoe'),'cart','usd',pg_temp.id('draft cart'),8000);
alter table show_exhibitor_balances enable trigger user;
select is((public.get_show_finances(pg_temp.id('summary show'))->'summaries'->0->>'discount_cents')::int,1000,
 'discount total excludes duplicate cart, draft cart, and manual credits');
select is((public.get_show_finances(pg_temp.id('summary show'))->'exhibitors'->0->>'discount_cents')::int,250,
 'RPC returns applied discount for each exhibitor');

create temporary table summary_rows(data jsonb);
insert into summary_rows values('[{"currency":"usd","charges_cents":14000,"online_cents":10000,"manual_cents":2000,"refunded_cents":0,"due_cents":2000}]');
create function pg_temp.summary() returns jsonb language sql as $$
 select show_finances_private.summary(pg_temp.id('summary show'),data)->0 from summary_rows
$$;
-- Two household allocations of ONE charge; processor fixed fee charged once.
insert into show_payment_sessions(id,status,quote_snapshot) values(pg_temp.id('session'),'paid',
 '{"currency":"usd","expected_amount_cents":10550,"platform_fee_cents":211,"processing_fee_rate":0.029,"processing_fee_fixed_cents":30}');
insert into show_payments(id,show_id,exhibitor_id,currency,provider,status,payment_type,amount_cents,total_cents,
 online_fee_cents,payment_session_id,provider_payment_id,application_fee_refunded_cents,created_at)
 values
 (pg_temp.id('receipt1'),pg_temp.id('summary show'),pg_temp.id('Ada'),'usd','stripe','paid','entry',4000,4000,220,pg_temp.id('session'),'pi_family',0,now()),
 (pg_temp.id('receipt2'),pg_temp.id('summary show'),pg_temp.id('Zoe'),'usd','stripe','paid','entry',6000,6000,330,pg_temp.id('session'),'pi_family',0,now());
select is((pg_temp.summary()->>'online_fee_cents')::int,550,'fees from both family allocations counted');
select is((pg_temp.summary()->>'estimated_payment_cost_cents')::int,547,'processor fixed charge counted once per checkout');
select is((pg_temp.summary()->>'club_earned_cents')::int,12003,'net includes manual receipt and fee coverage but excludes $20 unpaid');
select is((pg_temp.summary()->>'charges_cents')::int,14000,'show charges exclude payment fees');
select is((pg_temp.summary()->>'due_cents')::int,2000,'waiting reflects authoritative balances');
-- Parent + duplicate receipt representation + incomplete attempts must not inflate fees.
insert into show_payments(id,show_id,exhibitor_id,currency,provider,status,payment_type,amount_cents,
 online_fee_cents,provider_payment_id,created_at)
 values
 (gen_random_uuid(),pg_temp.id('summary show'),pg_temp.id('Ada'),'usd','stripe','paid','legacy_cart_parent',10000,550,'pi_family',now()),
 (gen_random_uuid(),pg_temp.id('summary show'),pg_temp.id('Ada'),'usd','stripe','paid','entry',4000,220,'pi_family',now()-interval '1 day'),
 (gen_random_uuid(),pg_temp.id('summary show'),pg_temp.id('Ada'),'usd','stripe','pending','entry',9000,900,'pi_pending',now()),
 (gen_random_uuid(),pg_temp.id('summary show'),pg_temp.id('Ada'),'usd','stripe','cancelled','entry',9000,900,'pi_cancelled',now()),
 (gen_random_uuid(),pg_temp.id('summary show'),pg_temp.id('Ada'),'usd','manual','paid','manual',2000,0,'external',now());
select is((pg_temp.summary()->>'club_earned_cents')::int,12003,'duplicates, cancelled, pending excluded and manual receipt not counted twice');
-- A failed refund is not money returned. Successful fee refunds are additional
-- to the principal refunds already in exhibitor balances.
insert into entry_refunds_private.requests values
 (pg_temp.id('summary show'),'usd',90,'failed'),(pg_temp.id('summary show'),'usd',55,'succeeded');
update summary_rows set data=jsonb_set(data,'{0,refunded_cents}','1000');
update show_payments set application_fee_refunded_cents=21 where id=pg_temp.id('receipt1');
select is((pg_temp.summary()->>'refunded_cents')::int,1055,'refund total includes successful online fee refund only');
select is((pg_temp.summary()->>'club_earned_cents')::int,10969,'net deducts refunds and credits returned application fee; processing cost retained');
-- Fee mode can change later; rely on original quote, including club-absorbed fees.
update show_payments set online_fee_cents=0 where id in(pg_temp.id('receipt1'),pg_temp.id('receipt2'));
update show_payment_sessions set quote_snapshot='{"currency":"usd","expected_amount_cents":10000,"platform_fee_cents":200,"processing_fee_rate":0.029,"processing_fee_fixed_cents":30}';
select is((pg_temp.summary()->>'club_earned_cents')::int,10446,'club-absorbed fee costs reduce club earnings');
-- Credits change charges/due, never masquerade as money collected.
update summary_rows set data=jsonb_set(jsonb_set(data,'{0,charges_cents}','13000'),'{0,due_cents}','1000');
select is((pg_temp.summary()->>'club_earned_cents')::int,10446,'credits do not increase earnings');
-- Incomplete evidence must not be shown as an exact earnings number.
update show_payment_sessions set quote_snapshot=quote_snapshot-'processing_fee_rate';
select ok(pg_temp.summary()->>'club_earned_cents' is null,'missing historical fee quote makes estimate unavailable');
update show_payment_sessions set quote_snapshot=quote_snapshot||'{"processing_fee_rate":0.029,"expected_amount_cents":9999}';
select ok(pg_temp.summary()->>'club_earned_cents' is null,'partial household ledger cannot silently overstate earnings');
update show_payment_sessions set quote_snapshot=quote_snapshot||'{"expected_amount_cents":10000}';
update summary_rows set data=jsonb_set(data,'{0,online_cents}','11000');
select ok(pg_temp.summary()->>'club_earned_cents' is null,'unmatched legacy receipts block earnings estimate');
-- Independent currency totals, including manual-only shows and negative net.
update summary_rows set data=data||'[{"currency":"cad","charges_cents":3000,"online_cents":0,"manual_cents":1000,"refunded_cents":1500,"due_cents":2000}]';
select is((select (show_finances_private.summary(pg_temp.id('summary show'),data)->0->>'club_earned_cents')::int from summary_rows),-500,'manual-only currency net can be negative and never mixes currencies');
select is((select show_finances_private.summary(pg_temp.id('summary show'),data)->0->>'currency' from summary_rows),'cad','currencies sorted separately');
select is(show_finances_private.summary(pg_temp.id('empty show'),'[]'),'[]'::jsonb,'empty show has no fabricated earnings');
select ok(not has_function_privilege('anon','show_finances_private.summary(uuid,jsonb)','EXECUTE'),'anonymous cannot call private summary');
select ok(not has_function_privilege('authenticated','show_finances_private.summary(uuid,jsonb)','EXECUTE'),'clients must use authorized show RPC');
select set_config('request.jwt.claims','{}',true);
select throws_ok(format('select public.get_show_finances(%L)',pg_temp.id('summary show')),'42501',null,'RPC still requires authorization');
select * from finish();
rollback;
