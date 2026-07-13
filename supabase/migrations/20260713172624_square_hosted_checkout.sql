-- Provider-neutral hosted-checkout attachment and supersession support.

create unique index if not exists show_payment_sessions_provider_attempt_uidx
  on public.show_payment_sessions(provider, provider_attempt_id)
  where provider_attempt_id is not null;

create or replace function public.attach_provider_hosted_checkout(
  p_payment_session_id uuid,
  p_provider text,
  p_provider_session_id text,
  p_provider_attempt_id text,
  p_checkout_url text,
  p_provider_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_payment_sessions%rowtype;
  v_provider text := lower(btrim(coalesce(p_provider, '')));
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_provider_session_id, '')), '') is null
     or nullif(btrim(coalesce(p_provider_attempt_id, '')), '') is null
     or nullif(btrim(coalesce(p_checkout_url, '')), '') is null then
    raise exception 'Hosted checkout identifiers and URL are required';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = p_payment_session_id
  for update;

  if not found or v_session.provider <> v_provider then
    raise exception 'Payment session not found';
  end if;
  if v_session.attempt_status not in ('created', 'pending') then
    raise exception 'Payment session is not attachable';
  end if;
  if (v_session.provider_session_id is not null
      and v_session.provider_session_id <> p_provider_session_id)
     or (v_session.provider_attempt_id is not null
      and v_session.provider_attempt_id <> p_provider_attempt_id) then
    raise exception 'Provider checkout is already attached';
  end if;

  update public.show_payment_sessions
  set provider_session_id = p_provider_session_id,
      provider_attempt_id = p_provider_attempt_id,
      checkout_url = p_checkout_url,
      attempt_status = 'pending',
      status = 'pending',
      metadata = coalesce(metadata, '{}'::jsonb)
        || coalesce(p_provider_metadata, '{}'::jsonb),
      updated_at = now()
  where id = p_payment_session_id;

  update public.show_payments
  set checkout_session_id = p_provider_session_id,
      checkout_url = p_checkout_url,
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object('provider_attempt_id', p_provider_attempt_id),
      updated_at = now()
  where payment_session_id = p_payment_session_id and provider = v_provider;

  update public.entry_carts
  set checkout_session_id = p_provider_session_id,
      updated_at = now()
  where active_payment_session_id = p_payment_session_id;

  return jsonb_build_object(
    'payment_session_id', p_payment_session_id,
    'provider_session_id', p_provider_session_id,
    'provider_attempt_id', p_provider_attempt_id,
    'attached', true
  );
end;
$$;

create or replace function public.supersede_provider_checkout(
  p_payment_session_id uuid,
  p_provider text,
  p_link_deactivated boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;

  v_result := public.mark_payment_attempt_terminal(
    p_payment_session_id,
    p_provider,
    'superseded',
    'superseded',
    'A newer hosted checkout replaced this payment link.',
    null
  );

  update public.show_payment_sessions
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'superseded_at', now(),
        'provider_link_deactivated', coalesce(p_link_deactivated, false)
      ),
      updated_at = now()
  where id = p_payment_session_id
    and provider = lower(btrim(coalesce(p_provider, '')));
  return v_result;
end;
$$;

-- Hosted checkout and its webhook reconciliation require both payment and
-- order read/write permissions. Existing grants must be re-consented.
update public.show_payment_account_links l
set status = 'reconnect_required',
    account_status = 'hosted_checkout_scopes_required',
    updated_at = now()
from public.payment_provider_credentials c
where l.provider = 'square'
  and c.payment_account_link_id = l.id
  and c.provider = 'square'
  and not coalesce(c.granted_scopes, '{}'::text[]) @> array[
    'MERCHANT_PROFILE_READ',
    'PAYMENTS_READ',
    'PAYMENTS_WRITE',
    'PAYMENTS_WRITE_ADDITIONAL_RECIPIENTS',
    'ORDERS_READ',
    'ORDERS_WRITE'
  ]::text[];

revoke execute on function public.attach_provider_hosted_checkout(
  uuid,text,text,text,text,jsonb
), public.supersede_provider_checkout(uuid,text,boolean)
from public, anon, authenticated;

grant execute on function public.attach_provider_hosted_checkout(
  uuid,text,text,text,text,jsonb
), public.supersede_provider_checkout(uuid,text,boolean)
to service_role;
