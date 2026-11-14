begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table fx(k text primary key,id uuid default gen_random_uuid());
insert into fx(k) values('secretary'),('buyer'),('other'),('club'),('host'),('cavy'),('ordinary'),
 ('host_section'),('youth_section'),('open_section'),('ordinary_section'),('kid'),('kid2'),('adult'),('stranger'),
 ('cart'),('host_cart'),('ordinary_cart'),('open_cart'),('other_cart'),('contest'),('not_linked'),('youth_item'),('kid2_item'),('open_item'),('existing');
grant select on fx to authenticated;
create function pg_temp.fx(text) returns uuid language sql as $$select id from fx where k=$1$$;
create function pg_temp.actor(text) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx($1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fx($1),'role','authenticated')::text,true);
end;$$;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',k||'-'||id||'@example.invalid','{}','{}' from fx where k in('secretary','buyer','other');
insert into clubs(id,name) values(pg_temp.fx('club'),'Houston local fixture');
insert into shows(id,created_by,owner_user_id,club_id,name,start_date,end_date,is_published,is_test,entry_open_at,entry_close_at,payment_timing_mode,online_payment_fee_mode,contests_enabled)
select id,pg_temp.fx('secretary'),pg_temp.fx('secretary'),case when k='ordinary' then null else pg_temp.fx('club') end,k,
 current_date,current_date+2,true,true,now()-interval '1 day',now()+interval '1 day','online_or_at_show','club_absorbs',k='host'
from fx where k in('host','cavy','ordinary');
insert into show_registration_private.policies
select pg_temp.fx('secretary'),pg_temp.fx('club'),version,agreement,handbook_url,website_url from show_registration_private.policies limit 1;
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
select id,k,case when k='stranger' then pg_temp.fx('other') else pg_temp.fx('buyer') end,
 998100+row_number() over(order by k),k||'@example.invalid',true,true from fx where k in('kid','kid2','adult','stranger');
insert into show_sections(id,show_id,kind,letter,display_name,sort_order) values
 (pg_temp.fx('host_section'),pg_temp.fx('host'),'youth','A','Youth Rabbit',1),
 (pg_temp.fx('youth_section'),pg_temp.fx('cavy'),'youth','A','Youth Cavy',2),
 (pg_temp.fx('open_section'),pg_temp.fx('cavy'),'open','A','Open Cavy',1),
 (pg_temp.fx('ordinary_section'),pg_temp.fx('ordinary'),'open','A','Open',1);
insert into show_fee_settings(show_id,currency) select id,'USD' from fx where k in('host','cavy','ordinary');
insert into show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider)
values(pg_temp.fx('cavy'),false,true,false,'square');
insert into show_payment_account_links(show_id,provider,status,provider_account_id,provider_location_id)
values(pg_temp.fx('cavy'),'square','active','LOCAL-ONLY-MERCHANT','LOCAL-ONLY-LOCATION');
insert into show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee)
select id,10,0,0 from fx where k like '%section' on conflict(section_id) do update set fee_per_entry=10,fee_per_show=0,fur_fee=0;
insert into entry_carts(id,user_id,show_id) select id,
 case when k='other_cart' then pg_temp.fx('other') else pg_temp.fx('buyer') end,
 case when k='host_cart' then pg_temp.fx('host') when k='ordinary_cart' then pg_temp.fx('ordinary') else pg_temp.fx('cavy') end
from fx where k in('cart','host_cart','ordinary_cart','open_cart','other_cart');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name) values
 (pg_temp.fx('youth_item'),pg_temp.fx('cart'),pg_temp.fx('youth_section'),pg_temp.fx('kid'),'cavy','CV1','American','Black','Boar','Senior'),
 (pg_temp.fx('kid2_item'),pg_temp.fx('cart'),pg_temp.fx('youth_section'),pg_temp.fx('kid2'),'cavy','CV2','American','Black','Sow','Senior'),
 (pg_temp.fx('open_item'),pg_temp.fx('cart'),pg_temp.fx('open_section'),pg_temp.fx('adult'),'cavy','AD1','American','Black','Boar','Senior');
insert into entries(id,show_id,section_id,exhibitor_user_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name,status)
values(pg_temp.fx('existing'),pg_temp.fx('cavy'),pg_temp.fx('youth_section'),pg_temp.fx('buyer'),pg_temp.fx('kid'),'cavy','PAID-CV','American','Black','Boar','Senior','submitted');
insert into show_addons_private.offerings(id,show_id,kind,name,price_cents,enabled,requires_animal_entry,animal_selection)
select id,pg_temp.fx('host'),'contest',k,500,true,true,'required' from fx where k in('contest','not_linked');
insert into show_addons_private.contest_show_links values(pg_temp.fx('contest'),pg_temp.fx('cavy'));

select pg_temp.actor('buyer');
set local role authenticated;
select is(jsonb_array_length(get_cart_registration_requirements(pg_temp.fx('cart'))->'exhibitors'),2,'mixed cart requires school for both youth exhibitors, not the Open adult');
select is(get_cart_registration_requirements(pg_temp.fx('cart'))#>>'{exhibitors,0,state}','TX','school state defaults to TX');
select is(get_cart_registration_requirements(pg_temp.fx('open_cart'))->>'required','true','Houston Open cart still needs agreement');
select is(jsonb_array_length(get_cart_registration_requirements(pg_temp.fx('open_cart'))->'exhibitors'),0,'Open cart needs no school fields');
select is(get_cart_registration_requirements(pg_temp.fx('ordinary_cart'))->>'required','false','unrelated show unaffected');
select throws_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',false,'[]')$$,'P0001','Agree to the Houston Livestock Show and Rodeo rules and terms before checkout.','unchecked agreement rejected');
select throws_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'old',true,'[]')$$,'P0001','Agree to the Houston Livestock Show and Rodeo rules and terms before checkout.','stale agreement version rejected');
select throws_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',true,'[]')$$,'P0001','Enter school name, city, and state for every youth exhibitor.','missing school rejected');
select throws_ok($$select commit_entry_cart_day_of(pg_temp.fx('cart'))$$,'P0001','Enter school name, city, and state for every youth exhibitor before checkout.','server prevents bypassing UI during submission');
select throws_ok($$select commit_free_entry_cart(pg_temp.fx('cart'))$$,'P0001','Enter school name, city, and state for every youth exhibitor before checkout.','free checkout cannot bypass requirements');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fx('buyer'),'role','service_role')::text,true);
select throws_ok($$select create_payment_quote_attempt(pg_temp.fx('cart'),pg_temp.fx('buyer'),'square',0.03,0.029,30)$$,'P0001','Enter school name, city, and state for every youth exhibitor before checkout.','Square quote cannot be created before school and agreement');
select is((select count(*)::int from show_payment_sessions where cart_id=pg_temp.fx('cart')),0,'blocked checkout creates no payment attempt');
select pg_temp.actor('buyer');
set local role authenticated;
select throws_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',true,jsonb_build_array(jsonb_build_object('exhibitor_id',pg_temp.fx('stranger'),'school_name','Wrong','city','Wrong','state','TX')))$$,'42501','School information must belong to a youth exhibitor in this cart.','cannot attach another exhibitor');
reset role;
create function pg_temp.schools() returns jsonb language sql as $$
 select jsonb_agg(jsonb_build_object('exhibitor_id',id,'school_name',' Example School ','city',' Houston ','state','tx')) from fx where k in('kid','kid2');
$$;
set local role authenticated;
select lives_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',true,pg_temp.schools())$$,'valid school details and affirmative agreement saved');
select throws_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',true,jsonb_set(pg_temp.schools(),'{0,city}','" "'))$$,'P0001','Enter school name, city, and a two-letter state for every youth exhibitor.','blank school city rejected');
select throws_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',true,jsonb_set(pg_temp.schools(),'{0,state}','"Texas"'))$$,'P0001','Enter school name, city, and a two-letter state for every youth exhibitor.','malformed state rejected');
reset role;
select lives_ok($$select show_registration_private.validate_cart(pg_temp.fx('cart'))$$,'completed requirements pass backend validation');
select is((select count(*)::int from show_registration_private.schools where cart_id=pg_temp.fx('cart')),2,'separate school record for each child');
select is((select state from show_registration_private.schools where cart_id=pg_temp.fx('cart') and exhibitor_id=pg_temp.fx('kid')),'TX','state normalized');
select is((select accepted_by from show_registration_private.acceptances where cart_id=pg_temp.fx('cart')),pg_temp.fx('buyer'),'acceptance records authenticated actor');
select ok((select handbook_url like '%2027-Exhibitor-Handbook-V2.pdf' and school_snapshot->0->>'school_name'='Example School' from show_registration_private.acceptances where cart_id=pg_temp.fx('cart')),'agreement evidence preserves exact handbook and school snapshot');
update entry_cart_items set tattoo='CV1-EDITED' where id=pg_temp.fx('youth_item');
select throws_ok($$select show_registration_private.validate_cart(pg_temp.fx('cart'))$$,'P0001','Review this cart and agree to the Houston Livestock Show and Rodeo rules and terms before checkout.','cart change requires fresh acceptance');
select lives_ok($$select show_registration_private.validate_cart(pg_temp.fx('ordinary_cart'))$$,'ordinary checkout unchanged');
select pg_temp.actor('other');
set local role authenticated;
select throws_ok($$select get_cart_registration_requirements(pg_temp.fx('cart'))$$,'42501','You do not have access to this cart.','school information private to household');
select throws_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',true,'[]')$$,'42501','You do not have access to this cart.','another household cannot accept agreement');
select pg_temp.actor('buyer');
select is(jsonb_array_length(get_show_addons(pg_temp.fx('cavy'))->'items'),1,'Cavy catalog offers only linked rabbit contest');
select is(get_show_addons(pg_temp.fx('cavy'))#>>'{items,0,host_show_name}','host','shared contest identifies host');
select is(jsonb_array_length(get_offering_contest_animals(pg_temp.fx('cart'),pg_temp.fx('kid'),pg_temp.fx('contest'))),2,'youth cavy entered and current-cart animals eligible');
select is(jsonb_array_length(get_offering_contest_animals(pg_temp.fx('host_cart'),pg_temp.fx('kid'),pg_temp.fx('contest'))),1,'rabbit portal accepts already entered youth cavy animal');
select is(jsonb_array_length(get_offering_contest_animals(pg_temp.fx('cart'),pg_temp.fx('adult'),pg_temp.fx('contest'))),0,'Open-only cavy animals excluded from youth contest');
select is(jsonb_array_length(get_offering_contest_animals(pg_temp.fx('ordinary_cart'),pg_temp.fx('kid'),pg_temp.fx('contest'))),0,'unrelated show cannot use linked animals');
select throws_ok($$select get_offering_contest_animals(pg_temp.fx('cart'),pg_temp.fx('stranger'),pg_temp.fx('contest'))$$,'42501','Choose an active exhibitor from this household.','cross-show animal picker retains ownership protection');
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('not_linked'),pg_temp.fx('kid'),1,'{}')$$,'P0001','This contest or add-on is not available.','unlinked contests cannot be purchased from Cavy cart');
select throws_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('adult'),1,'{}')$$,'P0001','contest requires a youth animal entry in the rabbit or linked cavy show for this exhibitor.','Open-only exhibitor cannot bypass youth requirement');
select lives_ok($$select save_cart_addon(pg_temp.fx('cart'),pg_temp.fx('contest'),pg_temp.fx('kid'),1,'{}',null,get_offering_contest_animals(pg_temp.fx('cart'),pg_temp.fx('kid'),pg_temp.fx('contest'))#>>'{0,key}')$$,'youth cavy enters canonical rabbit contest from Cavy cart');
reset role;
select is((select show_id from show_addons_private.selections where cart_id=pg_temp.fx('cart')),pg_temp.fx('host'),'registration stored under rabbit portal');
select is((select cart_id from show_addons_private.selections where exhibitor_id=pg_temp.fx('kid')),pg_temp.fx('cart'),'charge remains in original Cavy cart');
select is((select count(*)::int from entry_carts where show_id=pg_temp.fx('host')),1,'no additional Rabbit cart or duplicate show fee created');
select is((select unit_price_cents from show_addons_private.selections where cart_id=pg_temp.fx('cart')),500,'canonical contest fee retained');
set local role authenticated;
select throws_ok($$select save_cart_addon(pg_temp.fx('host_cart'),pg_temp.fx('contest'),pg_temp.fx('kid'),1,'{}',null,get_offering_contest_animals(pg_temp.fx('host_cart'),pg_temp.fx('kid'),pg_temp.fx('contest'))#>>'{0,key}')$$,'P0001','The limit for contest is 1 per exhibitor across the full show.','same child cannot register again through rabbit portal');
select lives_ok($$select save_cart_registration_requirements(pg_temp.fx('cart'),'hlsr-2027-handbook-v2',true,pg_temp.schools())$$,'updated cart can be accepted');
select lives_ok($$select commit_entry_cart_day_of(pg_temp.fx('cart'))$$,'Cavy checkout with shared contest and requirements completes without provider payment');
select pg_temp.actor('secretary');
select is(jsonb_array_length(get_show_addon_registrations(pg_temp.fx('host'))),1,'rabbit secretary sees youth cavy registration in same roster');
select is(jsonb_array_length(get_show_addon_registrations(pg_temp.fx('cavy'))),0,'no duplicate Cavy contest roster');
reset role;
select ok(position('show_registration_private.validate_cart' in pg_get_functiondef('public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)'::regprocedure))>0,'online checkout guard installed');
select ok(position('show_registration_private.validate_cart' in pg_get_functiondef('public.commit_free_entry_cart(uuid)'::regprocedure))>0,'free checkout guard installed');
select * from finish();
rollback;
