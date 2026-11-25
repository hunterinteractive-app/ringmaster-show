-- Isolated local database only. All fixtures, emails and payments roll back.
begin;
select no_plan();
create function pg_temp.check_ok(v boolean,m text) returns void language plpgsql as $$
begin if not coalesce(v,false) then raise exception 'FAIL: %',m; end if; end $$;
create temporary table fur_context(owner_id uuid,other_id uuid,show_id uuid,exhibitor_id uuid,
 animal_id uuid,a uuid,b uuid,c uuid,entry_id uuid,cart_id uuid,original_entries jsonb,original_balances jsonb);
do $$
declare o uuid:=gen_random_uuid(); x uuid:=gen_random_uuid(); s uuid:=gen_random_uuid();
 ex uuid:=gen_random_uuid(); animal uuid:=gen_random_uuid(); a uuid:=gen_random_uuid();
 b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); ent uuid; cart uuid;
begin
 insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
 values(o,'authenticated','authenticated',o||'@example.invalid','{}','{}'),(x,'authenticated','authenticated',x||'@example.invalid','{}','{}');
 insert into public.shows(id,created_by,name,start_date,end_date,entry_open_at,entry_close_at,payment_timing_mode,is_test,is_published)
 values(s,o,'Fur additions test',current_date+5,current_date+5,now()-interval '1 day',now()+interval '1 day','pay_at_show_only',true,true);
 insert into public.exhibitors(id,type,display_name,owner_user_id,is_active,is_test,email)
 values(ex,'adult','Fur Test',o,true,true,'fur-test@example.invalid');
 insert into public.animals(id,owner_user_id,exhibitor_id,species,tattoo,breed,variety,sex)
 values(animal,o,ex,'rabbit','FUR1','Havana','Black','Buck');
 insert into public.show_sections(id,show_id,kind,letter,display_name,is_enabled)
 values(a,s,'open','A','Open A',true),(b,s,'open','B','Open B',true),(c,s,'open','C','Open C',true);
 insert into public.show_fee_settings(show_id,currency) values(s,'USD');
 insert into public.show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee)
 values(a,4,5,2),(b,4,5,3),(c,4,5,0)
 on conflict(section_id) do update set fee_per_entry=excluded.fee_per_entry,fee_per_show=excluded.fee_per_show,fur_fee=excluded.fur_fee;
 insert into public.entry_carts(user_id,show_id) values(o,s) returning id into cart;
 insert into public.entry_cart_items(cart_id,section_id,animal_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name)
 select cart,sec,animal,ex,'rabbit','FUR1','Havana','Black','Buck','Senior' from unnest(array[a,b,c]) sec;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
 perform public.commit_entry_cart_day_of(cart);
 select id into ent from public.entries where source_cart_id=cart and section_id=a;
 insert into fur_context values(o,x,s,ex,animal,a,b,c,ent,null,
 (select jsonb_agg(to_jsonb(t) order by id) from public.entries t where source_cart_id=cart),
 (select jsonb_agg(to_jsonb(t) order by id) from public.show_exhibitor_balances t where entry_cart_id=cart));
end $$;
-- Real authenticated role: ownership, available sections and unavailable fees.
grant select,update on fur_context to authenticated;
set local role authenticated;
do $$
declare f record;r jsonb;blocked boolean;
begin
 select * into f from fur_context;
 r:=public.exhibitor_fur_additions(f.entry_id);
 perform pg_temp.check_ok(jsonb_array_length(r->'sections')=2,'only sections with a fur fee appear');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.other_id,'role','authenticated')::text,true);
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id,array[f.a],'Colored'); exception when insufficient_privilege then blocked:=true; end;
 perform pg_temp.check_ok(blocked,'other household rejected');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.owner_id,'role','authenticated')::text,true);
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id,array[f.c],'Colored'); exception when others then raise notice 'Ineligible section rejection: %',sqlerrm; blocked:=sqlerrm like '%not eligible%'; end;
 perform pg_temp.check_ok(blocked,'no fur offering rejected');
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id,array[f.a],null); exception when others then blocked:=sqlerrm like 'Choose White%'; end;
 perform pg_temp.check_ok(blocked,'missing class rejected');
 r:=public.exhibitor_fur_additions(f.entry_id,array[f.a,f.b,f.a],'Colored');
 update fur_context set cart_id=(r->>'cart_id')::uuid;
 perform pg_temp.check_ok((r->>'added_count')::int=2,'duplicate section selection adds two lines only');
 r:=public.exhibitor_fur_additions(f.entry_id,array[f.a,f.b],'White');
 perform pg_temp.check_ok((r->>'added_count')::int=0,'repeat click and different color do not duplicate');
 r:=public.exhibitor_fur_additions(f.entry_id);
 perform pg_temp.check_ok(r->>'cart_id' is not null and (r->'sections'->0->>'unavailable_reason')='Already in cart','pending additions expose their resumable cart');
end $$;
reset role;
do $$
declare f record;r jsonb;blocked boolean;original_count int;
begin
 select * into f from fur_context;
 perform pg_temp.check_ok((select count(*)=2 and bool_and(is_fur) from public.entry_cart_items where cart_id=f.cart_id),'only fur lines');
 perform pg_temp.check_ok((select calculated_total_cents=500 from public.show_exhibitor_balances where entry_cart_id=f.cart_id),'fur-only fees 2+3, no regular or flat fee');
 perform pg_temp.check_ok((select count(*)=3 from public.entries where show_id=f.show_id),'cart is draft until confirmation');
 perform public.commit_entry_cart_day_of(f.cart_id);
 perform pg_temp.check_ok((select count(*)=2 from public.entries where source_cart_id=f.cart_id and is_fur),'pay at show creates two fur entries');
 perform pg_temp.check_ok((select count(*)=3 from public.entries where show_id=f.show_id and not is_fur),'original class entries unchanged');
 perform pg_temp.check_ok((select balance_due_cents=500 from public.show_exhibitor_balances where entry_cart_id=f.cart_id),'new balance due is 5 dollars');
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id,array[f.a],'Colored'); exception when others then blocked:=sqlerrm like '%Already entered%'; end;
 perform pg_temp.check_ok(blocked,'submitted fur cannot be bought twice');
 update public.shows set entry_close_at=now() where id=f.show_id;
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id); exception when others then blocked:=sqlerrm like '%while entries are open%'; end;
 perform pg_temp.check_ok(blocked,'deadline exact boundary rejected');
 update public.shows set entry_close_at=now()+interval '1 day',entry_open_at=now()+interval '1 hour' where id=f.show_id;
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id); exception when others then blocked:=sqlerrm like '%while entries are open%'; end;
 perform pg_temp.check_ok(blocked,'future opening rejected');
 update public.shows set entry_open_at=now()-interval '1 day',is_locked=true where id=f.show_id;
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id); exception when others then blocked:=sqlerrm like '%while entries are open%'; end;
 perform pg_temp.check_ok(blocked,'locked show rejected');
 update public.shows set is_locked=false,payment_timing_mode='online_only',online_payment_fee_mode='club_absorbs' where id=f.show_id;
 -- Remove only synthetic fur rows/cart to exercise the same existing class
 -- entries through the online-only path. Rollback restores everything.
 delete from public.entries where source_cart_id=f.cart_id;
 delete from public.show_exhibitor_balances where entry_cart_id=f.cart_id;
 delete from public.entry_cart_items where cart_id=f.cart_id;
 delete from public.entry_carts where id=f.cart_id;
 insert into public.show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider)
 values(f.show_id,true,false,false,'stripe');
 insert into public.show_payment_account_links(show_id,provider,status,account_status,charges_enabled,stripe_account_id,provider_account_id)
 values(f.show_id,'stripe','active','ready',true,'acct_fur_test','acct_fur_test');
 r:=public.exhibitor_fur_additions(f.entry_id,array[f.a,f.b],'Colored');
 update fur_context set cart_id=(r->>'cart_id')::uuid;
end $$;
do $$
declare f record;q jsonb;q2 jsonb;sid uuid;amount int;blocked boolean;
begin
 select * into f from fur_context;
 blocked:=false;
 begin perform public.commit_entry_cart_day_of(f.cart_id); exception when others then blocked:=sqlerrm like '%does not allow payment at the show%'; end;
 perform pg_temp.check_ok(blocked,'online-only cannot submit without payment');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.owner_id,'role','service_role')::text,true);
 q:=public.create_payment_quote_attempt(f.cart_id,f.owner_id,'stripe',0.02,0.029,30);
 sid:=(q->>'payment_session_id')::uuid;
 select expected_amount_cents into amount from public.show_payment_sessions where id=sid;
 perform pg_temp.check_ok(amount=500,'online payment covers only fur fees');
 q2:=public.create_payment_quote_attempt(f.cart_id,f.owner_id,'stripe',0.02,0.029,30);
 perform pg_temp.check_ok(q2->>'payment_session_id'=sid::text,'checkout repeated click reuses quote');
 blocked:=false;
 begin perform public.exhibitor_fur_additions(f.entry_id,array[f.a],'Colored'); exception when others then blocked:=sqlerrm like '%payment in progress%'; end;
 perform pg_temp.check_ok(blocked,'in-flight checkout cannot be edited');
 perform public.finalize_entry_cart_paid(f.cart_id,sid,'stripe','pi_fur_test',amount,'usd');
 perform public.finalize_entry_cart_paid(f.cart_id,sid,'stripe','pi_fur_test',amount,'usd');
 perform pg_temp.check_ok((select count(*)=2 and bool_and(is_fur) from public.entries where source_cart_id=f.cart_id),'webhook retry creates exactly two fur entries');
 perform pg_temp.check_ok((select balance_due_cents=0 and paid_online_cents=500 from public.show_exhibitor_balances where entry_cart_id=f.cart_id),'paid fur balance settled');
 perform pg_temp.check_ok((select jsonb_agg(to_jsonb(t) order by id) from public.entries t where show_id=f.show_id and not is_fur)=f.original_entries,'original class entry rows remain unchanged');
 perform pg_temp.check_ok((select jsonb_agg(to_jsonb(t) order by id) from public.show_exhibitor_balances t where entry_cart_id=(select source_cart_id from public.entries where id=f.entry_id))=f.original_balances,'original charge and payment rows remain unchanged');
end $$;
select pass('Fur additions: authorization, windows, sections, duplicates, fees, offline and online finalization');
select * from finish();
rollback;
