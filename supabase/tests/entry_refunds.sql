-- Only disposable fixtures; no network calls and everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(1);
create function pg_temp.expect_error(statement text, fragment text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if position(lower(fragment) in lower(sqlerrm))>0 then return; end if;
    raise exception 'Unexpected error for %: %',statement,sqlerrm;
  end;
  raise exception 'Expected error containing % for %',fragment,statement;
end;
$$;
create function pg_temp.check_true(v boolean, message text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'Assertion failed: %',message; end if; end;
$$;

do $$
#variable_conflict use_variable
declare owner_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid(); show_id uuid:=gen_random_uuid();
  ex uuid:=gen_random_uuid(); section_id uuid:=gen_random_uuid(); cart uuid:=gen_random_uuid();
  b uuid:=gen_random_uuid(); payment uuid:=gen_random_uuid(); ids uuid[]; request_id uuid:=gen_random_uuid();
  next_id uuid:=gen_random_uuid(); failed_id uuid:=gen_random_uuid(); manual_id uuid:=gen_random_uuid();
  manual_payment uuid:=gen_random_uuid(); manual_b uuid:=gen_random_uuid(); manual_entry uuid:=gen_random_uuid();
  response jsonb; balance public.show_exhibitor_balances%rowtype; n integer;
begin
  insert into auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    values(owner_id,'authenticated','authenticated','refund-owner-'||owner_id||'@example.invalid','','{}','{}',now(),now()),
      (outsider_id,'authenticated','authenticated','refund-other-'||outsider_id||'@example.invalid','','{}','{}',now(),now());
  insert into shows(id,created_by,owner_user_id,name,start_date,end_date,entry_close_at,is_test)
    values(show_id,owner_id,owner_id,'Refund fixture',current_date,current_date+1,now()+interval '1 day',true);
  insert into exhibitors(id,type,display_name,email,is_local_only,exhibitor_number,owner_user_id,created_for_show_id,is_test)
    values(ex,'adult','Refund exhibitor','refund-fixture@example.invalid',true,999901,owner_id,show_id,true);
  insert into show_sections(id,show_id,kind,letter,display_name) values(section_id,show_id,'open','A','Open A');
  insert into entry_carts(id,user_id,show_id) values(cart,owner_id,show_id);
  insert into entry_cart_items(cart_id,section_id,species,tattoo,breed,variety,sex,class_name,exhibitor_id)
    select cart,section_id,'rabbit', 'RF-'||i,'Dutch','Black','Buck','Senior',ex from generate_series(1,3) i;
  insert into entries(show_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name,status,source_cart_id,source_cart_item_id,cart_entry_kind)
    select show_id,section_id,ex,'rabbit',i.tattoo,'Dutch','Black','Buck','Senior','entered',cart,i.id,'entry'
    from entry_cart_items i where i.cart_id=cart;
  select array_agg(e.id order by e.tattoo) into ids from entries e where e.show_id=show_id;
  insert into show_exhibitor_balances(id,show_id,exhibitor_id,exhibitor_user_id,entry_cart_id,cart_id,currency,source,
    entry_count,entries_subtotal_cents,subtotal_before_discount_cents,calculated_total_cents,paid_online_cents,balance_due_cents,payment_status,section_breakdown)
    values(b,show_id,ex,owner_id,cart,cart,'usd','cart',3,3000,3000,3000,3000,0,'paid',
      jsonb_build_array(jsonb_build_object('section_id',section_id,'entry_count',3,'entries_subtotal_cents',3000)));
  insert into show_payments(id,show_id,exhibitor_id,exhibitor_user_id,cart_id,entry_cart_id,balance_id,currency,
    status,payment_status,provider,payment_type,payment_method,amount_cents,total_cents,gross_charged_cents,online_fee_cents,
    provider_payment_id,stripe_account_id,paid_at)
    values(payment,show_id,ex,owner_id,cart,cart,b,'usd','paid','paid','stripe','checkout','stripe',3000,3000,3200,200,'pi_refund_fixture','acct_fixture',now());
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner_id)::text,true);
  perform pg_temp.check_true(public.can_refund_show_entries(show_id),'owner may refund');
  response:=public.get_entry_refund_options(show_id,ex);
  perform pg_temp.check_true(jsonb_array_length(response->'payments')=1,'payment offered once');
  perform pg_temp.check_true(jsonb_array_length(response#>'{payments,0,entries}')=3,'original cart entries offered');
  perform pg_temp.check_true((response#>>'{payments,0,entries,0,suggested_cents}')::integer=1000,'saved entry fee suggested');
  perform set_config('request.jwt.claim.sub',outsider_id::text,true);
  perform pg_temp.check_true(not public.can_refund_show_entries(show_id),'unrelated user denied');
  insert into role_assignments(user_id,show_id,role) values(outsider_id,show_id,'superintendent');
  perform pg_temp.check_true(not public.can_refund_show_entries(show_id),'superintendent cannot issue refunds');
  update role_assignments set role='admin' where user_id=outsider_id and role='superintendent';
  perform pg_temp.check_true(public.can_refund_show_entries(show_id),'assigned show secretary can refund');
  delete from role_assignments where user_id=outsider_id;
  insert into super_admins(user_id) values(outsider_id);
  perform pg_temp.check_true(public.can_refund_show_entries(show_id),'global super administrator can refund');
  delete from super_admins where user_id=outsider_id;
  perform pg_temp.expect_error(format('select public.get_entry_refund_options(%L,%L)',show_id,ex),'Only show secretaries');
  perform pg_temp.check_true(not has_function_privilege('authenticated','public.prepare_entry_refund(uuid,uuid,uuid,uuid[],integer,integer,text,boolean)','execute'),'client cannot call backend prepare');
  perform pg_temp.check_true(not has_function_privilege('authenticated','public.finish_entry_refund(uuid,text,text,text)','execute'),'client cannot claim provider success');
  perform pg_temp.check_true(not has_table_privilege('authenticated','entry_refunds_private.requests','select'),'refund audit is private');
  perform pg_temp.check_true(not has_function_privilege('authenticated','entry_refunds_private.can_refund(uuid,uuid)','execute'),'client cannot call actor-selecting permission helper');
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  perform pg_temp.expect_error(format('select public.prepare_entry_refund(%L,%L,%L,%L::uuid[],1000,0,%L,false)',request_id,outsider_id,payment,ids[1:1],'Reason'),'Only show secretaries');
  perform pg_temp.expect_error(format('select public.prepare_entry_refund(%L,%L,%L,%L::uuid[],3001,0,%L,false)',request_id,owner_id,payment,ids[1:1],'Reason'),'exceeds');
  perform pg_temp.expect_error(format('select public.prepare_entry_refund(%L,%L,%L,%L::uuid[],1000,201,%L,false)',request_id,owner_id,payment,ids[1:1],'Reason'),'exceeds');
  perform pg_temp.expect_error(format('select public.prepare_entry_refund(%L,%L,%L,%L::uuid[],1000,0,%L,false)',request_id,owner_id,payment,array[gen_random_uuid()],'Reason'),'no longer available');
  response:=public.prepare_entry_refund(request_id,owner_id,payment,ids[1:1],1000,100,'Entry canceled',false);
  perform pg_temp.check_true(response->>'status'='prepared','durable request prepared');
  perform pg_temp.check_true((select count(*) from entries e where e.id=any(ids))=3,'prepare does not remove entries');
  response:=public.prepare_entry_refund(request_id,owner_id,payment,ids[1:1],1000,100,'Entry canceled',false);
  perform pg_temp.check_true(response->>'id'=request_id::text,'same request reuses ID');
  perform pg_temp.expect_error(format('select public.prepare_entry_refund(%L,%L,%L,%L::uuid[],999,100,%L,false)',request_id,owner_id,payment,ids[1:1],'Entry canceled'),'already been used');
  perform pg_temp.expect_error(format('select public.prepare_entry_refund(%L,%L,%L,%L::uuid[],1000,0,%L,false)',next_id,owner_id,payment,ids[1:1],'Reason'),'no longer available');
  perform pg_temp.expect_error(format('delete from entries where id=%L',ids[1]),'refund in progress');
  perform pg_temp.expect_error(format('update entries set tattoo=%L where id=%L','CHANGED',ids[1]),'refund in progress');
  perform pg_temp.expect_error(format('update shows set is_locked=true where id=%L',show_id),'Resolve pending');
  perform public.finish_entry_refund(request_id,'pending','re_fixture');
  perform pg_temp.check_true((select count(*) from entries e where e.id=any(ids))=3,'pending does not remove entries');
  perform public.finish_entry_refund(request_id,'succeeded','re_fixture');
  select * into balance from show_exhibitor_balances where id=b;
  perform pg_temp.check_true(balance.calculated_total_cents=2000 and balance.refunded_cents=1000 and balance.balance_due_cents=0,'principal credited and returned without new debt');
  perform pg_temp.check_true(balance.paid_online_cents=3000,'gross paid amount retained');
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  response:=public.get_entry_refund_options(show_id,ex);
  perform pg_temp.check_true((response#>>'{payments,0,entries,0,suggested_cents}')::integer=1000,'prior refund is not treated as a discount on remaining entries');
  perform pg_temp.check_true((select count(*) from entries e where e.id=any(ids))=2,'only selected entry removed');
  perform public.finish_entry_refund(request_id,'succeeded','re_fixture');
  perform public.apply_show_payment_to_balance(payment);
  select * into balance from show_exhibitor_balances where id=b;
  perform pg_temp.check_true(balance.refunded_cents=1000 and balance.balance_due_cents=0,'duplicate completion/reconciliation do not double refund');
  update show_exhibitor_balances set calculated_total_cents=3000,refunded_cents=0,discount_cents=0,fee_snapshot='{}' where id=b;
  perform pg_temp.check_true((select calculated_total_cents=2000 and refunded_cents=1000 from show_exhibitor_balances where id=b),'refresh preserves refund credit');
  perform public.prepare_entry_refund(failed_id,owner_id,payment,ids[2:2],1000,0,'Canceled request',false);
  perform public.finish_entry_refund(failed_id,'failed',null,'Provider declined');
  perform pg_temp.check_true(exists(select 1 from entries where id=ids[2]),'failed refund keeps entry');
  perform pg_temp.check_true(not exists(select 1 from entry_refunds_private.entries where entry_id=ids[2]),'failed refund releases entry');
  perform public.prepare_entry_refund(next_id,owner_id,payment,ids[2:3],2000,100,'Remaining entries canceled',false);
  perform public.finish_entry_refund(next_id,'succeeded','re_fixture_two');
  perform public.apply_show_payment_to_balance(payment);
  select * into balance from show_exhibitor_balances where id=b;
  perform pg_temp.check_true(balance.calculated_total_cents=0 and balance.refunded_cents=3000 and balance.paid_online_cents=3000 and balance.balance_due_cents=0,'full refund remains balanced after reconciliation');
  perform pg_temp.check_true((select status='refunded' from show_payments where id=payment),'payment marked refunded');
  perform pg_temp.check_true((select sum(online_fee_cents)=200 from entry_refunds_private.requests where status='succeeded' and payment_id=payment),'online fees refunded separately');
  perform pg_temp.check_true((select jsonb_array_length(entry_snapshots)=1 from entry_refunds_private.requests where id=request_id),'deleted entry retained in audit');

  -- A cash receipt without a balance_id, as used at check-in.
  insert into entries(id,show_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name,status)
    values(manual_entry,show_id,section_id,ex,'rabbit','CASH-RF','Dutch','Black','Buck','Senior','entered');
  insert into show_exhibitor_balances(id,show_id,exhibitor_id,currency,source,entry_count,entries_subtotal_cents,
    subtotal_before_discount_cents,calculated_total_cents,paid_manual_cents,balance_due_cents,payment_status)
    values(manual_b,show_id,ex,'usd','entries',1,1000,1000,1000,1000,0,'paid');
  insert into show_payments(id,show_id,exhibitor_id,currency,status,payment_status,payment_method,provider,payment_type,amount_cents,total_cents,paid_at)
    values(manual_payment,show_id,ex,'usd','paid','paid','cash','cash','manual',1000,1000,now());
  perform pg_temp.expect_error(format('select public.prepare_entry_refund(%L,%L,%L,%L::uuid[],1000,0,%L,false)',manual_id,owner_id,manual_payment,array[manual_entry],'Cash returned'),'Confirm the money');
  perform public.prepare_entry_refund(manual_id,owner_id,manual_payment,array[manual_entry],1000,0,'Cash returned',true);
  perform public.finish_entry_refund(manual_id,'succeeded');
  perform pg_temp.check_true((select calculated_total_cents=0 and refunded_cents=1000 and balance_due_cents=0 from show_exhibitor_balances where id=manual_b),'manual refund balanced');
  perform pg_temp.check_true(not exists(select 1 from entries where id=manual_entry),'manual refunded entry removed');
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  response:=public.get_show_entry_refunds(show_id);
  perform pg_temp.check_true(jsonb_array_length(response)=4,'history remains accessible after all entries removed');
end;
$$;
select pass('Entry refunds: authorization, reservations, partial/full/manual accounting, audit and replay safety');
select * from finish();
rollback;
