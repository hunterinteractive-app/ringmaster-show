-- Run only against a disposable local database. All fixture changes roll back.
begin;
create temp table sale_checks(name text);
create function pg_temp.sale_check(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if;
 insert into sale_checks values(label); end; $$;
create function pg_temp.sale_reject(command text,message_fragment text,label text) returns void language plpgsql as $$
begin
 begin execute command;
 exception when others then
   if position(message_fragment in sqlerrm)>0 then perform pg_temp.sale_check(true,label); return; end if;
   raise;
 end;
 raise exception 'FAIL: % was accepted',label;
end; $$;

insert into auth.users(id,email) values
 ('aaaaaaaa-0000-4000-8000-000000000001','buyer@example.invalid'),
 ('aaaaaaaa-0000-4000-8000-000000000002','other@example.invalid'),
 ('aaaaaaaa-0000-4000-8000-000000000003','lifetime@example.invalid'),
 ('aaaaaaaa-0000-4000-8000-000000000004','admin@example.invalid');
insert into public.super_admins(user_id) values('aaaaaaaa-0000-4000-8000-000000000004');

select pg_temp.sale_check(not has_schema_privilege('authenticated','convention_sale_private','usage'),'visitors cannot read private sale records');
select pg_temp.sale_check(not has_function_privilege('authenticated','public.convention_sale_fulfill(uuid,text,text,bigint,text,boolean,timestamptz)','execute'),'buyers cannot grant themselves tokens');
select pg_temp.sale_check(not has_function_privilege('authenticated','public.convention_sale_claim(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz,text,bigint,text,boolean)','execute'),'buyers cannot bypass Edge authentication');
select pg_temp.sale_check(has_function_privilege('anon','public.convention_sale_settings()','execute'),'offer is publicly readable');
select pg_temp.sale_check((public.convention_sale_settings()->>'starts_at')::timestamptz='2026-10-26T07:00:00Z','Reno midnight is correctly converted to UTC');
select pg_temp.sale_check((public.convention_sale_settings()->>'ends_at')::timestamptz='2026-10-27T07:00:00Z','full day includes the final minute');
select pg_temp.sale_check((public.convention_sale_settings()->>'radius_miles')::numeric=1,'default radius is one mile');
select pg_temp.sale_reject('select public.convention_sale_admin()','Super Admin','admin settings reject anonymous access');
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000001',true);
select pg_temp.sale_reject('select public.convention_sale_admin()','Super Admin','admin settings reject ordinary buyers');
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000004',true);
create temp table original_sale as select public.convention_sale_settings() as data;
select pg_temp.sale_check(public.convention_sale_admin()->>'venue'='Reno–Sparks Convention Center','super admin can read settings');
select public.convention_sale_admin((select data from original_sale)||'{"starts_local":"2027-10-26T00:00","ends_local":"2027-10-27T00:00","radius_miles":2}'::jsonb);
select pg_temp.sale_check((public.convention_sale_settings()->>'radius_miles')::numeric=2,'radius changes persist');
select pg_temp.sale_check((public.convention_sale_settings()->>'starts_at')::timestamptz='2027-10-26T07:00Z','sale can be reused next year');
select pg_temp.sale_reject('select public.convention_sale_admin((select data from original_sale))','Settings changed','stale admin edits cannot overwrite newer settings');
select pg_temp.sale_reject($c$select public.convention_sale_admin(public.convention_sale_settings()||'{"time_zone":"Invalid/Zone"}'::jsonb)$c$,'valid IANA','invalid time zone rejected');
select public.convention_sale_admin(public.convention_sale_settings()||'{"starts_local":"2027-11-07T00:00","ends_local":"2027-11-08T00:00"}'::jsonb);
select pg_temp.sale_check((select ends_at-starts_at=interval '25 hours' from convention_sale_private.settings),'full day follows daylight saving fall-back');
select public.convention_sale_admin(public.convention_sale_settings()||'{"starts_local":"2027-03-14T00:00","ends_local":"2027-03-15T00:00"}'::jsonb);
select pg_temp.sale_check((select ends_at-starts_at=interval '23 hours' from convention_sale_private.settings),'full day follows daylight saving spring-forward');
select public.convention_sale_admin((select data from original_sale)||jsonb_build_object('revision',public.convention_sale_settings()->'revision'));
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000001',true);

-- Open a synthetic sale around the local test clock.
update convention_sale_private.settings set starts_at=now()-interval '1 hour',ends_at=now()+interval '1 hour';
create function pg_temp.sale_claim(claim_id uuid,plan text default 'single_show',lat double precision default 39.4861,
  lon double precision default -119.7911,accuracy double precision default 10,measured timestamptz default now(),
  buyer uuid default 'aaaaaaaa-0000-4000-8000-000000000001') returns jsonb language sql as $$
 select public.convention_sale_claim(claim_id,buyer,'buyer@example.invalid',plan,lat,lon,accuracy,measured,'price_test',5000,'usd',false);
$$;
create function pg_temp.sale_fulfill(claim_id uuid,session_id text,amount bigint default 5000,created timestamptz default now()) returns jsonb language sql as $$
 select public.convention_sale_fulfill(claim_id,session_id,'price_test',amount,'usd',false,created);
$$;

select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001','single_show',40,-119.7911)$c$,'inside the sale area','out-of-area check rejected');
select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001','single_show',39.4861,-119.7911,251)$c$,'fresh, accurate','inaccurate location rejected');
select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001','single_show',39.4861,-119.7911,10,now()-interval '61 seconds')$c$,'fresh, accurate','stale measurement rejected');
select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001','single_show',39.4861,-119.7911,10,now()+interval '31 seconds')$c$,'fresh, accurate','future measurement rejected');
select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001','single_show','NaN'::float8,-119.7911)$c$,'fresh, accurate','non-finite location rejected');
update convention_sale_private.settings set enabled=false;
select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001')$c$,'not open','paused sale rejects checkout');
update convention_sale_private.settings set enabled=true,ends_at=now();
select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001')$c$,'not open','closing time is exclusive');
update convention_sale_private.settings set ends_at=now()+interval '1 hour';

select pg_temp.sale_check((pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001')->>'bonus_tokens')::integer=1,'single-token bonus snapshotted');
select pg_temp.sale_check((pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001')->>'bonus_tokens')::integer=1,'checkout request retry returns the same offer');
select pg_temp.sale_reject($c$select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000001','four_shows')$c$,'does not match','cannot change a quoted package');
select pg_temp.sale_reject($c$select pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000001','cs_wrong',1)$c$,'does not match','underpayment cannot credit tokens');
select pg_temp.sale_check(not exists(select 1 from public.processed_stripe_sessions where stripe_session_id='cs_wrong'),'rejected payment leaves no processed marker');
select pg_temp.sale_reject($c$select pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000001','cs_wrong',5000,now()+interval '16 minutes')$c$,'does not match','expired offer cannot create checkout');
select pg_temp.sale_check((pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000001','cs_sale_one')->>'already_processed')::boolean=false,'paid purchase fulfilled');
select pg_temp.sale_check((select purchased_show_days=2 from public.account_license_balances where user_id='aaaaaaaa-0000-4000-8000-000000000001'),'buy one get one awards two');
select pg_temp.sale_check((pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000001','cs_sale_one')->>'already_processed')::boolean,'duplicate webhook is idempotent');
select pg_temp.sale_check((select purchased_show_days=2 from public.account_license_balances where user_id='aaaaaaaa-0000-4000-8000-000000000001'),'duplicate payment event does not add tokens');
select pg_temp.sale_reject($c$select pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000001','cs_sale_other')$c$,'another checkout','one offer cannot fulfill two sessions');
select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000002','four_shows');
update convention_sale_private.settings set four_bonus=99;
select pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000002','cs_sale_four');
select pg_temp.sale_check((select purchased_show_days=8 from public.account_license_balances where user_id='aaaaaaaa-0000-4000-8000-000000000001'),'every qualifying purchase earns its original bonus even after settings change');
select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000003','unlimited');
select pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000003','cs_sale_unlimited');
select pg_temp.sale_check((select unlimited_expires_at=now()+interval '14 months' from public.account_license_balances where user_id='aaaaaaaa-0000-4000-8000-000000000001'),'unlimited purchase grants fourteen calendar months');
select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000004','unlimited');
select pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000004','cs_sale_renew');
select pg_temp.sale_check((select unlimited_expires_at=now()+interval '28 months' from public.account_license_balances where user_id='aaaaaaaa-0000-4000-8000-000000000001'),'renewal preserves remaining time and adds fourteen months');
insert into public.account_license_balances(user_id,unlimited_access,unlimited_active) values('aaaaaaaa-0000-4000-8000-000000000003',true,true);
select pg_temp.sale_claim('bbbbbbbb-0000-4000-8000-000000000005','unlimited',39.4861,-119.7911,10,now(),'aaaaaaaa-0000-4000-8000-000000000003');
select pg_temp.sale_fulfill('bbbbbbbb-0000-4000-8000-000000000005','cs_sale_lifetime');
select pg_temp.sale_check((select unlimited_expires_at is null from public.account_license_balances where user_id='aaaaaaaa-0000-4000-8000-000000000003'),'existing lifetime access is preserved');
select pg_temp.sale_check(public.convention_sale_purchase('bbbbbbbb-0000-4000-8000-000000000001')->>'fulfilled'='true','buyer can read their receipt');
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000002',true);
select pg_temp.sale_check(public.convention_sale_purchase('bbbbbbbb-0000-4000-8000-000000000001') is null,'another account cannot read the receipt');
select pg_temp.sale_check(not exists(select 1 from information_schema.columns where table_schema='convention_sale_private' and table_name='claims' and column_name in ('latitude','longitude','accuracy')),'precise visitor location is not retained');
select count(*)||' convention sale database checks passed' as result from sale_checks;
rollback;
