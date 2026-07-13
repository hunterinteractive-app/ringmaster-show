-- Persist hosted provider order IDs in their dedicated column. The previous
-- hosted-checkout RPC incorrectly used provider_attempt_id for Square orders.

update public.show_payment_sessions
set provider_order_id = coalesce(
      nullif(btrim(metadata ->> 'square_order_id'), ''),
      case
        when metadata ->> 'checkout_type' = 'square_hosted_payment_link'
          then nullif(btrim(provider_attempt_id), '')
        else null
      end
    ),
    updated_at = now()
where provider = 'square'
  and provider_order_id is null
  and coalesce(
    nullif(btrim(metadata ->> 'square_order_id'), ''),
    case
      when metadata ->> 'checkout_type' = 'square_hosted_payment_link'
        then nullif(btrim(provider_attempt_id), '')
      else null
    end
  ) is not null;

create unique index if not exists show_payment_sessions_provider_order_uidx
  on public.show_payment_sessions(provider, provider_order_id)
  where provider_order_id is not null;

drop function public.attach_provider_hosted_checkout(
  uuid,text,text,text,text,jsonb
);

create function public.attach_provider_hosted_checkout(
  p_payment_session_id uuid,
  p_provider text,
  p_provider_session_id text,
  p_provider_order_id text,
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
  if nullif(btrim(coalesce(p_provider_session_id, '')), '') is null then
    raise exception 'Hosted checkout payment-link ID is required';
  end if;
  if nullif(btrim(coalesce(p_provider_order_id, '')), '') is null then
    raise exception 'Hosted checkout order ID is required';
  end if;
  if nullif(btrim(coalesce(p_checkout_url, '')), '') is null then
    raise exception 'Hosted checkout URL is required';
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
     or (v_session.provider_order_id is not null
      and v_session.provider_order_id <> p_provider_order_id) then
    raise exception 'Provider checkout is already attached';
  end if;

  update public.show_payment_sessions
  set provider_session_id = p_provider_session_id,
      provider_order_id = p_provider_order_id,
      checkout_url = p_checkout_url,
      attempt_status = 'pending',
      status = 'pending',
      metadata = coalesce(metadata, '{}'::jsonb)
        || coalesce(p_provider_metadata, '{}'::jsonb)
        || jsonb_build_object('provider_order_id', p_provider_order_id),
      updated_at = now()
  where id = p_payment_session_id;

  if not exists (
    select 1 from public.show_payment_sessions
    where id = p_payment_session_id
      and provider_session_id = p_provider_session_id
      and provider_order_id = p_provider_order_id
      and checkout_url = p_checkout_url
  ) then
    raise exception 'Hosted checkout identifiers were not persisted';
  end if;

  update public.show_payments
  set checkout_session_id = p_provider_session_id,
      checkout_url = p_checkout_url,
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object('provider_order_id', p_provider_order_id),
      updated_at = now()
  where payment_session_id = p_payment_session_id and provider = v_provider;

  update public.entry_carts
  set checkout_session_id = p_provider_session_id,
      updated_at = now()
  where active_payment_session_id = p_payment_session_id;

  return jsonb_build_object(
    'payment_session_id', p_payment_session_id,
    'provider_session_id', p_provider_session_id,
    'provider_order_id', p_provider_order_id,
    'checkout_url', p_checkout_url,
    'attached', true
  );
end;
$$;

revoke execute on function public.attach_provider_hosted_checkout(
  uuid,text,text,text,text,jsonb
) from public, anon, authenticated;

grant execute on function public.attach_provider_hosted_checkout(
  uuid,text,text,text,text,jsonb
) to service_role;
