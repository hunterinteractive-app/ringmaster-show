begin;
set local search_path=public,extensions;
select no_plan();

create temporary table fixture (key text primary key,id uuid default gen_random_uuid());
insert into fixture(key) select unnest(array[
  'staff','owner','stranger','show','A','B','person','family','outside',
  'old_cart','draft','old_animal','new_animal','old_item','old_entry','draft_item','balance'
]);
create function pg_temp.id(text) returns uuid language sql as $$select id from fixture where key=$1$$;
create function pg_temp.as_user(text) returns text language sql as $$
  select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.id($1))::text,true)
$$;
create function pg_temp.review() returns jsonb language sql as $$select get_entry_cart_review(pg_temp.id('draft'))$$;
create function pg_temp.due() returns integer language sql as $$
  select balance_due_cents from show_exhibitor_balances
  where show_id=pg_temp.id('show') and exhibitor_id=pg_temp.id('person') and source='entries'
$$;

insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
  select id,'authenticated','authenticated',id||'@example.invalid','{}','{}' from fixture
  where key in ('staff','owner','stranger');
insert into shows(id,created_by,name,start_date,end_date,entry_close_at,payment_timing_mode,is_test)
values(pg_temp.id('show'),pg_temp.id('staff'),'Safeguard fixture',current_date+2,current_date+2,
  now()+interval '1 day','pay_at_show_only',true);
insert into exhibitors(id,display_name,email,owner_user_id) values
  (pg_temp.id('person'),'Initial exhibitor','initial@example.invalid',pg_temp.id('owner')),
  (pg_temp.id('family'),'Family exhibitor','family@example.invalid',pg_temp.id('owner')),
  (pg_temp.id('outside'),'Other account','other@example.invalid',pg_temp.id('stranger'));
insert into show_sections(id,show_id,kind,letter,display_name,is_enabled)
  select id,pg_temp.id('show'),'open',key,'Open '||key,true from fixture where key in ('A','B');
insert into show_fee_settings(show_id,currency) values(pg_temp.id('show'),'usd');
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee,fee_per_show)
  select id,5,3,0 from fixture where key in ('A','B')
  on conflict(section_id) do update set fee_per_entry=5,fur_fee=3,fee_per_show=0;
insert into animals(id,owner_user_id,species,tattoo,breed,variety,sex,deleted_at) values
  (pg_temp.id('old_animal'),pg_temp.id('owner'),'rabbit','TAG1','Havana','Black','Buck',now()),
  (pg_temp.id('new_animal'),pg_temp.id('owner'),'rabbit','tag 1','Havana','Black','Buck',null);
insert into entry_carts(id,user_id,show_id,status,payment_status,selected_payment_timing) values
  (pg_temp.id('draft'),pg_temp.id('owner'),pg_temp.id('show'),'active','unpaid',null),
  (pg_temp.id('old_cart'),pg_temp.id('owner'),pg_temp.id('show'),'submitted','unpaid','at_show');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,animal_id,species,tattoo,breed,variety,sex,class_name,is_fur) values
  (pg_temp.id('old_item'),pg_temp.id('old_cart'),pg_temp.id('A'),pg_temp.id('person'),
   pg_temp.id('old_animal'),'rabbit','TAG1','Havana','Black','Buck','Senior',false),
  (pg_temp.id('draft_item'),pg_temp.id('draft'),pg_temp.id('A'),pg_temp.id('family'),
   pg_temp.id('new_animal'),'rabbit','tag 1','Havana','Black','buck','Senior',false);
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,currency,entry_count,fur_count,
  entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,subtotal_before_discount_cents,
  discount_cents,calculated_total_cents,paid_online_cents,paid_manual_cents,refunded_cents,balance_due_cents,
  payment_status,section_breakdown)
values(pg_temp.id('balance'),pg_temp.id('show'),pg_temp.id('person'),pg_temp.id('old_cart'),'cart','usd',1,0,
  500,0,0,1*500,1,499,0,0,0,499,'unpaid',jsonb_build_array(jsonb_build_object(
    'section_id',pg_temp.id('A'),'entry_count',1,'fur_count',0,
    'entries_subtotal_cents',500,'fur_subtotal_cents',0,'show_fee_cents',0)));
insert into entries(id,show_id,section_id,exhibitor_id,exhibitor_user_id,source_cart_id,source_cart_item_id,
  animal_id,species,tattoo,breed,variety,sex,class_name,status,payment_status,is_fur)
values(pg_temp.id('old_entry'),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('person'),pg_temp.id('owner'),
  pg_temp.id('old_cart'),pg_temp.id('old_item'),pg_temp.id('old_animal'),'rabbit','TAG1','Havana','Black','Buck','Senior',
  'submitted','unpaid',false);
insert into entries(show_id,section_id,exhibitor_id,exhibitor_user_id,species,tattoo,breed,variety,sex,class_name,status)
values(pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('outside'),pg_temp.id('stranger'),'rabbit','TAG1','Havana','Black','Buck','Senior','entered');

grant select on fixture to authenticated;
select pg_temp.as_user('owner');
set local role authenticated;
select is(jsonb_array_length(pg_temp.review()->'entries'),1,'review returns the household roster only');
select is((pg_temp.review()->'balances'->0->>'due_cents')::int,499,'review includes existing unpaid balance');
select is(jsonb_array_length(pg_temp.review()->'matches'),1,'archive and recreate still matches under another household exhibitor');
select is(pg_temp.review()->'matches'->0->>'already_same_animal','false','separate profiles can be confirmed');
select throws_ok(format('select commit_entry_cart_day_of(%L)',pg_temp.id('draft')),'P0001',
  'Review the possible duplicate entries in your cart before submitting.','server rejects unchecked possible duplicate');
reset role;
savepoint online_checkout;
update shows set payment_timing_mode='online_only' where id=pg_temp.id('show');
insert into show_payment_settings(show_id,stripe_enabled,default_online_provider)
values(pg_temp.id('show'),true,'stripe');
insert into show_payment_account_links(show_id,provider,status,account_status,charges_enabled,stripe_account_id,provider_account_id)
values(pg_temp.id('show'),'stripe','active','ready',true,'acct_duplicate_guard_fixture','acct_duplicate_guard_fixture');
select set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',pg_temp.id('owner'))::text,true);
select throws_ok(format('select create_payment_quote_attempt(%L,%L,%L)',pg_temp.id('draft'),pg_temp.id('owner'),'stripe'),
  'P0001','Review the possible duplicate entries in your cart before submitting.','online checkout checks duplicates before accepting payment');
select is((select count(*)::int from show_payment_sessions where cart_id=pg_temp.id('draft')),0,
  'blocked quote creates no payment attempt');
rollback to online_checkout;
select pg_temp.as_user('owner');
set local role authenticated;
select confirm_distinct_cart_entry(pg_temp.id('draft'),pg_temp.review()->'matches'->0->>'match_key');
select is(pg_temp.review()->'matches'->0->>'confirmed','true','confirmation is scoped to the exact match');
reset role;

update entry_cart_items set class_name='Junior' where id=pg_temp.id('draft_item');
select is(jsonb_array_length(pg_temp.review()->'matches'),0,'same tattoo with a different class is allowed');
update entry_cart_items set section_id=pg_temp.id('B'),class_name='Senior' where id=pg_temp.id('draft_item');
select is(jsonb_array_length(pg_temp.review()->'matches'),0,'different section is allowed');
update entry_cart_items set section_id=pg_temp.id('A'),is_fur=true where id=pg_temp.id('draft_item');
select is(jsonb_array_length(pg_temp.review()->'matches'),0,'breed entry and wool entry are separate');
update entry_cart_items set is_fur=false,animal_id=pg_temp.id('old_animal') where id=pg_temp.id('draft_item');
select is(pg_temp.review()->'matches'->0->>'already_same_animal','true','same saved rabbit is a hard duplicate across family members');
select throws_ok(format('select confirm_distinct_cart_entry(%L,%L)',pg_temp.id('draft'),pg_temp.review()->'matches'->0->>'match_key'),
  'P0001','This match changed. Refresh your cart and check again.','hard duplicate cannot be confirmed');
select throws_ok(format('select commit_entry_cart_day_of(%L)',pg_temp.id('draft')),'P0001',
  'The same animal is already entered in this section. Remove the extra line from your cart.',
  'server blocks repeated saved animal');
update entry_cart_items set animal_id=pg_temp.id('new_animal'),exhibitor_id=pg_temp.id('person') where id=pg_temp.id('draft_item');
select is(pg_temp.review()->'matches'->0->>'confirmed','false','changing the exhibitor invalidates previous confirmation');
update entry_cart_items set exhibitor_id=pg_temp.id('family') where id=pg_temp.id('draft_item');

select pg_temp.as_user('stranger');
set local role authenticated;
select throws_ok(format('select get_entry_cart_review(%L)',pg_temp.id('draft')),'42501','Cart not found','other accounts cannot read the cart review');
select throws_ok(format('select confirm_distinct_cart_entry(%L,%L)',pg_temp.id('draft'),'fake'),'42501','Cart not found','other accounts cannot confirm a match');
reset role;

select pg_temp.as_user('owner');
select is(commit_entry_cart_day_of(pg_temp.id('draft')),1,'confirmed distinct animal submits successfully');

select pg_temp.as_user('staff');
savepoint scratch_then_remove;
update entries set status='scratched',scratched_at=now() where id=pg_temp.id('old_entry');
select is(pg_temp.due(),0,'scratch applies the original unpaid credit');
delete from entries where id=pg_temp.id('old_entry');
select is(pg_temp.due(),0,'staff removal preserves the existing credit exactly once');
rollback to scratch_then_remove;

update shows set entry_close_at=now()-interval '1 minute' where id=pg_temp.id('show');
update show_section_fee_settings set fee_per_entry=9 where section_id=pg_temp.id('A');
select is(pg_temp.due(),499,'prior unpaid charge is frozen after a fee change');

savepoint pending_payment;
update entry_carts set payment_status='pending' where id=pg_temp.id('old_cart');
select throws_ok(format('delete from entries where id=%L',pg_temp.id('old_entry')),'P0001',
  'A payment is in progress. Finish or cancel it before removing this entry.','staff removal cannot race a payment');
rollback to pending_payment;

savepoint paid;
update show_exhibitor_balances set paid_online_cents=499 where id=pg_temp.id('balance');
delete from entries where id=pg_temp.id('old_entry');
select is((select count(*)::int from show_finances_private.unpaid_scratch_lines
  where entry_id=pg_temp.id('old_entry')),0,'paid receipt is outside the unpaid adjustment');
rollback to paid;

set local role authenticated;
delete from entries where id=pg_temp.id('old_entry');
reset role;
select is(pg_temp.due(),0,'staff removal zeroes the original $4.99 due after the deadline');
select is((select discount_cents from show_finances_private.unpaid_scratch_lines
  where entry_id=pg_temp.id('old_entry')),1,'original discount is allocated once');
select is((select calculated_total_cents from show_exhibitor_balances where id=pg_temp.id('balance')),499,
  'original cart quote remains available');
select is((select count(*)::int from entry_cart_items where id=pg_temp.id('old_item')),1,'original checkout item remains available');
select pg_temp.as_user('owner');
select is((pg_temp.review()->'balances'->0->>'due_cents')::int,500,'other family balance stays correct in the cart review');
delete from show_exhibitor_balances where show_id=pg_temp.id('show') and exhibitor_id=pg_temp.id('person') and source='entries';
select is((pg_temp.review()->'balances'->0->>'due_cents')::int,500,'cart-only fallback includes the removal credit');
select * from finish();
rollback;
