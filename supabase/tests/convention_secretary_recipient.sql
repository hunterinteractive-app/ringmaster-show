-- Synthetic fixtures only. Use tool/convention_sale/test_database.py.
begin;
create temp table recipient_checks(label text);
create function pg_temp.rec_check(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if;
 insert into recipient_checks values(label); end; $$;
create function pg_temp.rec_reject(command text,fragment text,label text) returns void language plpgsql as $$
begin
 begin execute command;
 exception when others then
   if position(fragment in sqlerrm)>0 then perform pg_temp.rec_check(true,label);return;end if;raise;
 end;
 raise exception 'FAIL: % was accepted',label;
end; $$;
insert into auth.users(id,email) values
 ('dddddddd-0000-4000-8000-000000000001','payer@example.invalid'),
 ('dddddddd-0000-4000-8000-000000000002','club@example.invalid'),
 ('dddddddd-0000-4000-8000-000000000005','lifetime@example.invalid'),
 ('dddddddd-0000-4000-8000-000000000006','other@example.invalid'),
 ('dddddddd-0000-4000-8000-000000000007','unverified@example.invalid');
update auth.users set email_confirmed_at=null where id='dddddddd-0000-4000-8000-000000000007';
insert into public.account_license_balances(user_id,purchased_show_days,consumed_show_days) values
 ('dddddddd-0000-4000-8000-000000000001',7,2),('dddddddd-0000-4000-8000-000000000002',10,4);
insert into public.account_license_balances(user_id,unlimited_access,unlimited_active) values
 ('dddddddd-0000-4000-8000-000000000005',true,true);
update convention_sale_private.settings set enabled=true,starts_at=now()-interval '1 hour',ends_at=now()+interval '1 hour';
create function pg_temp.rec_claim(claim_id uuid,plan text default 'single_show') returns jsonb language sql as $$
 select public.convention_sale_claim_secretary(claim_id,'dddddddd-0000-4000-8000-000000000001',
 'payer@example.invalid',plan,39.4861,-119.7911,10,now(),'price_test',5000,'usd',false);
$$;
create function pg_temp.rec_pay(claim_id uuid,session_id text,email text default 'club@example.invalid',name text default 'Club Secretary')
returns jsonb language sql as $$
 select public.convention_sale_fulfill_secretary(claim_id,session_id,'price_test',5000,'usd',false,now(),name,email);
$$;

select pg_temp.rec_check(not has_function_privilege('authenticated','public.convention_sale_claim_secretary(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz,text,bigint,text,boolean)','execute'),'browser cannot create a secretary offer');
select pg_temp.rec_check(not has_function_privilege('authenticated','public.convention_sale_fulfill_secretary(uuid,text,text,bigint,text,boolean,timestamptz,text,text)','execute'),'browser cannot fulfill a secretary purchase');
select pg_temp.rec_check(not has_function_privilege('service_role','convention_sale_private.credit_recipient(uuid,uuid)','execute'),'raw credit helper is inaccessible even through the service API');
select pg_temp.rec_check(not has_function_privilege('authenticated','convention_sale_private.claim_pending_licenses(uuid,text)','execute'),'legacy pending-claim helper cannot bypass recipient authentication');

select pg_temp.rec_check((pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000001')->>'secretary_recipient')::boolean,'new offers require secretary questions');
select pg_temp.rec_check((pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000001')->>'secretary_recipient')::boolean,'retry preserves secretary mode');
select pg_temp.rec_reject($c$select public.convention_sale_fulfill('eeeeeeee-0000-4000-8000-000000000001','cs_missing','price_test',5000,'usd',false,now())$c$,'Show Secretary','legacy fulfillment cannot bypass required secretary details');
select pg_temp.rec_reject($c$select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000001','cs_invalid','bad-email')$c$,'Show Secretary','invalid secretary email does not fall back to payer');
select pg_temp.rec_check((pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000001','cs_rec_single',' Club@Example.Invalid ')->>'user_id')::uuid='dddddddd-0000-4000-8000-000000000002','secretary email selects a different account from payer');
select pg_temp.rec_check((select purchased_show_days=12 and consumed_show_days=4 and secretary_name='Club Secretary' and secretary_email='club@example.invalid' from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000002'),'single package and bonus add two tokens to secretary');
select pg_temp.rec_check((select purchased_show_days=7 and consumed_show_days=2 from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000001'),'payer balance is unchanged');
select pg_temp.rec_check((pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000001','cs_rec_single')->>'already_processed')::boolean,'duplicate webhook is idempotent');
select pg_temp.rec_reject($c$select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000001','cs_rec_single','other@example.invalid')$c$,'recipient does not match','paid recipient cannot be redirected on retry');
select set_config('request.jwt.claim.sub','dddddddd-0000-4000-8000-000000000001',true);
select pg_temp.rec_check(public.convention_sale_purchase('eeeeeeee-0000-4000-8000-000000000001')->>'recipient_email'='club@example.invalid','payer confirmation identifies actual recipient');
select set_config('request.jwt.claim.sub','dddddddd-0000-4000-8000-000000000002',true);
select pg_temp.rec_check((public.convention_sale_purchase('eeeeeeee-0000-4000-8000-000000000001')->>'fulfilled')::boolean,'recipient can read their own receipt');
select set_config('request.jwt.claim.sub','dddddddd-0000-4000-8000-000000000006',true);
select pg_temp.rec_check(public.convention_sale_purchase('eeeeeeee-0000-4000-8000-000000000001') is null,'unrelated account cannot read purchase');
select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000002','four_shows');
select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000002','cs_rec_four');
select pg_temp.rec_check((select purchased_show_days=18 and consumed_show_days=4 from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000002'),'four package adds six tokens to existing secretary balance');
update public.account_license_balances set unlimited_access=true,unlimited_active=true,unlimited_expires_at=now()+interval '1 month' where user_id='dddddddd-0000-4000-8000-000000000002';
select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000003','unlimited');
select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000003','cs_rec_unlimited');
select pg_temp.rec_check((select unlimited_expires_at=now()+interval '15 months' and purchased_show_days=18 from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000002'),'unlimited extends recipient expiry by fourteen months and preserves tokens');
select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000004','unlimited');
select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000004','cs_rec_renew');
select pg_temp.rec_check((select unlimited_expires_at=now()+interval '29 months' from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000002'),'repeat unlimited purchases add every bonus to recipient');
select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000005','unlimited');
select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000005','cs_rec_lifetime','lifetime@example.invalid');
select pg_temp.rec_check((select unlimited_expires_at is null and unlimited_access from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000005'),'recipient lifetime access stays lifetime');

select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000011');
select pg_temp.rec_check((pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000011','cs_rec_pending_one','future@example.invalid')->>'recipient_pending')::boolean,'unregistered secretary receives a pending paid reservation');
select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000012','four_shows');
select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000012','cs_rec_pending_four','future@example.invalid');
select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000013','unlimited');
select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000013','cs_rec_pending_unlimited1','future@example.invalid');
select pg_temp.rec_claim('eeeeeeee-0000-4000-8000-000000000014','unlimited');
select pg_temp.rec_pay('eeeeeeee-0000-4000-8000-000000000014','cs_rec_pending_unlimited2','future@example.invalid');
select pg_temp.rec_check((select count(*)=4 from convention_sale_private.claims where recipient_pending and recipient_email='future@example.invalid'),'every pending purchase retains its original bonus');
select pg_temp.rec_check((select purchased_show_days=7 from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000001'),'pending gifts never credit payer');
select pg_temp.rec_reject($c$select public.claim_pending_licenses('dddddddd-0000-4000-8000-000000000006','future@example.invalid')$c$,'verified secretary email','another user cannot steal a reservation by supplying its email');
insert into auth.users(id,email) values('dddddddd-0000-4000-8000-000000000003','future@example.invalid');
insert into public.account_license_balances(user_id,purchased_show_days,consumed_show_days,unlimited_access,unlimited_active,unlimited_expires_at)
 values('dddddddd-0000-4000-8000-000000000003',3,1,true,true,now()+interval '2 months');
insert into public.pending_licenses(email,purchased_show_days) values('future@example.invalid',5);
select set_config('request.jwt.claim.sub','dddddddd-0000-4000-8000-000000000007',true);
select pg_temp.rec_reject($c$select public.claim_pending_licenses('dddddddd-0000-4000-8000-000000000007','unverified@example.invalid')$c$,'verified secretary email','unverified email cannot claim purchases');
select set_config('request.jwt.claim.sub','dddddddd-0000-4000-8000-000000000003',true);
select pg_temp.rec_check(public.claim_pending_licenses('dddddddd-0000-4000-8000-000000000003','future@example.invalid')=5,'verified sign-in applies four convention reservations and one normal purchase');
select pg_temp.rec_check((select purchased_show_days=16 and consumed_show_days=1 and unlimited_expires_at=now()+interval '30 months' from public.account_license_balances where user_id='dddddddd-0000-4000-8000-000000000003'),'pending token bonuses and both unlimited bonuses add to existing recipient balances');
select pg_temp.rec_check(public.claim_pending_licenses('dddddddd-0000-4000-8000-000000000003','future@example.invalid')=0,'repeated sign-in does not credit pending purchases twice');
select pg_temp.rec_check((select count(*)=4 from public.processed_stripe_sessions where secretary_email='future@example.invalid' and matched_user_id='dddddddd-0000-4000-8000-000000000003'),'pending purchases update the ledger to actual recipient');
select pg_temp.rec_check(not exists(select 1 from convention_sale_private.claims where recipient_pending),'all verified reservations are cleared');
select count(*)||' secretary recipient checks passed' from recipient_checks;
rollback;
