-- Synthetic registrations and mocked payment completion; always rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table addon_fixture(k text primary key,id uuid default gen_random_uuid());
insert into addon_fixture(k) values('secretary'),('buyer'),('other'),('show'),('section'),('ex'),('other_ex'),('cart'),('later_cart'),('free_cart'),('contest'),('extra'),('free');
grant select on addon_fixture to authenticated;
create function pg_temp.fx(k text) returns uuid language sql as $$select id from addon_fixture where addon_fixture.k=$1$$;
create function pg_temp.actor(k text, service boolean default false) returns void language plpgsql as $$begin
  perform set_config('request.jwt.claim.sub',pg_temp.fx(k)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fx(k),'role',case when service then 'service_role' else 'authenticated' end)::text,true);
end;$$;
create function pg_temp.expect_error(statement text, fragment text) returns void language plpgsql as $$begin
  begin execute statement; exception when others then
    if position(lower(fragment) in lower(sqlerrm))>0 then return; end if;
    raise exception 'Unexpected error: %',sqlerrm;
  end;
  raise exception 'Expected error: %',fragment;
end;$$;
create function pg_temp.check_true(v boolean,message text) returns void language plpgsql as $$begin
  if v is distinct from true then raise exception 'Assertion failed: %',message; end if;
end;$$;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',k||'-'||id||'@example.invalid','{}','{}' from addon_fixture where k in ('secretary','buyer','other');
insert into shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test,entry_close_at,payment_timing_mode,online_payment_fee_mode)
values(pg_temp.fx('show'),pg_temp.fx('secretary'),pg_temp.fx('secretary'),'Contests fixture',current_date,current_date+2,true,true,now()+interval '1 day','online_or_at_show','club_absorbs');
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
values(pg_temp.fx('ex'),'Contest Exhibitor',pg_temp.fx('buyer'),996701,'contest@example.invalid',true,true),
 (pg_temp.fx('other_ex'),'Other Exhibitor',pg_temp.fx('other'),996702,'other@example.invalid',true,true);
insert into show_sections(id,show_id,kind,letter,display_name,sort_order) values(pg_temp.fx('section'),pg_temp.fx('show'),'open','A','Open A',1);
insert into show_fee_settings(show_id,currency) values(pg_temp.fx('show'),'USD');
insert into show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee) values(pg_temp.fx('section'),10,0,3)
on conflict(section_id) do update set fee_per_entry=10,fee_per_show=0,fur_fee=3;
insert into entry_carts(id,user_id,show_id) select id,pg_temp.fx('buyer'),pg_temp.fx('show') from addon_fixture where k in ('cart','later_cart','free_cart');
insert into show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider) values(pg_temp.fx('show'),true,false,false,'stripe');
insert into show_payment_account_links(show_id,provider,status,account_status,charges_enabled,stripe_account_id,provider_account_id)
values(pg_temp.fx('show'),'stripe','active','ready',true,'acct_contest_fixture','acct_contest_fixture');

select pg_temp.actor('secretary');
set local role authenticated;
select lives_ok($$select set_show_addons_enabled(pg_temp.fx('show'),'contest',true)$$,'any authorized secretary enables contests without an allowlist');
select lives_ok($$select set_show_addons_enabled(pg_temp.fx('show'),'extra',true)$$,'extras enabled separately');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('contest'),'kind','contest','name','Showmanship','price_cents',500,'requires_animal_entry',true,'fields',
  '[{"id":"category","label":"Category","type":"select","required":true,"options":["Junior","Senior"]},{"id":"date","label":"Date","type":"date","required":false},{"id":"terms","label":"Acknowledgment","type":"checkbox","required":true}]'::jsonb))$$,'secretary configures contest fields and fee');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('extra'),'kind','extra','name','Banquet Ticket','price_cents',700,'max_per_exhibitor',4))$$,'secretary creates a priced extra');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('free'),'kind','contest','name','Free Contest','price_cents',0))$$,'free standalone contest configured');
select pg_temp.actor('buyer');
select throws_ok($$select set_show_addons_enabled(pg_temp.fx('show'),'contest',false)$$,'42501','Only show secretaries and administrators can manage contests and add-ons.','exhibitor cannot change setup');
select throws_ok($$select get_show_addons(pg_temp.fx('show'),true)$$,'42501','Show secretary permission is required.','exhibitor cannot access admin catalog');
select is(jsonb_array_length(get_show_addons(pg_temp.fx('show'))->'items'),3,'exhibitor sees enabled offerings');
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{"category":"Junior","terms":true}')$$,'P0001','Showmanship requires an animal entry for this exhibitor in this show.','required animal entry enforced on the server');
reset role;
insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name)
values(pg_temp.fx('cart'),pg_temp.fx('section'),pg_temp.fx('ex'),'rabbit','CT-1','Dutch','Black','Buck','Senior');
set local role authenticated;
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('other_ex'),1,'{"category":"Junior","terms":true}')$$,'42501','Choose an active exhibitor from this household.','cannot register another household’s exhibitor');
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{}')$$,'P0001','Category is required.','required answers enforced');
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{"category":"Fake","terms":true}')$$,'P0001','Choose a valid option for Category.','dropdown options enforced');
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{"category":"Junior","terms":false}')$$,'P0001','Acknowledgment is required.','required checkbox must be checked');
select lives_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{"category":"Junior","terms":true}')$$,'eligible contest registration is added');
select lives_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{"category":"Senior","terms":true}')$$,'editing the same registration is idempotent');
select lives_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('extra'),pg_temp.fx('ex'),2,'{}')$$,'extra quantity added');
select throws_ok($$select save_cart_addon(pg_temp.fx('later_cart'),pg_temp.fx('extra'),pg_temp.fx('ex'),3,'{}')$$,'P0001','The limit for Banquet Ticket is 4 per exhibitor across the full show.','quantity limit spans carts');
select is(jsonb_array_length(get_cart_addons(pg_temp.fx('cart'))),2,'repeated saves do not duplicate purchases');
select pg_temp.actor('other');
select throws_ok($$select get_cart_addons(pg_temp.fx('cart'))$$,'42501','You do not have access to this cart.','cart answers are private');
select throws_ok($$select get_show_addon_registrations(null,pg_temp.fx('buyer'))$$,'42501','Household access is required.','other household registration history denied');
reset role;
select ok(not has_table_privilege('authenticated','show_addons_private.selections','SELECT'),'private registration tables are not exposed');
select ok(not has_function_privilege('authenticated','show_addons_private.refresh_cart(uuid)','EXECUTE'),'internal accounting helper is not client callable');
select is((select entry_count from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),1,'contest and extras never count as animals');
select is((select calculated_total_cents from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),2900,'animal plus contest plus quantity pricing');
select is((select addons_subtotal_cents from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),1900,'separate add-on subtotal');
select pg_temp.actor('secretary');
update show_fee_settings set multi_show_discount_enabled=true,multi_show_discount_type='percent',multi_show_discount_value=100,multi_show_discount_min_entries=1,multi_show_discount_required_shows=1 where show_id=pg_temp.fx('show');
select pg_temp.actor('buyer');
select is((select calculated_total_cents from calculate_entry_cart_balance(pg_temp.fx('cart'))),1900,'animal discounts do not discount contests or extras');
select is((select calculated_total_cents from calculate_entry_cart_balance(pg_temp.fx('cart'))),1900,'recalculation never duplicates add-on fees');

-- Registration is not completed merely by placing it in a cart.
select is(jsonb_array_length(get_show_addon_registrations(null,pg_temp.fx('buyer'))),0,'draft selections do not appear as completed registrations');
delete from entry_cart_items where cart_id=pg_temp.fx('cart') and not is_checkin_fee_carrier;
select throws_ok($$select commit_entry_cart_day_of(pg_temp.fx('cart'))$$,'P0001','Showmanship requires an animal entry for this exhibitor in this show.','eligibility rechecked if qualifying animal is removed');
insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name)
values(pg_temp.fx('cart'),pg_temp.fx('section'),pg_temp.fx('ex'),'rabbit','CT-1','Dutch','Black','Buck','Senior');

-- Simulate the trusted provider confirmation entirely within this rollback.
select pg_temp.actor('buyer',true);
do $$declare q jsonb; sid uuid; total integer; result jsonb; begin
  q:=create_payment_quote_attempt(pg_temp.fx('cart'),pg_temp.fx('buyer'),'stripe',0.02,0.029,30);
  sid:=(q->>'payment_session_id')::uuid;
  select expected_amount_cents into total from show_payment_sessions where id=sid;
  perform pg_temp.check_true(total=1900,'provider quote includes contest and extras');
  perform pg_temp.check_true((select sum(total_amount_cents)=1900 from show_payment_line_items where payment_session_id=sid and line_type<>'platform_fee'),'receipt lines reconcile');
  perform pg_temp.check_true((select quantity=2 and total_amount_cents=1400 from show_payment_line_items where payment_session_id=sid and label='Banquet Ticket'),'ticket quantity on receipt');
  perform pg_temp.expect_error(format('select save_cart_addon(%L,%L,%L,1,''{}'')',pg_temp.fx('cart'),pg_temp.fx('extra'),pg_temp.fx('ex')),'payment in progress');
  update show_payment_sessions set provider_session_id='cs_contest_fixture' where id=sid;
  result:=finalize_entry_cart_paid(pg_temp.fx('cart'),sid,'stripe','pi_contest_fixture',total,'usd');
  perform pg_temp.check_true((select count(*)=1 from entries where source_cart_id=pg_temp.fx('cart')),'only one real animal is materialized');
  perform pg_temp.check_true((select balance_due_cents=0 and addons_subtotal_cents=1900 from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),'payment preserves exact add-on subtotal');
  result:=finalize_entry_cart_paid(pg_temp.fx('cart'),sid,'stripe','pi_contest_fixture',total,'usd');
  perform pg_temp.check_true((select count(*)=2 from show_addons_private.selections where cart_id=pg_temp.fx('cart')),'provider replay never duplicates registrations');
end;$$;
select pass('online quote, receipt, payment protection, completion and replay verified');
select pg_temp.actor('buyer');
select is(jsonb_array_length(get_show_addon_registrations(null,pg_temp.fx('buyer'))),2,'submitted contests and extras visible to household');
select throws_ok($$select save_cart_addon(pg_temp.fx('later_cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{"category":"Junior","terms":true}')$$,'P0001','The limit for Showmanship is 1 per exhibitor across the full show.','contest cannot be entered again in a later cart');
select lives_ok($$select save_cart_addon(pg_temp.fx('later_cart'),pg_temp.fx('extra'),pg_temp.fx('ex'),2,'{}')$$,'remaining allowed extra quantity can be ordered later');
select lives_ok($$select commit_entry_cart_day_of(pg_temp.fx('later_cart'))$$,'extras-only pay-at-show checkout works');
select is((select count(*)::integer from entries where source_cart_id=pg_temp.fx('later_cart')),0,'extras-only checkout creates no fake animals');
select is((select balance_due_cents from show_exhibitor_balances where entry_cart_id=pg_temp.fx('later_cart')),1400,'extras-only outstanding balance retained');
select lives_ok($$select save_cart_addon(pg_temp.fx('free_cart'),pg_temp.fx('free'),pg_temp.fx('ex'),1,'{}')$$,'free standalone contest is added');
select lives_ok($$select commit_free_addon_cart(pg_temp.fx('free_cart'))$$,'free registration requires no payment provider');
select is((select count(*)::integer from entries where source_cart_id=pg_temp.fx('free_cart')),0,'free contest creates no animal');
select pg_temp.actor('secretary');
select is(jsonb_array_length(get_show_addon_registrations(pg_temp.fx('show'),null)),4,'secretary sees all submitted registrations with answers');
-- Dedicated division and animal choices, with existing entries and new cart animals.
insert into addon_fixture(k) values('choice_cart'),('choice_contest'),('sibling_ex'),('other_show'),('other_section'),('duplicate_section');
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
values(pg_temp.fx('sibling_ex'),'Second Household Exhibitor',pg_temp.fx('buyer'),996703,'sibling@example.invalid',true,true);
insert into shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test)
values(pg_temp.fx('other_show'),pg_temp.fx('secretary'),pg_temp.fx('secretary'),'Other show fixture',current_date,current_date+1,true,true);
insert into show_sections(id,show_id,kind,letter,display_name) values(pg_temp.fx('other_section'),pg_temp.fx('other_show'),'open','A','Open A');
insert into show_sections(id,show_id,kind,letter,display_name) values(pg_temp.fx('duplicate_section'),pg_temp.fx('show'),'open','B','Open B');
insert into entry_carts(id,user_id,show_id) values(pg_temp.fx('choice_cart'),pg_temp.fx('buyer'),pg_temp.fx('show'));
insert into entries(show_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name,status,is_fur)
values
 (pg_temp.fx('show'),pg_temp.fx('duplicate_section'),pg_temp.fx('ex'),'rabbit','CT-1','Dutch','Black','Buck','Senior','entered',false),
 (pg_temp.fx('show'),pg_temp.fx('section'),pg_temp.fx('ex'),'rabbit','SCRATCH','Dutch','Black','Buck','Senior','scratched',false),
 (pg_temp.fx('show'),pg_temp.fx('section'),pg_temp.fx('ex'),'rabbit','FUR','Dutch','Black','Buck','Senior','entered',true),
 (pg_temp.fx('show'),pg_temp.fx('section'),pg_temp.fx('sibling_ex'),'rabbit','SIBLING','Dutch','Black','Buck','Senior','entered',false),
 (pg_temp.fx('other_show'),pg_temp.fx('other_section'),pg_temp.fx('ex'),'rabbit','OTHER-SHOW','Dutch','Black','Buck','Senior','entered',false);
insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name)
values(pg_temp.fx('choice_cart'),pg_temp.fx('section'),pg_temp.fx('ex'),'cavy','NEW-1','American','Black','Boar','Senior');
select pg_temp.actor('secretary');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('choice_contest'),'kind','contest','name','Choice Contest','price_cents',0,'divisions','["Junior","Senior"]'::jsonb,'animal_selection','required'))$$,'secretary configures division and animal choices');
select throws_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('choice_contest'),'kind','contest','name','Choice Contest','price_cents',0,'divisions','["Junior","Junior"]'::jsonb))$$,'P0001','Divisions must be unique, nonempty names.','duplicate divisions rejected');
select pg_temp.actor('buyer');
set local role authenticated;
select is(jsonb_array_length(get_contest_animals(pg_temp.fx('choice_cart'),pg_temp.fx('ex'))),2,'picker includes current cart and entered animals once, excludes fur, scratched, other exhibitors and shows');
select is(jsonb_array_length(get_contest_animals(pg_temp.fx('choice_cart'),pg_temp.fx('sibling_ex'))),1,'switching exhibitor offers only their animal');
select throws_ok($$select get_contest_animals(pg_temp.fx('choice_cart'),pg_temp.fx('other_ex'))$$,'42501','Choose an active exhibitor from this household.','cannot request another household’s animals');
select throws_ok($$select save_cart_addon(pg_temp.fx('choice_cart'),pg_temp.fx('choice_contest'),pg_temp.fx('ex'),1,'{}')$$,'P0001','Choose a valid division for Choice Contest.','division is required when configured');
select throws_ok($$select save_cart_addon(pg_temp.fx('choice_cart'),pg_temp.fx('choice_contest'),pg_temp.fx('ex'),1,'{}','Bogus',null)$$,'P0001','Choose a valid division for Choice Contest.','unconfigured division rejected');
select throws_ok($$select save_cart_addon(pg_temp.fx('choice_cart'),pg_temp.fx('choice_contest'),pg_temp.fx('ex'),1,'{}','Junior',null)$$,'P0001','Choose an entered animal for Choice Contest.','required animal choice enforced');
select throws_ok($$select save_cart_addon(pg_temp.fx('choice_cart'),pg_temp.fx('choice_contest'),pg_temp.fx('ex'),1,'{}','Junior',get_contest_animals(pg_temp.fx('choice_cart'),pg_temp.fx('sibling_ex'))->0->>'key')$$,'P0001','Choose an eligible animal entered for this exhibitor in this show.','cannot register a sibling’s animal for the wrong exhibitor');
select lives_ok($$select save_cart_addon(pg_temp.fx('choice_cart'),pg_temp.fx('choice_contest'),pg_temp.fx('ex'),1,'{}','Junior',(select value->>'key' from jsonb_array_elements(get_contest_animals(pg_temp.fx('choice_cart'),pg_temp.fx('ex'))) where value->>'tattoo'='NEW-1'))$$,'can choose an animal being entered in this cart');
select is(get_cart_addons(pg_temp.fx('choice_cart'))->0->>'division','Junior','chosen division retained in cart');
select is(get_cart_addons(pg_temp.fx('choice_cart'))->0->'animal_snapshot'->>'tattoo','NEW-1','animal identity snapshotted by server');
delete from entry_cart_items where cart_id=pg_temp.fx('choice_cart') and tattoo='NEW-1';
select throws_ok($$select commit_free_addon_cart(pg_temp.fx('choice_cart'))$$,'P0001','Choose an eligible animal entered for this exhibitor in this show.','removing selected animal invalidates checkout even when another animal qualifies');
select lives_ok($$select save_cart_addon(pg_temp.fx('choice_cart'),pg_temp.fx('choice_contest'),pg_temp.fx('ex'),1,'{}','Senior',get_contest_animals(pg_temp.fx('choice_cart'),pg_temp.fx('ex'))->0->>'key')$$,'can replace selection with an existing entered animal');
select lives_ok($$select commit_free_addon_cart(pg_temp.fx('choice_cart'))$$,'division and selected animal survive free checkout');
select is((select value->>'division' from jsonb_array_elements(get_show_addon_registrations(null,pg_temp.fx('buyer'))) where value->>'name'='Choice Contest'),'Senior','submitted registration includes division');
reset role;
select pg_temp.actor('secretary');
select lives_ok($$select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('choice_contest'),'kind','contest','name','Choice Contest','price_cents',0,'animal_selection','optional'))$$,'secretary can make animal selection optional and omit divisions');
insert into addon_fixture(k) values('optional_cart');
insert into entry_carts(id,user_id,show_id) values(pg_temp.fx('optional_cart'),pg_temp.fx('buyer'),pg_temp.fx('show'));
select pg_temp.actor('buyer');
select lives_ok($$select save_cart_addon(pg_temp.fx('optional_cart'),pg_temp.fx('choice_contest'),pg_temp.fx('sibling_ex'),1,'{}')$$,'optional animal choice allows registration without an animal selection');
select pg_temp.actor('secretary');

update shows set is_locked=true where id=pg_temp.fx('show');
select throws_ok($$select set_show_addons_enabled(pg_temp.fx('show'),'contest',false)$$,'P0001','This show is locked or finalized.','locked show setup protected');
select * from finish();
rollback;
