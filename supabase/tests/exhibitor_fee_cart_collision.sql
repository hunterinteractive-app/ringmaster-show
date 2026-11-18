-- Run against the full schema. All fixtures and the production-equivalent
-- unique index scoped to this fixture account roll back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table ids(k text primary key,id uuid default gen_random_uuid());
insert into ids(k) values('owner'),('show'),('section'),('source'),('first'),('second'),('paid'),('active');
create function pg_temp.id(text) returns uuid language sql as $$select id from ids where k=$1$$;
insert into auth.users(id) values(pg_temp.id('owner'));
select set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',pg_temp.id('owner'))::text,true);
insert into shows(id,name,created_by,owner_user_id,start_date,end_date)
values(pg_temp.id('show'),'Fee cart collision regression',pg_temp.id('owner'),pg_temp.id('owner'),current_date,current_date+1);
insert into exhibitors(id,display_name,owner_user_id,email)
select id,k,pg_temp.id('owner'),'fixture@example.invalid' from ids where k in ('source','first','second');
insert into show_sections(id,show_id,kind,letter) values(pg_temp.id('section'),pg_temp.id('show'),'youth','A');
insert into show_fee_settings(show_id,currency,exhibitor_fee_enabled,exhibitor_fee_amount)
values(pg_temp.id('show'),'usd',true,10);
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee)
values(pg_temp.id('section'),10,0) on conflict(section_id) do update set fee_per_entry=10,fur_fee=0;
insert into entry_carts(id,show_id,user_id,status,payment_status,currency)
values(pg_temp.id('paid'),pg_temp.id('show'),pg_temp.id('owner'),'submitted','paid','usd'),
      (pg_temp.id('active'),pg_temp.id('show'),pg_temp.id('owner'),'active','unpaid','usd');
do $$begin execute format('create unique index fee_test_one_active_cart on entry_carts(show_id,user_id) where status=''active'' and user_id=%L',pg_temp.id('owner')); end$$;
create temporary table saved_carts as select * from entry_carts where id in (pg_temp.id('paid'),pg_temp.id('active'));
select lives_ok($$select exhibitor_fees_private.ensure_charge(pg_temp.id('show'),pg_temp.id('first'),pg_temp.id('paid'),pg_temp.id('section'))$$,
 'assessing a new exhibitor alongside an existing active cart succeeds');
select lives_ok($$select exhibitor_fees_private.ensure_charge(pg_temp.id('show'),pg_temp.id('second'),pg_temp.id('paid'),pg_temp.id('section'))$$,
 'a second exhibitor on the same account can also be assessed');
select is((select count(*)::int from entry_carts where show_id=pg_temp.id('show') and status='active'),1,'keeps exactly one active household cart');
select is((select count(*)::int from exhibitor_fees_private.charges ch join entry_carts c on c.id=ch.cart_id where ch.show_id=pg_temp.id('show') and c.id=pg_temp.id('active')),2,'both fees reuse the existing active cart');
select lives_ok($$select public.calculate_entry_cart_balance_internal(cart_id) from exhibitor_fees_private.charges where show_id=pg_temp.id('show')$$,'fee cart can be calculated');
select is((select sum(calculated_total_cents)::int from show_exhibitor_balances where show_id=pg_temp.id('show') and source='cart'),2000,'exactly two $10 office fees are assessed');
select is((select sum(entry_count)::int from show_exhibitor_balances where show_id=pg_temp.id('show') and source='cart'),0,'no animal entries are invented');
select is((select count(*)::int from entry_carts c join saved_carts s using(id) where c.id=pg_temp.id('paid') and to_jsonb(c) is distinct from to_jsonb(s)),0,'original receipt cart is unchanged');
select lives_ok($$select exhibitor_fees_private.ensure_charge(pg_temp.id('show'),pg_temp.id('first'),pg_temp.id('paid'),pg_temp.id('section'))$$,'repeated assessment is idempotent');
select is((select count(*)::int from exhibitor_fees_private.charges where show_id=pg_temp.id('show')),2,'retries do not duplicate charges');
select is((select count(*)::int from entries where show_id=pg_temp.id('show')),0,'fee carriers never create show entries');
select ok(not has_function_privilege('authenticated','exhibitor_fees_private.ensure_charge(uuid,uuid,uuid,uuid)','EXECUTE'),'private assessment remains inaccessible to clients');
insert into ids(k) values('third');
insert into exhibitors(id,display_name,owner_user_id,email)
values(pg_temp.id('third'),'third',pg_temp.id('owner'),'fixture@example.invalid');
update entry_carts set payment_status='pending' where id=pg_temp.id('active');
select throws_ok($$select exhibitor_fees_private.ensure_charge(pg_temp.id('show'),pg_temp.id('third'),pg_temp.id('paid'),pg_temp.id('section'))$$,
 '40001',null,'pending checkout is protected with an actionable error');
select is((select count(*)::int from exhibitor_fees_private.charges where show_id=pg_temp.id('show')),2,'failed assessment leaves no charge');
update entry_carts set payment_status='unpaid' where id=pg_temp.id('active');
select set_config('ringmaster.payment_state_write','on',true);
update show_exhibitor_balances set paid_manual_cents=1000,balance_due_cents=0,payment_status='paid'
where entry_cart_id=pg_temp.id('active') and exhibitor_id=pg_temp.id('first');
select throws_ok($$select exhibitor_fees_private.ensure_charge(pg_temp.id('show'),pg_temp.id('third'),pg_temp.id('paid'),pg_temp.id('section'))$$,
 '40001',null,'recorded manual funds freeze the cart even if its status says unpaid');
update entry_carts set status='submitted' where id=pg_temp.id('active');
select lives_ok($$select exhibitor_fees_private.ensure_charge(pg_temp.id('show'),pg_temp.id('third'),pg_temp.id('paid'),pg_temp.id('section'))$$,
 'creates a new active cart when no active cart exists');
select is((select count(*)::int from entry_carts where show_id=pg_temp.id('show') and status='active'),1,'new cart still respects household uniqueness');
select * from finish();
rollback;
