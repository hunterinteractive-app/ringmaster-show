-- Provider-neutral primitives needed by tokenized/direct payment providers.

create or replace function public.claim_payment_attempt_client_key(
  p_payment_session_id uuid,
  p_provider text,
  p_client_attempt_key_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_payment_sessions%rowtype;
  v_existing text;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_client_attempt_key_hash, '')), '') is null then
    raise exception 'Client attempt key is required';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = p_payment_session_id
  for update;

  if not found or v_session.provider <> lower(btrim(p_provider)) then
    raise exception 'Payment session not found';
  end if;
  v_existing := nullif(v_session.metadata ->> 'client_attempt_key_hash', '');
  if v_existing is not null and v_existing <> p_client_attempt_key_hash then
    raise exception 'Another payment attempt is already in progress';
  end if;

  update public.show_payment_sessions
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'client_attempt_key_hash', p_client_attempt_key_hash
      ),
      updated_at = now()
  where id = p_payment_session_id and v_existing is null;

  return jsonb_build_object(
    'payment_session_id', v_session.id,
    'attempt_status', v_session.attempt_status,
    'provider_payment_id', v_session.provider_payment_id,
    'already_finalized', v_session.attempt_status = 'finalized'
  );
end;
$$;

create or replace function public.set_provider_payment_state(
  p_payment_session_id uuid,
  p_provider text,
  p_provider_payment_id text,
  p_provider_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_payment_sessions%rowtype;
  v_status text := upper(btrim(coalesce(p_provider_status, '')));
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_provider_payment_id, '')), '') is null then
    raise exception 'Provider payment ID is required';
  end if;
  if v_status not in ('PENDING', 'APPROVED', 'COMPLETED') then
    raise exception 'Invalid provider payment status';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = p_payment_session_id
  for update;
  if not found or v_session.provider <> lower(btrim(p_provider)) then
    raise exception 'Payment session not found';
  end if;
  if v_session.provider_payment_id is not null
     and v_session.provider_payment_id <> p_provider_payment_id then
    raise exception 'Provider payment ID does not match the attempt';
  end if;
  if v_session.attempt_status in ('failed', 'cancelled', 'expired', 'superseded') then
    raise exception 'Payment attempt is terminal';
  end if;

  update public.show_payment_sessions
  set provider_payment_id = p_provider_payment_id,
      provider_attempt_id = coalesce(provider_attempt_id, p_provider_payment_id),
      attempt_status = case when attempt_status = 'finalized' then attempt_status
        else 'processing' end,
      status = case when attempt_status = 'finalized' then status else 'processing' end,
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object('provider_status', v_status),
      updated_at = now()
  where id = p_payment_session_id;

  update public.show_payments
  set provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
      status = case when status = 'paid' then status else 'processing' end,
      payment_status = case when payment_status = 'paid' then payment_status else 'processing' end,
      updated_at = now()
  where payment_session_id = p_payment_session_id
    and provider = lower(btrim(p_provider));

  return jsonb_build_object('payment_session_id', p_payment_session_id,
    'provider_payment_id', p_provider_payment_id, 'provider_status', v_status);
end;
$$;

-- Square application fees require this scope in addition to basic payments.
-- Existing authorizations must be re-consented; never infer that the new scope
-- was granted from an older successful connection.
update public.show_payment_account_links l
set status = 'reconnect_required',
    account_status = 'payment_scope_required',
    updated_at = now()
from public.payment_provider_credentials c
where l.provider = 'square'
  and c.payment_account_link_id = l.id
  and c.provider = 'square'
  and not coalesce(c.granted_scopes, '{}'::text[]) @>
    array['MERCHANT_PROFILE_READ','PAYMENTS_WRITE',
      'PAYMENTS_WRITE_ADDITIONAL_RECIPIENTS']::text[];

create or replace function public.get_show_checkout_options(p_show_id uuid)
returns jsonb
language sql
set search_path = 'public'
as $$
  select jsonb_build_object(
    'show_id', s.id,
    'payment_timing_mode', s.payment_timing_mode,
    'allow_online', s.payment_timing_mode in ('online_only', 'online_or_at_show'),
    'allow_at_show', s.payment_timing_mode in ('pay_at_show_only', 'online_or_at_show'),
    'require_online_payment', s.payment_timing_mode = 'online_only',
    'default_online_provider', ps.default_online_provider,
    'providers', jsonb_build_array(
      jsonb_build_object('provider', 'stripe', 'enabled', coalesce(ps.stripe_enabled, false),
        'ready', coalesce(exists (
          select 1 from public.show_payment_account_links l
          where l.show_id=s.id and l.provider='stripe'
            and coalesce(l.charges_enabled,false) and coalesce(l.account_status,'')='ready'
        ), false)),
      jsonb_build_object('provider', 'square', 'enabled', coalesce(ps.square_enabled, false),
        'ready', coalesce(exists (
          select 1 from public.show_payment_account_links l
          where l.show_id=s.id and l.provider='square'
            and l.provider_account_id is not null and l.provider_location_id is not null
            and coalesce(l.status,'') = 'ready'
        ), false)),
      jsonb_build_object('provider', 'paypal', 'enabled', coalesce(ps.paypal_enabled, false),
        'ready', coalesce(exists (
          select 1 from public.show_payment_account_links l
          where l.show_id=s.id and l.provider='paypal'
            and l.provider_account_id is not null
            and coalesce(l.status,'') in ('ready','connected','active')
        ), false))
    )
  )
  from public.shows s
  left join public.show_payment_settings ps on ps.show_id=s.id
  where s.id=p_show_id;
$$;

revoke execute on function public.claim_payment_attempt_client_key(uuid,text,text),
  public.set_provider_payment_state(uuid,text,text,text)
  from public, anon, authenticated;
grant execute on function public.claim_payment_attempt_client_key(uuid,text,text),
  public.set_provider_payment_state(uuid,text,text,text)
  to service_role;
