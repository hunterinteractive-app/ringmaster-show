-- Disposable DB only. All customers, carts, code usage, payments and jobs roll back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(1);
create function pg_temp.check_ok(v boolean,msg text) returns void language plpgsql as $$begin if not coalesce(v,false) then raise exception 'FAILED: %',msg; end if; end $$;
create function pg_temp.new_cart(o uuid,s uuid,e uuid,sec uuid,tag text) returns uuid language plpgsql as $$
declare c uuid:=gen_random_uuid(); begin
 insert into public.entry_carts(id,user_id,show_id) values(c,o,s);
 insert into public.entry_cart_items(cart_id,section_id,species,tattoo,breed,variety,sex,class_name,exhibitor_id,is_fur)
 values(c,sec,'rabbit',tag,'Dutch','Black','Buck','Senior',e,false);
 return c;
end $$;
do $$
declare o uuid:=gen_random_uuid(); stranger uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); sec uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); e2 uuid:=gen_random_uuid();
 c1 uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; c6 uuid; c7 uuid; code_id uuid; quote jsonb; result jsonb; b public.show_exhibitor_balances; prior jsonb; sid uuid;
begin
 insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 (o,'authenticated','authenticated','discount-'||o||'@example.invalid',now(),now(),now()),
 (stranger,'authenticated','authenticated','discount-'||stranger||'@example.invalid',now(),now(),now());
 insert into public.shows(id,created_by,name,start_date,end_date,entry_close_at,payment_timing_mode,is_test)
 values(s,o,'Discount test',current_date,current_date+1,now()+interval '1 day','online_or_at_show',true);
 insert into public.show_sections(id,show_id,kind,letter,display_name) values(sec,s,'open','A','Open A');
 insert into public.show_fee_settings(show_id,currency) values(s,'USD');
 insert into public.show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee) values(sec,12,0,3)
 on conflict(section_id) do update set fee_per_entry=12,fee_per_show=0,fur_fee=3;
 insert into public.exhibitors(id,owner_user_id,type,display_name,email,is_local_only,created_for_show_id,is_test)
 values(e,o,'adult','Discount Adult','test@example.invalid',true,s,true),(e2,o,'youth','Discount Youth','test2@example.invalid',true,s,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','authenticated')::text,true);
 result:=public.manage_show_discount_code(s,p_code=>'member20',p_type=>'amount',p_basis=>'overall',p_value=>20,p_action=>'save');
 code_id:=(result->0->>'id')::uuid;
 perform pg_temp.check_ok(result->0->>'code'='MEMBER20','custom codes normalized');
 result:=public.manage_show_discount_code(s,p_code=>null,p_value=>1,p_action=>'save');
 perform pg_temp.check_ok(jsonb_array_length(result)=2 and exists(select 1 from jsonb_array_elements(result) x where length(x->>'code')=12),'server random code');
 c1:=pg_temp.new_cart(o,s,e,sec,'ONE');
 result:=public.entry_cart_discounts(c1,'bogus',e);
 perform pg_temp.check_ok(result ? 'error','invalid code rejected');
 result:=public.entry_cart_discounts(c1,' member20 ',e);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=1200,'first checkout consumes 12 of 20');
 perform public.commit_free_entry_cart(c1);
 perform pg_temp.check_ok((select payment_status='paid' and status='submitted' from public.entry_carts where id=c1),'free entries can submit without payment provider');
 perform pg_temp.check_ok((select bool_and(payment_status='paid') from public.entries where source_cart_id=c1),'free entries are paid');
 perform pg_temp.check_ok(public.commit_free_entry_cart(c1)=0,'free retry idempotent');
 c2:=pg_temp.new_cart(o,s,e,sec,'TWO');
 result:=public.entry_cart_discounts(c2);
 perform pg_temp.check_ok(jsonb_array_length(result->'codes')=1,'code persists into next cart');
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=800,'8 dollars carries forward');
 perform pg_temp.check_ok((result->'balances'->0->>'balance_due_cents')::int=400,'second checkout owes 4');
 result:=public.entry_cart_discounts(c2,'MEMBER20',e);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=800,'reapplying code cannot double discount');
 begin perform public.commit_free_entry_cart(c2); raise exception 'unexpected success'; exception when others then if sqlerrm='unexpected success' then raise; end if; end;
 perform public.commit_entry_cart_day_of(c2);
 c3:=pg_temp.new_cart(o,s,e,sec,'THREE');
 result:=public.entry_cart_discounts(c3);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=0,'overall discount exhausted');
 result:=public.manage_show_discount_code(s,p_code=>'TENPER',p_value=>10,p_action=>'save');
 result:=public.entry_cart_discounts(c3,'TENPER',e);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=1000,'better code replaces prior overall without stacking');
 -- Fur and per-show fees must never consume the entry discount.
 insert into public.entry_cart_items(cart_id,section_id,species,tattoo,breed,variety,sex,class_name,exhibitor_id,is_fur)
 values(c3,sec,'rabbit','THREE','Dutch','Black','Buck','Senior',e,true);
 result:=public.entry_cart_discounts(c3);
 perform pg_temp.check_ok((result->'balances'->0->>'balance_due_cents')::int=500,'fur excluded');
 -- Pending checkout freezes the quote and reserves its discount for other carts.
 insert into public.show_payment_settings(show_id,stripe_enabled,default_online_provider) values(s,true,'stripe');
 insert into public.show_payment_account_links(show_id,provider,status,account_status,charges_enabled,stripe_account_id,provider_account_id)
 values(s,'stripe','active','ready',true,'acct_discount_test','acct_discount_test');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','service_role')::text,true);
 quote:=public.create_payment_quote_attempt(c3,o,'stripe'); sid:=(quote->>'payment_session_id')::uuid;
 select to_jsonb(x) into prior from public.show_exhibitor_balances x where entry_cart_id=c3;
 c4:=pg_temp.new_cart(o,s,e,sec,'FOUR');
 perform 1 from public.calculate_entry_cart_balance_internal(c4);
 perform pg_temp.check_ok((select discount_cents=1000 from public.show_exhibitor_balances where entry_cart_id=c4),'pending discount reserved; next entry only earns its own discount');
 update entry_discount_private.codes set value=11 where show_id=s and code='TENPER';
 perform 1 from public.calculate_entry_cart_balance_internal(c3);
 perform pg_temp.check_ok((select discount_cents=1000 and calculated_total_cents=500 from public.show_exhibitor_balances where entry_cart_id=c3),'pending price remains frozen after rule change');
 perform public.finalize_entry_cart_paid(c3,sid,'stripe','pi_discount_test',(quote->'quote'->>'expected_amount_cents')::int,'usd');
 perform public.finalize_entry_cart_paid(c3,sid,'stripe','pi_discount_test',(quote->'quote'->>'expected_amount_cents')::int,'usd');
 perform pg_temp.check_ok((select count(*)=2 from public.entries where source_cart_id=c3),'webhook retry does not duplicate entry or fur');
 perform pg_temp.check_ok((select discount_cents=1000 and paid_online_cents=500 and balance_due_cents=0 from public.show_exhibitor_balances where entry_cart_id=c3),'frozen discounted amount finalized correctly');
 -- Separate exhibitor cannot inherit another family member's code.
 c5:=pg_temp.new_cart(o,s,e2,sec,'YOUTH1');
 result:=public.entry_cart_discounts(c5);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=0 and jsonb_array_length(result->'codes')=0,'per-exhibitor separation');
 update public.show_fee_settings set multi_show_discount_enabled=true,multi_show_discount_type='amount',multi_show_discount_value=2,
 multi_show_discount_basis='cumulative',multi_show_discount_min_entries=2,multi_show_discount_required_shows=1 where show_id=s;
 perform public.commit_entry_cart_day_of(c5);
 c6:=pg_temp.new_cart(o,s,e2,sec,'YOUTH2');
 result:=public.entry_cart_discounts(c6);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=400,'volume qualification includes earlier checkout');
 perform public.commit_entry_cart_day_of(c6);
 c7:=pg_temp.new_cart(o,s,e2,sec,'YOUTH3');
 result:=public.entry_cart_discounts(c7,'MEMBER20',e2);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=1200,'best overall saves 20 less prior 4 capped at current 12');
 update entry_discount_private.codes set enabled=false where id=code_id;
 result:=public.entry_cart_discounts(c7);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=200,'disabled code no longer discounts new checkout');
 -- Candidate calculator: literal percentage and per-entry capped fixed rate.
 perform pg_temp.check_ok(entry_discount_private.candidate('[{"section_id":"s","kind":"open","letter":"A","entry_count":2,"entries_subtotal_cents":2400}]','percent',0.5)=12,'half a percent means half a percent');
 perform pg_temp.check_ok(entry_discount_private.candidate('[{"section_id":"s","kind":"open","letter":"A","entry_count":2,"entries_subtotal_cents":2400}]','fixed_rate',8)=800,'reduced rate');

 -- A full entry discount leaves per-show and one-time exhibitor fees payable.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'role','service_role')::text,true);
 update public.show_fee_settings set exhibitor_fee_enabled=true,exhibitor_fee_label='Facility Fee',exhibitor_fee_amount=7.5 where show_id=s;
 update public.show_section_fee_settings set fee_per_show=2 where section_id=sec;
 e2:=gen_random_uuid();
 insert into public.exhibitors(id,owner_user_id,type,display_name,email,is_local_only,created_for_show_id,is_test)
 values(e2,o,'adult','Fee Exclusion Test','fee@example.invalid',true,s,true);
 c7:=pg_temp.new_cart(o,s,e2,sec,'FEES');
 result:=public.manage_show_discount_code(s,p_code=>'FREEENTRY',p_type=>'percent',p_value=>100,p_action=>'save');
 result:=public.entry_cart_discounts(c7,'FREEENTRY',e2);
 perform pg_temp.check_ok((result->'balances'->0->>'discount_cents')::int=1200,'100 percent code discounts only the entry');
 perform pg_temp.check_ok((result->'balances'->0->>'balance_due_cents')::int=950,'per-show and one-time exhibitor fees remain due');
 -- Auth checks are independent of a trusted caller-provided owner ID.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger,'role','authenticated')::text,true);
 begin perform public.entry_cart_discounts(c7); raise exception 'unexpected success'; exception when insufficient_privilege then null; end;
 begin perform public.manage_show_discount_code(s); raise exception 'unexpected success'; exception when insufficient_privilege then null; end;
 perform pg_temp.check_ok(not has_table_privilege('authenticated','entry_discount_private.codes','SELECT'),'codes cannot be enumerated by exhibitors');
 perform pg_temp.check_ok(not has_function_privilege('authenticated','public.calculate_entry_cart_balance_internal(uuid)','EXECUTE'),'internal calculator private');
 perform pg_temp.check_ok(not has_function_privilege('anon','public.entry_cart_discounts(uuid,text,uuid)','EXECUTE'),'anonymous redemption denied');
end $$;
select pass('carryover, best discount, zero checkout, pending reservations, immutable payments, retry and authorization assertions passed');
select * from finish();
rollback;
