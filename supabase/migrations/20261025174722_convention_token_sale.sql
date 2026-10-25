-- Location is checked once for each checkout. Raw visitor coordinates are never
-- persisted. Only the offer snapshot and verification time reach the ledger.
create schema if not exists convention_sale_private;
revoke all on schema convention_sale_private from public, anon, authenticated;
grant usage on schema convention_sale_private to service_role;

create table convention_sale_private.settings (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true,
  title text not null default 'Convention token bonus',
  venue text not null default 'Reno–Sparks Convention Center',
  address text not null default '4590 S Virginia St, Reno, NV 89502',
  latitude double precision not null default 39.4861 check (latitude between -85 and 85),
  longitude double precision not null default -119.7911 check (longitude between -180 and 180),
  radius_miles double precision not null default 1 check (radius_miles between 0.1 and 25),
  time_zone text not null default 'America/Los_Angeles',
  starts_at timestamptz not null default '2026-10-26 00:00:00 America/Los_Angeles',
  ends_at timestamptz not null default '2026-10-27 00:00:00 America/Los_Angeles',
  single_bonus integer not null default 1 check (single_bonus between 0 and 100),
  four_bonus integer not null default 2 check (four_bonus between 0 and 100),
  unlimited_bonus_months integer not null default 2 check (unlimited_bonus_months between 0 and 24),
  revision integer not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  check (ends_at > starts_at and ends_at <= starts_at + interval '14 days')
);
insert into convention_sale_private.settings(singleton) values (true);

create table convention_sale_private.claims (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  email text not null,
  plan text not null check (plan in ('single_show','four_shows','unlimited')),
  sale_revision integer not null,
  bonus_tokens integer not null,
  bonus_months integer not null,
  price_id text not null,
  quoted_amount_cents bigint not null check (quoted_amount_cents > 0),
  currency text not null,
  livemode boolean not null,
  verified_at timestamptz not null default now(),
  expires_at timestamptz not null,
  stripe_session_id text unique,
  fulfilled_at timestamptz,
  unlimited_expires_at timestamptz
);
create index convention_sale_claim_user_time on convention_sale_private.claims(user_id,verified_at);
alter table convention_sale_private.settings enable row level security;
alter table convention_sale_private.claims enable row level security;
revoke all on all tables in schema convention_sale_private from public,anon,authenticated;
grant select,insert,update on all tables in schema convention_sale_private to service_role;

-- A deliberately small public projection; visitor eligibility is never public.
create function public.convention_sale_settings() returns jsonb
language sql stable security definer set search_path = '' as $$
 select to_jsonb(s) - 'singleton' - 'updated_by' || jsonb_build_object(
   'starts_local',to_char(s.starts_at at time zone s.time_zone,'YYYY-MM-DD"T"HH24:MI'),
   'ends_local',to_char(s.ends_at at time zone s.time_zone,'YYYY-MM-DD"T"HH24:MI'),
   'active',s.enabled and now() >= s.starts_at and now() < s.ends_at,
   'server_now',now())
 from convention_sale_private.settings s where singleton;
$$;
revoke all on function public.convention_sale_settings() from public;
grant execute on function public.convention_sale_settings() to anon,authenticated,service_role;

create function public.convention_sale_admin(p_settings jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_start timestamptz; v_end timestamptz; v_zone text;
begin
 if auth.uid() is null or not public.is_super_admin(auth.uid()) then
   raise exception 'Super Admin access required' using errcode='42501';
 end if;
 if p_settings is not null then
   v_zone := p_settings->>'time_zone';
   if not exists(select 1 from pg_catalog.pg_timezone_names where name=v_zone) then
     raise exception 'Choose a valid IANA time zone';
   end if;
   v_start := (p_settings->>'starts_local')::timestamp at time zone v_zone;
   v_end := (p_settings->>'ends_local')::timestamp at time zone v_zone;
   if (v_start at time zone v_zone) <> (p_settings->>'starts_local')::timestamp
     or (v_end at time zone v_zone) <> (p_settings->>'ends_local')::timestamp then
     raise exception 'That local time does not exist due to daylight saving time';
   end if;
   if length(trim(p_settings->>'title')) not between 1 and 100
     or length(trim(p_settings->>'venue')) not between 1 and 200
     or length(p_settings->>'address') > 300 then raise exception 'Enter a title and venue'; end if;
   update convention_sale_private.settings set
     enabled=(p_settings->>'enabled')::boolean,
     title=trim(p_settings->>'title'),venue=trim(p_settings->>'venue'),address=trim(p_settings->>'address'),
     latitude=(p_settings->>'latitude')::double precision,longitude=(p_settings->>'longitude')::double precision,
     radius_miles=(p_settings->>'radius_miles')::double precision,time_zone=v_zone,
     starts_at=v_start,ends_at=v_end,single_bonus=(p_settings->>'single_bonus')::integer,
     four_bonus=(p_settings->>'four_bonus')::integer,
     unlimited_bonus_months=(p_settings->>'unlimited_bonus_months')::integer,
     revision=revision+1,updated_at=now(),updated_by=auth.uid()
   where singleton and revision=(p_settings->>'revision')::integer;
   if not found then raise exception 'Settings changed. Reload before saving.'; end if;
 end if;
 return public.convention_sale_settings();
end;
$$;
revoke all on function public.convention_sale_admin(jsonb) from public,anon;
grant execute on function public.convention_sale_admin(jsonb) to authenticated;

-- Only the authenticated Edge Function can call this service-role RPC. The
-- browser supplies a measurement, never an eligibility flag or bonus amount.
create function public.convention_sale_claim(
 p_id uuid,p_user_id uuid,p_email text,p_plan text,
 p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_measured_at timestamptz,
 p_price_id text,p_amount_cents bigint,p_currency text,p_livemode boolean
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare s convention_sale_private.settings%rowtype; c convention_sale_private.claims%rowtype;
 d double precision; radius_m double precision;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text,71526));
 select * into c from convention_sale_private.claims where id=p_id;
 if found then
   if c.user_id<>p_user_id or c.plan<>p_plan or c.price_id<>p_price_id or c.livemode<>p_livemode
     or c.quoted_amount_cents<>p_amount_cents or c.currency<>p_currency then
     raise exception 'Checkout request does not match';
   end if;
   if c.expires_at<=now() then raise exception 'Location check expired. Check your location again.'; end if;
   return to_jsonb(c);
 end if;
 select * into s from convention_sale_private.settings where singleton;
 if not s.enabled or now()<s.starts_at or now()>=s.ends_at then
   raise exception 'The convention sale is not open';
 end if;
 if p_plan not in ('single_show','four_shows','unlimited') then raise exception 'Choose a token package'; end if;
 radius_m := s.radius_miles*1609.344;
 if p_latitude is null or p_longitude is null or p_accuracy is null or p_measured_at is null
   or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
   or p_accuracy not between 0 and least(250,radius_m/2)
   or p_measured_at<now()-interval '60 seconds' or p_measured_at>now()+interval '30 seconds' then
   raise exception 'A fresh, accurate location reading is required. Retry or visit the booth for help.';
 end if;
 d := 12742017.6*asin(sqrt(least(1,greatest(0,
   power(sin(radians(p_latitude-s.latitude)/2),2)
   +cos(radians(s.latitude))*cos(radians(p_latitude))*power(sin(radians(p_longitude-s.longitude)/2),2)))));
 if d+p_accuracy>radius_m then
   raise exception 'Your location could not be confirmed inside the sale area. Retry or visit the booth for help.';
 end if;
 if (select count(*) from convention_sale_private.claims where user_id=p_user_id
     and verified_at>now()-interval '1 hour')>=30 then raise exception 'Too many checkout attempts. Try again later.'; end if;
 insert into convention_sale_private.claims(
   id,user_id,email,plan,sale_revision,bonus_tokens,bonus_months,price_id,quoted_amount_cents,currency,livemode,expires_at)
 values(p_id,p_user_id,p_email,p_plan,s.revision,
   case p_plan when 'single_show' then s.single_bonus when 'four_shows' then s.four_bonus else 0 end,
   case when p_plan='unlimited' then s.unlimited_bonus_months else 0 end,
   p_price_id,p_amount_cents,p_currency,p_livemode,least(now()+interval '15 minutes',s.ends_at)) returning * into c;
 return to_jsonb(c);
end;
$$;
revoke all on function public.convention_sale_claim(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz,text,bigint,text,boolean) from public,anon,authenticated;
grant execute on function public.convention_sale_claim(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz,text,bigint,text,boolean) to service_role;

-- Fulfillment, the license balance and the processed-session marker commit in
-- one transaction. Locking the account also protects simultaneous purchases.
create function public.convention_sale_fulfill(
 p_claim_id uuid,p_session_id text,p_price_id text,p_amount_cents bigint,p_currency text,
 p_livemode boolean,p_checkout_created timestamptz
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare c convention_sale_private.claims%rowtype; b public.account_license_balances%rowtype;
 v_tokens integer; v_expiry timestamptz;
begin
 select * into c from convention_sale_private.claims where id=p_claim_id for update;
 if not found then raise exception 'Unknown convention checkout'; end if;
 if p_session_id is null or p_session_id not like 'cs_%'
   or p_price_id is distinct from c.price_id or p_amount_cents is distinct from c.quoted_amount_cents
   or p_currency is distinct from c.currency or p_livemode is distinct from c.livemode
   or p_checkout_created is null or p_checkout_created<c.verified_at-interval '30 seconds'
   or p_checkout_created>=c.expires_at then raise exception 'Convention payment does not match its offer'; end if;
 if c.fulfilled_at is not null then
   if c.stripe_session_id<>p_session_id then raise exception 'Offer already used by another checkout'; end if;
   return to_jsonb(c)||jsonb_build_object('already_processed',true);
 end if;
 insert into public.processed_stripe_sessions(stripe_session_id,secretary_email,matched_user_id,matched_plan)
 values(p_session_id,c.email,c.user_id,c.plan);
 insert into public.account_license_balances(user_id) values(c.user_id) on conflict(user_id) do nothing;
 select * into b from public.account_license_balances where user_id=c.user_id for update;
 v_tokens := case c.plan when 'single_show' then 1+c.bonus_tokens when 'four_shows' then 4+c.bonus_tokens else 0 end;
 v_expiry := b.unlimited_expires_at;
 if c.plan='unlimited' then
   -- Preserve existing lifetime access; renewals extend rather than reset it.
   if not ((b.unlimited_access or b.unlimited_active) and b.unlimited_expires_at is null) then
     v_expiry := greatest(now(),b.unlimited_expires_at)+make_interval(months=>12+c.bonus_months);
   end if;
 end if;
 update public.account_license_balances set
   purchased_show_days=purchased_show_days+v_tokens,
   unlimited_access=unlimited_access or c.plan='unlimited',
   unlimited_active=unlimited_active or c.plan='unlimited',
   unlimited_expires_at=v_expiry,secretary_email=c.email,updated_at=now()
 where user_id=c.user_id;
 update convention_sale_private.claims set stripe_session_id=p_session_id,fulfilled_at=now(),unlimited_expires_at=v_expiry
 where id=c.id returning * into c;
 return to_jsonb(c)||jsonb_build_object('already_processed',false);
end;
$$;
revoke all on function public.convention_sale_fulfill(uuid,text,text,bigint,text,boolean,timestamptz) from public,anon,authenticated;
grant execute on function public.convention_sale_fulfill(uuid,text,text,bigint,text,boolean,timestamptz) to service_role;

-- The buyer can poll only their own result after returning from Stripe.
create function public.convention_sale_purchase(p_claim_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('fulfilled',fulfilled_at is not null,'plan',plan,
   'bonus_tokens',bonus_tokens,'bonus_months',bonus_months,'unlimited_expires_at',unlimited_expires_at)
 from convention_sale_private.claims where id=p_claim_id and user_id=auth.uid();
$$;
revoke all on function public.convention_sale_purchase(uuid) from public,anon;
grant execute on function public.convention_sale_purchase(uuid) to authenticated;
