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


create function pg_temp.offering(k text,custom boolean,opens timestamptz default null,closes timestamptz default null,price integer default 500)
returns jsonb language sql as $$select jsonb_build_object('id',pg_temp.fx(k),'kind','contest','name',k,'price_cents',price,
'use_show_entry_dates',not custom,'registration_open_at',opens,'registration_close_at',closes)$$;
select pg_temp.actor('secretary');
set local role authenticated;
select set_show_addons_enabled(pg_temp.fx('show'),'contest',true);
select lives_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('contest',false))$$,'existing contests default to the show dates');
select is((get_show_addons(pg_temp.fx('show'))->'items'->0->>'use_show_entry_dates')::boolean,true,'catalog reports inherited dates');
select throws_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('free',true))$$,'P0001','Choose an opening and closing date, with closing after opening.','custom dates require both ends');
select throws_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('free',true,now(),now()))$$,'P0001','Choose an opening and closing date, with closing after opening.','equal times rejected');
select throws_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('free',true,now(),now()-interval '1 day'))$$,'P0001','Choose an opening and closing date, with closing after opening.','reverse range rejected');
select throws_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('free',true,now(),'infinity'))$$,'P0001','Choose an opening and closing date, with closing after opening.','nonfinite dates rejected');
select throws_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('extra',true,now(),now()+interval '1 day')||'{"kind":"extra"}'::jsonb)$$,'P0001','Custom registration dates are only available for contests.','add-on dates still follow the show');
reset role;
update shows set entry_open_at=now()-interval '3 days',entry_close_at=now()-interval '1 day' where id=pg_temp.fx('show');
select pg_temp.actor('buyer');
set local role authenticated;
select is(get_show_addons(pg_temp.fx('show'))->'items'->0->>'registration_status','closed','inherited window follows changes to show dates');
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{}')$$,'P0001','Registration is outside the registration window for contest.','default contest rejects registration after animal entry closes');
select pg_temp.actor('secretary');
set local role authenticated;
select lives_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('contest',true,now()-interval '1 hour',now()+interval '1 day'))$$,'secretary overrides dates per contest');
select pg_temp.actor('buyer');
select is(get_show_addons(pg_temp.fx('show'))->'items'->0->>'registration_status','open','custom contest remains open after animal entry close');
select ok(exists(select 1 from jsonb_array_elements(get_open_contest_shows()) s where s->>'id'=pg_temp.fx('show')::text),'show remains discoverable while a custom contest is open');
select lives_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('ex'),1,'{}')$$,'custom contest can be added after animal close');
select lives_ok($$select commit_entry_cart_day_of(pg_temp.fx('cart'))$$,'day-of contest checkout works after animal close');
reset role;
select is((select status from entry_carts where id=pg_temp.fx('cart')),'submitted','contest cart was submitted');
select is((select count(*)::int from entries where show_id=pg_temp.fx('show')),0,'contest checkout creates no animals');
select pg_temp.actor('secretary');
set local role authenticated;
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('extra',true,now()-interval '1 hour',now()+interval '1 day'));
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('free',true,now()-interval '1 hour',now()+interval '1 day',0));
select pg_temp.actor('buyer');
select save_cart_addon(pg_temp.fx('later_cart'),pg_temp.fx('extra'),pg_temp.fx('ex'),1,'{}');
select save_cart_addon(pg_temp.fx('free_cart'),pg_temp.fx('free'),pg_temp.fx('ex'),1,'{}');
select pg_temp.actor('secretary');
set local role authenticated;
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('extra',true,now()-interval '3 hours',now()-interval '1 hour'));
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('free',true,now()-interval '3 hours',now()-interval '1 hour',0));
select pg_temp.actor('buyer');
select throws_ok($$select commit_free_addon_cart(pg_temp.fx('free_cart'))$$,'P0001','Registration is outside the registration window for free.','free checkout revalidates an expired custom window');
select pg_temp.actor('buyer',true);
reset role;
select throws_ok($$select create_payment_quote_attempt(pg_temp.fx('later_cart'),pg_temp.fx('buyer'),'stripe',0,0,0)$$,'P0001','Registration is outside the registration window for extra.','online checkout revalidates an expired custom window');
select pg_temp.actor('secretary');
set local role authenticated;
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('extra',true,now()-interval '1 hour',now()+interval '1 day'));
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('free',true,now()-interval '1 hour',now()+interval '1 day',0));
select pg_temp.actor('buyer');
select lives_ok($$select commit_free_addon_cart(pg_temp.fx('free_cart'))$$,'free contest checkout works in its custom window');
select pg_temp.actor('buyer',true);
reset role;
select lives_ok($$select create_payment_quote_attempt(pg_temp.fx('later_cart'),pg_temp.fx('buyer'),'stripe',0,0,0)$$,'online quote works for custom contest after animal close without contacting a provider');
reset role;
insert into addon_fixture(k) values('mixed_cart'),('mixed');
insert into entry_carts(id,user_id,show_id) values(pg_temp.fx('mixed_cart'),pg_temp.fx('buyer'),pg_temp.fx('show'));
insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name)
values(pg_temp.fx('mixed_cart'),pg_temp.fx('section'),pg_temp.fx('ex'),'rabbit','WINDOW-1','Dutch','Black','Buck','Senior');
select pg_temp.actor('secretary');
set local role authenticated;
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('mixed',true,now()-interval '1 hour',now()+interval '1 day'));
select pg_temp.actor('buyer');
select save_cart_addon(pg_temp.fx('mixed_cart'),pg_temp.fx('mixed'),pg_temp.fx('ex'),1,'{}');
select throws_ok($$select commit_entry_cart_day_of(pg_temp.fx('mixed_cart'))$$,'P0001','This show''s entry deadline has passed','custom contest does not reopen animal checkout');
reset role;
update shows set entry_open_at=now()+interval '1 day',entry_close_at=now()+interval '3 days' where id=pg_temp.fx('show');
select pg_temp.actor('buyer',true);
reset role;
select throws_ok($$select create_payment_quote_attempt(pg_temp.fx('mixed_cart'),pg_temp.fx('buyer'),'stripe',0,0,0)$$,'P0001','Remove animal entries from the cart to register for contests outside the show entry window.','early contest window cannot submit animals before animal entries open');
select pg_temp.actor('secretary');
set local role authenticated;
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('mixed',true,now()+interval '1 day',now()+interval '2 days'));
select pg_temp.actor('buyer');
select is((select item->>'registration_status' from jsonb_array_elements(get_show_addons(pg_temp.fx('show'))->'items') item where item->>'name'='mixed'),'upcoming','future opening is shown to exhibitors');
select throws_ok($$select save_cart_addon(pg_temp.fx('mixed_cart'),pg_temp.fx('mixed'),pg_temp.fx('ex'),1,'{}')$$,'P0001','Registration is outside the registration window for mixed.','cannot add before custom opening');
select pg_temp.actor('secretary');
set local role authenticated;
select save_show_addon(pg_temp.fx('show'),pg_temp.offering('mixed',false,now()-interval '1 day',now()+interval '1 day'));
select is((select item->>'registration_open_at' from jsonb_array_elements(get_show_addons(pg_temp.fx('show'),true)->'items') item where item->>'name'='mixed'),null::text,'switching back to default clears the saved override');
select pg_temp.actor('other');
select throws_ok($$select save_show_addon(pg_temp.fx('show'),pg_temp.offering('mixed',true,now(),now()+interval '1 day'))$$,'42501','Only show secretaries and administrators can manage contests and add-ons.','custom dates retain secretary-only permissions');
reset role;
update shows set is_locked=true where id=pg_temp.fx('show');
select pg_temp.actor('buyer');
set local role authenticated;
select ok(not exists(select 1 from jsonb_array_elements(get_open_contest_shows()) s where s->>'id'=pg_temp.fx('show')::text),'locked shows are not advertised for contest registration');
select is(get_show_addons(pg_temp.fx('show'))->'items'->0->>'registration_status','locked','locked state overrides a custom open window');
reset role;
update shows set is_locked=false,is_published=false where id=pg_temp.fx('show');
set local role authenticated;
select ok(not exists(select 1 from jsonb_array_elements(get_open_contest_shows()) s where s->>'id'=pg_temp.fx('show')::text),'unpublished shows stay private');
reset role;
select ok(not has_function_privilege('anon','public.get_open_contest_shows()','execute'),'anonymous callers cannot list custom contest shows');
select * from finish();
rollback;
