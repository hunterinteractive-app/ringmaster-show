-- Synthetic registrations and mocked payment completion; always rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table addon_fixture(k text primary key,id uuid default gen_random_uuid());
insert into addon_fixture(k) values('secretary'),('buyer'),('other'),('show'),('section'),('ex'),('other_ex'),('cart'),('attempt'),('later_cart'),('free_cart'),('contest'),('extra'),('free');
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
insert into show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider) values(pg_temp.fx('show'),false,true,false,'square');
insert into show_payment_account_links(show_id,provider,status,account_status,charges_enabled,provider_location_id,provider_account_id)
values(pg_temp.fx('show'),'square','active','ready',true,'LOCAL-LOCATION','LOCAL-MERCHANT');


select pg_temp.actor('secretary');
select set_show_addons_enabled(pg_temp.fx('show'),'extra',true);
select save_show_addon(pg_temp.fx('show'),jsonb_build_object('id',pg_temp.fx('extra'),'kind','extra','name','Pass','price_cents',5000));
select pg_temp.actor('buyer');
insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name)
values(pg_temp.fx('cart'),pg_temp.fx('section'),pg_temp.fx('ex'),'rabbit','TEST','Dutch','Black','Buck','Senior');
select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('extra'),pg_temp.fx('ex'),1,'{}');
select pg_temp.actor('buyer',true);
update addon_fixture set id=(create_payment_quote_attempt(pg_temp.fx('cart'),pg_temp.fx('buyer'),'square',0,0,0)->>'payment_session_id')::uuid where k='attempt';
select is((select calculated_total_cents from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),6000,'quote freezes animal and pass charges');
select throws_ok($$delete from entry_cart_items where cart_id=pg_temp.fx('cart') and not is_show_addon_carrier$$,'P0001','Cancel the unfinished checkout before changing cart items.','pending animal deletion is blocked');
select throws_ok($$select remove_cart_addon((select id from show_addons_private.selections where cart_id=pg_temp.fx('cart')))$$,'P0001','This cart is already submitted or has a payment in progress.','pending add-on deletion remains blocked');
select ok(not has_function_privilege('authenticated','public.finish_cancelled_square_checkout(uuid,uuid)','execute'),'browser cannot unlock an unchecked payment');
select pg_temp.actor('buyer');
select throws_ok($$select checkout_private.finish_cancelled_square_checkout(pg_temp.fx('cart'),pg_temp.fx('attempt'))$$,'42501','Backend authorization required','even a privileged SQL call needs backend claims');
select pg_temp.actor('buyer',true);
select throws_ok($$select finish_cancelled_square_checkout(pg_temp.fx('later_cart'),pg_temp.fx('attempt'))$$,'P0001','Square checkout not found.','attempt must belong to exact cart');
-- Model an old client that removed an animal while the quoted balance was frozen.
-- This is only a disposable local fixture; the production trigger stays enabled.
alter table entry_cart_items disable trigger a_serialize_checkout_cart_edit;
delete from entry_cart_items where cart_id=pg_temp.fx('cart') and not is_show_addon_carrier;
alter table entry_cart_items enable trigger a_serialize_checkout_cart_edit;
select lives_ok($$select finish_cancelled_square_checkout(pg_temp.fx('cart'),pg_temp.fx('attempt'))$$,'confirmed provider cancellation unlocks and reprices');
select is((select active_payment_session_id from entry_carts where id=pg_temp.fx('cart')),null::uuid,'cart lock cleared');
select is((select attempt_status from show_payment_sessions where id=pg_temp.fx('attempt')),'cancelled','attempt canceled');
select is((select calculated_total_cents from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),5000,'stale animal price removed');
select is((select entries_subtotal_cents from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),0,'no animal fee for zero entries');
select lives_ok($$select finish_cancelled_square_checkout(pg_temp.fx('cart'),pg_temp.fx('attempt'))$$,'cancellation retry is idempotent');
select pg_temp.actor('other');
select throws_ok($$select remove_cart_addon((select id from show_addons_private.selections where cart_id=pg_temp.fx('cart')))$$,'42501','You do not have access to this cart.','other household still cannot delete');
select pg_temp.actor('buyer');
select lives_ok($$select remove_cart_addon((select id from show_addons_private.selections where cart_id=pg_temp.fx('cart')))$$,'owner can remove the remaining pass');
select is(jsonb_array_length(get_cart_addons(pg_temp.fx('cart'))),0,'pass removed');
select is((select count(*)::int from show_exhibitor_balances where entry_cart_id=pg_temp.fx('cart')),0,'empty cart has no collectible balance');
select pg_temp.actor('buyer',true);
update entry_carts set completed_payment_session_id=pg_temp.fx('attempt'),payment_status='paid' where id=pg_temp.fx('cart');
select throws_ok($$select finish_cancelled_square_checkout(pg_temp.fx('cart'),pg_temp.fx('attempt'))$$,'P0001','This cart has a payment and cannot be reopened.','paid cart cannot be reopened');
select * from finish();
rollback;
