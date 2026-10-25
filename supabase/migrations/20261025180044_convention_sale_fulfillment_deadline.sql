-- Eligibility and quote expiry are enforced before asking Stripe to create a
-- session. Honor a matching paid session even if the in-flight provider request
-- crosses that deadline. Delivery/settlement time never revokes a paid offer.
create or replace function public.convention_sale_fulfill(
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
   or p_checkout_created is null or p_checkout_created<c.verified_at-interval '30 seconds' then raise exception 'Convention payment does not match its offer'; end if;
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
