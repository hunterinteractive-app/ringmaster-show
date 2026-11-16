begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table fx(k text primary key,id uuid default gen_random_uuid());
insert into fx(k) values('secretary'),('buyer'),('other'),('show'),('ordinary'),('section'),('ordinary_section'),('kid'),('stranger'),('cart'),('free_cart'),('paid_cart'),('ordinary_cart'),('pending'),('known'),('free'),('paid');
grant select on fx to authenticated;
create function pg_temp.fx(text) returns uuid language sql as $$select id from fx where k=$1$$;
create function pg_temp.actor(text) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx($1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fx($1),'role','authenticated')::text,true);
end;$$;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',k||'-'||id||'@example.invalid','{}','{}' from fx where k in('secretary','buyer','other');
insert into shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test,entry_open_at,entry_close_at,payment_timing_mode,online_payment_fee_mode)
select id,pg_temp.fx('secretary'),pg_temp.fx('secretary'),k,current_date,current_date+2,true,true,now()-interval '1 day',now()+interval '1 day','online_or_at_show','club_absorbs'
from fx where k in('show','ordinary');
insert into meat_pens_private.enabled_shows values(pg_temp.fx('show'));
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
select id,k,case when k='stranger' then pg_temp.fx('other') else pg_temp.fx('buyer') end,
 997100+row_number() over(order by k),k||'@example.invalid',true,true from fx where k in('kid','stranger');
insert into breeds(name,species,class_system,is_active) values('Californian','rabbit','six',true);
insert into show_sections(id,show_id,kind,letter,display_name,sort_order,breed_scope,allow_meat_classes) values
 (pg_temp.fx('section'),pg_temp.fx('show'),'youth','A','Youth Meat Pen',1,'meat_only',true),
 (pg_temp.fx('ordinary_section'),pg_temp.fx('ordinary'),'youth','A','Youth Meat Pen',1,'meat_only',true);
insert into show_commercial_classes(show_id,class_code,display_name,is_enabled)
select id,'meat_pen','Meat Pens',true from fx where k in('show','ordinary');
insert into show_fee_settings(show_id,currency) select id,'USD' from fx where k in('show','ordinary');
insert into show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee)
select id,0,0,0 from fx where k like '%section' on conflict(section_id) do update set fee_per_entry=0,fee_per_show=0,fur_fee=0;
insert into entry_carts(id,user_id,show_id) select id,pg_temp.fx('buyer'),case when k='ordinary_cart' then pg_temp.fx('ordinary') else pg_temp.fx('show') end
from fx where k in('cart','free_cart','paid_cart','ordinary_cart');
select pg_temp.actor('buyer');
set local role authenticated;
select ok(meat_pen_registration_enabled(pg_temp.fx('show')),'enabled show offers deferred tattoos');
select ok(not meat_pen_registration_enabled(pg_temp.fx('ordinary')),'other shows unchanged');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,species,breed,variety,class_name,meat_pen_tattoos) values
 (pg_temp.fx('pending'),pg_temp.fx('cart'),pg_temp.fx('section'),pg_temp.fx('kid'),'rabbit','Californian','Standard','Meat Pen','{}'),
 (pg_temp.fx('known'),pg_temp.fx('cart'),pg_temp.fx('section'),pg_temp.fx('kid'),'rabbit','Californian','Standard','Meat Pen',array['A','B','C']),
 (pg_temp.fx('free'),pg_temp.fx('free_cart'),pg_temp.fx('section'),pg_temp.fx('kid'),'rabbit','Californian','Standard','Meat Pen','{}'),
 (pg_temp.fx('paid'),pg_temp.fx('paid_cart'),pg_temp.fx('section'),pg_temp.fx('kid'),'rabbit','Californian','Standard','Meat Pen','{}');
select is((select count(distinct meat_pen_id)::int from entry_cart_items where cart_id=pg_temp.fx('cart')),2,'each pen has a unique assigned identity');
select ok(tattoo like 'MP-% | Tattoos not yet assigned','pending is a label, not a fabricated tattoo') from entry_cart_items where id=pg_temp.fx('pending');
select throws_ok($$update entry_cart_items set meat_pen_id='MP-FORGE' where id=pg_temp.fx('pending')$$,'23514','The Pen ID cannot be changed.','client cannot change Pen ID');
select throws_ok($$update entry_cart_items set meat_pen_tattoos=array['A','B'] where id=pg_temp.fx('pending')$$,'23514','Enter all 3 tattoos, or select Tattoos not yet assigned.','partial tattoos rejected');
select throws_ok($$insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,breed,variety,class_name,meat_pen_tattoos) values(pg_temp.fx('ordinary_cart'),pg_temp.fx('ordinary_section'),pg_temp.fx('kid'),'rabbit','Californian','Standard','Meat Pen','{}')$$,'23514','Deferred meat-pen tattoos are not enabled for this show.','pending cannot be used in other shows');
select lives_ok($$insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,breed,variety,class_name,tattoo) values(pg_temp.fx('ordinary_cart'),pg_temp.fx('ordinary_section'),pg_temp.fx('kid'),'rabbit','Californian','Standard','Meat Pen','X / Y / Z')$$,'ordinary meat pens still accept existing format');
select lives_ok($$insert into entry_cart_items(cart_id,section_id,exhibitor_id,species,breed,variety,class_name,tattoo) values(pg_temp.fx('cart'),pg_temp.fx('section'),pg_temp.fx('kid'),'rabbit','Californian','Standard','Meat Pen','X / X / X')$$,'older app submissions still accept supplied tattoos');
select is((select tattoo from entry_cart_items where cart_id=pg_temp.fx('cart') and tattoo='X / X / X'),'X / X / X','legacy submission response keeps provided fields for idempotent retry');
delete from entry_cart_items where cart_id=pg_temp.fx('cart') and tattoo='X / X / X';
select lives_ok($$select commit_entry_cart_day_of(pg_temp.fx('cart'))$$,'pending and known pens submit without changing existing checkout');
select lives_ok($$select commit_entry_cart_day_of(pg_temp.fx('cart'))$$,'retry submission is idempotent');
select is((select count(*)::int from entries where source_cart_id=pg_temp.fx('cart')),2,'submission retry does not duplicate pens');
select is((select e.meat_pen_id from entries e where source_cart_item_id=pg_temp.fx('pending')),
 (select meat_pen_id from entry_cart_items where id=pg_temp.fx('pending')),'checkout retains original Pen ID');
select lives_ok($$select commit_free_entry_cart(pg_temp.fx('free_cart'))$$,'free checkout accepts pending tattoos');
select is((select e.meat_pen_id from entries e where source_cart_item_id=pg_temp.fx('free')),
 (select meat_pen_id from entry_cart_items where id=pg_temp.fx('free')),'free checkout retains Pen ID');
reset role;
update show_section_fee_settings set fee_per_entry=8 where section_id=pg_temp.fx('section');
insert into show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider)
values(pg_temp.fx('show'),false,true,false,'square');
insert into show_payment_account_links(show_id,provider,status,provider_account_id,provider_location_id)
values(pg_temp.fx('show'),'square','active','LOCAL-MEAT-PEN','LOCAL-LOCATION');
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fx('buyer'),'role','service_role')::text,true);
select lives_ok($$select create_payment_quote_attempt(pg_temp.fx('paid_cart'),pg_temp.fx('buyer'),'square',0.03,0.029,30)$$,'local paid checkout quote accepts pending pen');
select lives_ok($$select finalize_entry_cart_paid(pg_temp.fx('paid_cart'),s.id,'square','LOCAL-ONLY-NO-REAL-CHARGE',s.expected_amount_cents,s.expected_currency) from show_payment_sessions s where s.cart_id=pg_temp.fx('paid_cart')$$,'local Square finalization accepts pending pen');
select is((select meat_pen_id from entries where source_cart_item_id=pg_temp.fx('paid')),(select meat_pen_id from entry_cart_items where id=pg_temp.fx('paid')),'paid checkout retains original Pen ID');
select lives_ok($$select finalize_entry_cart_paid(pg_temp.fx('paid_cart'),s.id,'square','LOCAL-ONLY-NO-REAL-CHARGE',s.expected_amount_cents,s.expected_currency) from show_payment_sessions s where s.cart_id=pg_temp.fx('paid_cart')$$,'paid checkout retry is idempotent');
select is((select count(*)::int from entries where source_cart_item_id=pg_temp.fx('paid')),1,'paid retry does not duplicate pen');
select pg_temp.actor('buyer');
create temporary table before_change as select to_jsonb(e)-array['tattoo','meat_pen_tattoos','updated_at']::text[] snapshot from entries e where source_cart_item_id=pg_temp.fx('pending');
create temporary table paid_before as select to_jsonb(e)-array['tattoo','meat_pen_tattoos','updated_at']::text[] snapshot from entries e where source_cart_item_id=pg_temp.fx('paid');
create temporary table payments_before as select to_jsonb(p) snapshot from show_payments p;
set local role authenticated;
select lives_ok($$select update_meat_pen_tattoos((select id from entries where source_cart_item_id=pg_temp.fx('pending')),array[' p1 ','p2','p3'])$$,'household can add actual tattoos before deadline');
select lives_ok($$select update_meat_pen_tattoos((select id from entries where source_cart_item_id=pg_temp.fx('paid')),array['R1','R2','R3'])$$,'paid entry can receive actual tattoos without another checkout');
select is((select meat_pen_tattoos from entries where source_cart_item_id=pg_temp.fx('pending')),array['P1','P2','P3'],'actual tattoos trimmed and uppercased');
select throws_ok($$select update_meat_pen_tattoos((select id from entries where source_cart_item_id=pg_temp.fx('pending')),array['','p2','p3'])$$,'23514','Enter all 3 tattoos, or select Tattoos not yet assigned.','blank tattoo rejected');
reset role;
select is((select to_jsonb(e)-array['tattoo','meat_pen_tattoos','updated_at']::text[] from entries e where source_cart_item_id=pg_temp.fx('pending')),(select snapshot from before_change),'identity, ownership, entry and payment fields unchanged');
select is((select to_jsonb(e)-array['tattoo','meat_pen_tattoos','updated_at']::text[] from entries e where source_cart_item_id=pg_temp.fx('paid')),(select snapshot from paid_before),'paid amount and payment provenance remain unchanged');
select results_eq($$select to_jsonb(p) from show_payments p$$,$$select snapshot from payments_before$$,'no payment ledger changes');
select is((select count(*)::int from meat_pens_private.tattoo_changes),2,'tattoo change audited');
create temporary table target as select id from entries where source_cart_item_id=pg_temp.fx('pending');
grant select on target to authenticated,anon;
select pg_temp.actor('other');
set local role authenticated;
select throws_ok($$select update_meat_pen_tattoos((select id from target),array['Z1','Z2','Z3'])$$,'42501','You do not have permission to update this meat pen.','unrelated account cannot edit tattoos');
select throws_ok($$select * from meat_pens_private.tattoo_changes$$,'42501','permission denied for table tattoo_changes','audit information is private');
reset role;
select pg_temp.actor('secretary');
set local role authenticated;
select lives_ok($$select update_meat_pen_tattoos((select id from target),array['S1','S2','S3'])$$,'secretary can update same pen');
reset role;
-- The deadline applies to both account and secretary updates, even while the
-- show is unlocked. A direct entry update cannot bypass the cutoff either.
create temporary table after_change as select to_jsonb(e) snapshot from entries e where id=(select id from target);
update shows set entry_close_at=now()-interval '1 hour' where id=pg_temp.fx('show');
select pg_temp.actor('buyer');
set local role authenticated;
select throws_ok($$select update_meat_pen_tattoos((select id from target),array['D1','D2','D3'])$$,'P0001','Entry deadline passed. Tattoos can no longer be changed.','household cannot update after entry deadline');
reset role;
select pg_temp.actor('secretary');
set local role authenticated;
select throws_ok($$select update_meat_pen_tattoos((select id from target),array['D1','D2','D3'])$$,'P0001','Entry deadline passed. Tattoos can no longer be changed.','secretary cannot update after entry deadline');
with changed as (update entries set meat_pen_tattoos=array['D1','D2','D3'] where id=(select id from target) returning id) select is(count(*),0::bigint,'row policy prevents direct staff update after deadline') from changed;
reset role;
select throws_ok($$update entries set meat_pen_tattoos=array['D1','D2','D3'] where id=(select id from target)$$,'P0001','Entry deadline passed. Tattoos can no longer be changed.','table trigger enforces deadline even when row policies are bypassed');
select is((select to_jsonb(e) from entries e where id=(select id from target)),(select snapshot from after_change),'rejected changes preserve complete entry including ID and tattoos');
select is((select count(*)::int from meat_pens_private.tattoo_changes),3,'rejected updates create no tattoo audit changes');
update shows set entry_close_at=now() where id=pg_temp.fx('show');
set local role authenticated;
select throws_ok($$select update_meat_pen_tattoos((select id from target),array['D1','D2','D3'])$$,'P0001','Entry deadline passed. Tattoos can no longer be changed.','deadline boundary is closed');
reset role;
update shows set entry_close_at=null where id=pg_temp.fx('show');
set local role authenticated;
select lives_ok($$select update_meat_pen_tattoos((select id from target),array['N1','N2','N3'])$$,'no configured deadline retains ordinary editing availability');
reset role;
update shows set is_locked=true where id=pg_temp.fx('show');
set local role authenticated;
select throws_ok($$select update_meat_pen_tattoos((select id from target),array['L1','L2','L3'])$$,'P0001','Show is locked. Changes are not allowed.','locked show remains protected');
reset role;
set local role anon;
select throws_ok($$select update_meat_pen_tattoos((select id from target),array['L1','L2','L3'])$$,'42501','permission denied for function update_meat_pen_tattoos','anonymous caller denied');
reset role;
select * from finish();
rollback;
