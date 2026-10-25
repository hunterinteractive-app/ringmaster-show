-- Keep the location-checked buyer separate from the secretary named in Stripe.
-- Old, already-issued checkout sessions retain their original buyer recipient.
alter table convention_sale_private.claims
  add column secretary_recipient boolean not null default false,
  add column recipient_name text,
  add column recipient_email text,
  add column recipient_user_id uuid references auth.users(id),
  add column recipient_pending boolean not null default false;
create index convention_sale_pending_recipient
  on convention_sale_private.claims(recipient_email,fulfilled_at,id)
  where recipient_pending;

-- Take the original claim lock before checking whether this is a retry. Never
-- turn an old buyer-bound offer into a different kind of Stripe session.
create function public.convention_sale_claim_secretary(
 p_id uuid,p_user_id uuid,p_email text,p_plan text,
 p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_measured_at timestamptz,
 p_price_id text,p_amount_cents bigint,p_currency text,p_livemode boolean
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_existing boolean; v_claim jsonb;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text,71526));
 select exists(select 1 from convention_sale_private.claims where id=p_id) into v_existing;
 v_claim := public.convention_sale_claim(p_id,p_user_id,p_email,p_plan,p_latitude,p_longitude,
   p_accuracy,p_measured_at,p_price_id,p_amount_cents,p_currency,p_livemode);
 if not v_existing then
   update convention_sale_private.claims set secretary_recipient=true where id=p_id;
   v_claim := v_claim || jsonb_build_object('secretary_recipient',true);
 end if;
 return v_claim;
end;
$$;
revoke all on function public.convention_sale_claim_secretary(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz,text,bigint,text,boolean) from public,anon,authenticated;
grant execute on function public.convention_sale_claim_secretary(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz,text,bigint,text,boolean) to service_role;

-- Only trusted fulfillment and the verified recipient's sign-in path can call
-- this helper. The pending flag and row lock make granting the benefit atomic.
create function convention_sale_private.credit_recipient(p_claim_id uuid,p_user_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare c convention_sale_private.claims%rowtype; b public.account_license_balances%rowtype;
 v_tokens integer; v_expiry timestamptz;
begin
 select * into c from convention_sale_private.claims where id=p_claim_id for update;
 if not found or c.fulfilled_at is null or not c.recipient_pending then
   raise exception 'Convention purchase is not awaiting credit';
 end if;
 insert into public.account_license_balances(user_id) values(p_user_id) on conflict(user_id) do nothing;
 select * into b from public.account_license_balances where user_id=p_user_id for update;
 v_tokens := case c.plan when 'single_show' then 1+c.bonus_tokens when 'four_shows' then 4+c.bonus_tokens else 0 end;
 v_expiry := b.unlimited_expires_at;
 if c.plan='unlimited'
   and not ((b.unlimited_access or b.unlimited_active) and b.unlimited_expires_at is null) then
   v_expiry := greatest(now(),b.unlimited_expires_at)+make_interval(months=>12+c.bonus_months);
 end if;
 update public.account_license_balances set
   purchased_show_days=purchased_show_days+v_tokens,
   unlimited_access=unlimited_access or c.plan='unlimited',
   unlimited_active=unlimited_active or c.plan='unlimited',
   unlimited_expires_at=v_expiry,
   secretary_name=coalesce(c.recipient_name,secretary_name),
   secretary_email=c.recipient_email,updated_at=now()
 where user_id=p_user_id;
 update convention_sale_private.claims set recipient_user_id=p_user_id,
   recipient_pending=false,unlimited_expires_at=v_expiry where id=c.id;
 update public.processed_stripe_sessions set matched_user_id=p_user_id
 where stripe_session_id=c.stripe_session_id;
end;
$$;
revoke all on function convention_sale_private.credit_recipient(uuid,uuid) from public,anon,authenticated,service_role;

-- Auth's email index is not exposed to the Data API. This service-only helper
-- performs that lookup privately without exposing an account-directory API.
create function convention_sale_private.fulfill(
 p_claim_id uuid,p_session_id text,p_price_id text,p_amount_cents bigint,p_currency text,
 p_livemode boolean,p_checkout_created timestamptz,p_secretary_name text,p_secretary_email text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare c convention_sale_private.claims%rowtype; v_email text; v_name text;
 v_recipient uuid; v_matches uuid[];
begin
 select * into c from convention_sale_private.claims where id=p_claim_id;
 if not found then raise exception 'Unknown convention checkout'; end if;
 if c.secretary_recipient then
   v_name := nullif(btrim(p_secretary_name),'');
   v_email := lower(btrim(p_secretary_email));
   if v_name is null or length(v_name)>255 or v_name ~ '[[:cntrl:]]'
     or v_email is null or length(v_email)>254
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
     raise exception 'A valid Show Secretary Name and Email are required';
   end if;
 else
   v_email := lower(btrim(c.email));
 end if;
 -- Use this same lock order during sign-in and webhook retries.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email,261026));
 select * into c from convention_sale_private.claims where id=p_claim_id for update;
 if p_session_id is null or p_session_id not like 'cs_%'
   or p_price_id is distinct from c.price_id or p_amount_cents is distinct from c.quoted_amount_cents
   or p_currency is distinct from c.currency or p_livemode is distinct from c.livemode
   or p_checkout_created is null or p_checkout_created<c.verified_at-interval '30 seconds' then
   raise exception 'Convention payment does not match its offer';
 end if;
 if c.fulfilled_at is not null then
   if c.stripe_session_id<>p_session_id then raise exception 'Offer already used by another checkout'; end if;
   if c.secretary_recipient and (v_email is distinct from c.recipient_email or v_name is distinct from c.recipient_name) then
     raise exception 'Convention payment recipient does not match';
   end if;
 else
   if c.secretary_recipient then
     select array_agg(u.id) into v_matches from auth.users u
     where lower(btrim(u.email))=v_email and u.email_confirmed_at is not null
       and u.deleted_at is null and not coalesce(u.is_anonymous,false);
     if coalesce(cardinality(v_matches),0)>1 then raise exception 'Secretary email matches more than one account'; end if;
     v_recipient := v_matches[1];
   else
     v_recipient := c.user_id;
   end if;
   insert into public.processed_stripe_sessions(stripe_session_id,secretary_email,matched_user_id,matched_plan)
   values(p_session_id,v_email,v_recipient,c.plan);
   update convention_sale_private.claims set stripe_session_id=p_session_id,fulfilled_at=now(),
     recipient_name=v_name,recipient_email=v_email,recipient_pending=true where id=c.id;
   if v_recipient is not null then perform convention_sale_private.credit_recipient(c.id,v_recipient); end if;
   select * into c from convention_sale_private.claims where id=c.id;
   return to_jsonb(c)||jsonb_build_object('email',c.recipient_email,'user_id',c.recipient_user_id,
     'secretary_name',c.recipient_name,'already_processed',false);
 end if;
 return to_jsonb(c)||jsonb_build_object('email',coalesce(c.recipient_email,c.email),
   'user_id',case when c.secretary_recipient then c.recipient_user_id else c.user_id end,
   'secretary_name',c.recipient_name,'already_processed',true);
end;
$$;
revoke all on function convention_sale_private.fulfill(uuid,text,text,bigint,text,boolean,timestamptz,text,text) from public,anon,authenticated;
grant execute on function convention_sale_private.fulfill(uuid,text,text,bigint,text,boolean,timestamptz,text,text) to service_role;

create function public.convention_sale_fulfill_secretary(
 p_claim_id uuid,p_session_id text,p_price_id text,p_amount_cents bigint,p_currency text,
 p_livemode boolean,p_checkout_created timestamptz,p_secretary_name text,p_secretary_email text
) returns jsonb language sql security invoker set search_path = '' as $$
 select convention_sale_private.fulfill(p_claim_id,p_session_id,p_price_id,p_amount_cents,p_currency,
   p_livemode,p_checkout_created,p_secretary_name,p_secretary_email);
$$;
revoke all on function public.convention_sale_fulfill_secretary(uuid,text,text,bigint,text,boolean,timestamptz,text,text) from public,anon,authenticated;
grant execute on function public.convention_sale_fulfill_secretary(uuid,text,text,bigint,text,boolean,timestamptz,text,text) to service_role;

create or replace function public.convention_sale_fulfill(
 p_claim_id uuid,p_session_id text,p_price_id text,p_amount_cents bigint,p_currency text,
 p_livemode boolean,p_checkout_created timestamptz
) returns jsonb language sql security invoker set search_path = '' as $$
 select convention_sale_private.fulfill(p_claim_id,p_session_id,p_price_id,p_amount_cents,p_currency,
   p_livemode,p_checkout_created,null,null);
$$;
revoke all on function public.convention_sale_fulfill(uuid,text,text,bigint,text,boolean,timestamptz) from public,anon,authenticated;
grant execute on function public.convention_sale_fulfill(uuid,text,text,bigint,text,boolean,timestamptz) to service_role;

-- Preserve normal pending-license processing behind the authenticated wrapper.
alter function public.claim_pending_licenses(uuid,text) set schema convention_sale_private;
revoke all on function convention_sale_private.claim_pending_licenses(uuid,text) from public,anon,authenticated,service_role;
create function public.claim_pending_licenses(p_user_id uuid,p_email text) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(p_email)); v_count integer; c record;
begin
 if auth.uid() is null or p_user_id is distinct from auth.uid()
   or not exists(select 1 from auth.users u where u.id=auth.uid()
     and lower(btrim(u.email))=v_email and u.email_confirmed_at is not null
     and u.deleted_at is null and not coalesce(u.is_anonymous,false)) then
   raise exception 'Sign in with the verified secretary email to claim purchases' using errcode='42501';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email,261026));
 v_count := convention_sale_private.claim_pending_licenses(p_user_id,v_email);
 for c in select id,stripe_session_id from convention_sale_private.claims
   where recipient_pending and recipient_email=v_email and fulfilled_at is not null
   order by fulfilled_at,id for update
 loop
   perform convention_sale_private.credit_recipient(c.id,p_user_id);
   update public.license_purchase_email_events set matched_user_id=p_user_id
   where provider='stripe' and provider_transaction_id=c.stripe_session_id and matched_user_id is null;
   v_count := v_count+1;
 end loop;
 return v_count;
end;
$$;
revoke all on function public.claim_pending_licenses(uuid,text) from public,anon,service_role;
grant execute on function public.claim_pending_licenses(uuid,text) to authenticated;

create or replace function public.convention_sale_purchase(p_claim_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('fulfilled',c.fulfilled_at is not null,'plan',c.plan,
   'bonus_tokens',c.bonus_tokens,'bonus_months',c.bonus_months,'unlimited_expires_at',c.unlimited_expires_at,
   'recipient_name',c.recipient_name,'recipient_email',coalesce(c.recipient_email,c.email),
   'recipient_pending',c.recipient_pending)
 from convention_sale_private.claims c where c.id=p_claim_id
   and (c.user_id=auth.uid() or c.recipient_user_id=auth.uid());
$$;
revoke all on function public.convention_sale_purchase(uuid) from public,anon;
grant execute on function public.convention_sale_purchase(uuid) to authenticated;
notify pgrst, 'reload schema';
