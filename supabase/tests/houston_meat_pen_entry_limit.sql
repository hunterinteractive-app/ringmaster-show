begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
create schema meat_limit_test;
create table meat_limit_test.ids(k text primary key,id uuid default gen_random_uuid());
insert into meat_limit_test.ids(k) values('secretary'),('buyer'),('show'),('ordinary'),('section'),('ordinary_section'),('kid'),('sibling'),('legacy'),('paid'),('race'),('c1'),('c2'),('sib'),('ordinary_cart'),('stale'),('paid1'),('paid2'),('race1'),('race2');
create function meat_limit_test.id(text) returns uuid language sql as $$select id from meat_limit_test.ids where k=$1$$;
create function meat_limit_test.actor(text) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',meat_limit_test.id($1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',meat_limit_test.id($1),'role','authenticated')::text,true);
end;$$;
grant usage on schema meat_limit_test to authenticated;
grant select on meat_limit_test.ids to authenticated;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',k||'-'||id||'@example.invalid','{}','{}' from meat_limit_test.ids where k in('secretary','buyer');
insert into shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test,entry_open_at,entry_close_at,payment_timing_mode,online_payment_fee_mode)
select id,meat_limit_test.id('secretary'),meat_limit_test.id('secretary'),k,current_date,current_date+2,true,true,now()-interval '1 day',now()+interval '1 day','online_or_at_show','club_absorbs'
from meat_limit_test.ids where k in('show','ordinary');
insert into meat_pens_private.enabled_shows values(meat_limit_test.id('show'));
insert into meat_pens_private.entry_limits values(meat_limit_test.id('show'),2);
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
select id,k,meat_limit_test.id('buyer'),998100+row_number() over(order by k),k||'@example.invalid',true,true
from meat_limit_test.ids where k in('kid','sibling','legacy','paid','race');
insert into breeds(name,species,class_system,is_active) values('Californian','rabbit','six',true);
insert into show_sections(id,show_id,kind,letter,display_name,sort_order,breed_scope,allow_meat_classes) values
 (meat_limit_test.id('section'),meat_limit_test.id('show'),'youth','A','Meat Pen',1,'meat_only',true),
 (meat_limit_test.id('ordinary_section'),meat_limit_test.id('ordinary'),'youth','A','Meat Pen',1,'meat_only',true);
insert into show_commercial_classes(show_id,class_code,display_name,is_enabled)
select id,'meat_pen','Meat Pens',true from meat_limit_test.ids where k in('show','ordinary');
insert into show_fee_settings(show_id,currency) select id,'USD' from meat_limit_test.ids where k in('show','ordinary');
insert into show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee)
select id,0,0,0 from meat_limit_test.ids where k in('section','ordinary_section')
on conflict(section_id) do update set fee_per_entry=0,fee_per_show=0,fur_fee=0;
insert into entry_carts(id,user_id,show_id)
select id,meat_limit_test.id('buyer'),case when k='ordinary_cart' then meat_limit_test.id('ordinary') else meat_limit_test.id('show') end
from meat_limit_test.ids where k in('c1','c2','sib','ordinary_cart','stale','paid1','paid2','race1','race2');
create function meat_limit_test.add(p_cart text,p_kid text) returns uuid language plpgsql as $$declare result uuid;begin
 insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,breed,variety,class_name,tattoo)
 values(meat_limit_test.id(p_cart),meat_limit_test.id(case when p_cart='ordinary_cart' then 'ordinary_section' else 'section' end),
 meat_limit_test.id(p_kid),'rabbit','Californian','Standard','Meat Pen',gen_random_uuid()::text) returning id into result;
 return result;
end;$$;
create function meat_limit_test.checkout(p_cart text) returns void language plpgsql as $$begin
 perform meat_limit_test.actor('buyer');
 perform public.commit_entry_cart_day_of(meat_limit_test.id(p_cart));
end;$$;
-- Test assertions
select no_plan();
select meat_limit_test.actor('buyer');
set local role authenticated;
select throws_like($$insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,breed,variety,class_name,tattoo)
 select meat_limit_test.id('c1'),meat_limit_test.id('section'),meat_limit_test.id('kid'),'rabbit','Californian','Standard','Meat Pen','BATCH-'||n from generate_series(1,3) n$$,
 '%maximum of 2 meat pen entries per exhibitor%','three-pen batch rejected atomically');
select is((select count(*) from entry_cart_items where cart_id=meat_limit_test.id('c1')),0::bigint,'rejected batch leaves no partial cart items');
select lives_ok($$select meat_limit_test.add('c1','kid')$$,'first pen allowed');
select lives_ok($$select meat_limit_test.add('c1','kid')$$,'second pen allowed');
select throws_like($$select meat_limit_test.add('c1','kid')$$,'%maximum of 2 meat pen entries per exhibitor%','third pen blocked in cart');
select is((select count(*) from entry_cart_items where cart_id=meat_limit_test.id('c1')),2::bigint,'rejected pen was not inserted');
select lives_ok($$select meat_limit_test.add('sib','sibling'); select meat_limit_test.add('sib','sibling')$$,'sibling has a separate two-pen allowance');
select lives_ok($$select meat_limit_test.add('ordinary_cart','kid'); select meat_limit_test.add('ordinary_cart','kid'); select meat_limit_test.add('ordinary_cart','kid')$$,'other shows retain existing behavior');
select lives_ok($$select meat_limit_test.add('c2','kid')$$,'another abandoned draft does not reserve capacity');
select lives_ok($$select commit_entry_cart_day_of(meat_limit_test.id('c1'))$$,'two pens submit without double counting cart rows');
select lives_ok($$select commit_entry_cart_day_of(meat_limit_test.id('c1'))$$,'submission retry is idempotent');
select throws_like($$select commit_entry_cart_day_of(meat_limit_test.id('c2'))$$,'%maximum of 2 meat pen entries per exhibitor%','separate cart cannot exceed completed entries');
select throws_like($$select commit_free_entry_cart(meat_limit_test.id('c2'))$$,'%maximum of 2 meat pen entries per exhibitor%','free checkout also rejects excess entries');
select throws_like($$select meat_limit_test.add('c2','kid')$$,'%maximum of 2 meat pen entries per exhibitor%','new cart addition counts previous submissions');
select lives_ok($$update entry_cart_items set tattoo='updated' where cart_id=meat_limit_test.id('ordinary_cart')$$,'ordinary edits unaffected');
select lives_ok($$select update_meat_pen_tattoos((select id from entries where exhibitor_id=meat_limit_test.id('kid') limit 1),array['A','B','C'])$$,'tattoo updates allowed at the limit');
reset role;
select throws_like($$insert into entries(show_id,section_id,exhibitor_id,species,breed,variety,class_name,tattoo) values(meat_limit_test.id('show'),meat_limit_test.id('section'),meat_limit_test.id('kid'),'rabbit','Californian','Standard','Meat Pen','MANUAL')$$,'%maximum of 2 meat pen entries per exhibitor%','direct secretary entry cannot bypass limit');
-- An existing over-limit cart is preserved but cannot reach payment.
update meat_pens_private.entry_limits set maximum=3 where show_id=meat_limit_test.id('show');
select meat_limit_test.add('stale','legacy'); select meat_limit_test.add('stale','legacy'); select meat_limit_test.add('stale','legacy');
update meat_pens_private.entry_limits set maximum=2 where show_id=meat_limit_test.id('show');
select is((select count(*) from entry_cart_items where cart_id=meat_limit_test.id('stale')),3::bigint,'existing excess draft not deleted');
set local role authenticated;
select throws_like($$select commit_entry_cart_day_of(meat_limit_test.id('stale'))$$,'%maximum of 2 meat pen entries per exhibitor%','old over-limit cart blocked at checkout');
select lives_ok($$delete from entry_cart_items where id=(select id from entry_cart_items where cart_id=meat_limit_test.id('stale') limit 1)$$,'excess draft can be removed');
select lives_ok($$select commit_free_entry_cart(meat_limit_test.id('stale'))$$,'corrected cart of two can submit');
reset role;
-- Local Square simulation: no provider network calls or real charges.
update show_section_fee_settings set fee_per_entry=10 where section_id=meat_limit_test.id('section');
insert into show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider)
values(meat_limit_test.id('show'),false,true,false,'square');
insert into show_payment_account_links(show_id,provider,status,provider_account_id,provider_location_id)
values(meat_limit_test.id('show'),'square','active','LOCAL-MEAT-LIMIT','LOCAL-LOCATION');
select meat_limit_test.add('paid1','paid'); select meat_limit_test.add('paid1','paid'); select meat_limit_test.add('paid2','paid');
select set_config('request.jwt.claims',jsonb_build_object('sub',meat_limit_test.id('buyer'),'role','service_role')::text,true);
select throws_like($$select create_payment_quote_attempt(meat_limit_test.id('c2'),meat_limit_test.id('buyer'),'square',0.03,0.029,30)$$,'%maximum of 2 meat pen entries per exhibitor%','excess entry blocked before provider checkout');
select is((select count(*) from show_payment_sessions where cart_id=meat_limit_test.id('c2')),0::bigint,'rejection creates no payment attempt');
select lives_ok($$select create_payment_quote_attempt(meat_limit_test.id('paid1'),meat_limit_test.id('buyer'),'square',0.03,0.029,30)$$,'two pens can begin payment');
select throws_like($$select create_payment_quote_attempt(meat_limit_test.id('paid2'),meat_limit_test.id('buyer'),'square',0.03,0.029,30)$$,'%maximum of 2 meat pen entries per exhibitor%','pending checkout reserves places across carts');
select lives_ok($$select finalize_entry_cart_paid(meat_limit_test.id('paid1'),s.id,'square','LOCAL-NO-CHARGE',s.expected_amount_cents,s.expected_currency) from show_payment_sessions s where s.cart_id=meat_limit_test.id('paid1')$$,'paid finalization counts each pen once');
select lives_ok($$select finalize_entry_cart_paid(meat_limit_test.id('paid1'),s.id,'square','LOCAL-NO-CHARGE',s.expected_amount_cents,s.expected_currency) from show_payment_sessions s where s.cart_id=meat_limit_test.id('paid1')$$,'paid finalization retry remains idempotent');
select is((select count(*) from entries where exhibitor_id=meat_limit_test.id('paid')),2::bigint,'exactly two paid entries materialize');
select meat_limit_test.actor('secretary');
update entries set scratched_at=now(),status='scratched' where id=(select id from entries where exhibitor_id=meat_limit_test.id('kid') limit 1);
select meat_limit_test.actor('buyer');
set local role authenticated;
select lives_ok($$select commit_entry_cart_day_of(meat_limit_test.id('c2'))$$,'scratching releases a place for a replacement');
reset role;
select meat_limit_test.actor('secretary');
select throws_like($$update entries set scratched_at=null,status='entered' where exhibitor_id=meat_limit_test.id('kid') and scratched_at is not null$$,'%maximum of 2 meat pen entries per exhibitor%','reactivating a scratched pen cannot create a third entry');
select throws_like($$update entries set exhibitor_id=meat_limit_test.id('kid') where id=(select id from entries where exhibitor_id=meat_limit_test.id('legacy') limit 1)$$,'%maximum of 2 meat pen entries per exhibitor%','reassigning an entry cannot bypass limit');
set local role authenticated;
select throws_ok($$select * from meat_pens_private.entry_limits$$,'42501','permission denied for table entry_limits','clients cannot change limits');
select throws_ok($$select meat_pens_private.validate_cart_limit(meat_limit_test.id('c1'))$$,'42501','permission denied for function validate_cart_limit','internal checker is not a public API');
reset role;
select * from finish();
rollback;
