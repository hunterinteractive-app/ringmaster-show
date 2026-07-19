set lock_timeout = '5s';

create table public.license_purchase_email_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'stripe',
  provider_event_id text not null,
  provider_transaction_id text not null,
  secretary_email text not null,
  normalized_secretary_email text not null,
  matched_user_id uuid null references auth.users(id) on delete set null,
  matched_plan text null,
  purchase_sequence integer not null check (purchase_sequence > 0),
  purchase_completed_at timestamptz not null,
  email_type text not null check (
    email_type in ('welcome', 'returning', 'historical')
  ),
  email_status text not null default 'pending' check (
    email_status in ('pending', 'sent', 'failed', 'not_applicable')
  ),
  email_attempt_count integer not null default 0 check (email_attempt_count >= 0),
  provider_message_id text null,
  email_error text null,
  email_sent_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_event_id),
  unique (provider, provider_transaction_id)
);

comment on table public.license_purchase_email_events is
  'Server-only audit and idempotency ledger for completed license purchases and their welcome/returning email.';

create index license_purchase_email_identity_idx
  on public.license_purchase_email_events
  (normalized_secretary_email, purchase_completed_at);

create index license_purchase_email_user_idx
  on public.license_purchase_email_events
  (matched_user_id, purchase_completed_at)
  where matched_user_id is not null;

alter table public.license_purchase_email_events enable row level security;

revoke all on table public.license_purchase_email_events
  from public, anon, authenticated;
grant select, insert, update on table public.license_purchase_email_events
  to service_role;

-- Existing processed sessions establish returning-customer history without
-- retroactively sending email. Stripe session IDs are durable transactions;
-- older webhook code did not persist the event ID.
insert into public.license_purchase_email_events (
  provider,
  provider_event_id,
  provider_transaction_id,
  secretary_email,
  normalized_secretary_email,
  matched_user_id,
  matched_plan,
  purchase_sequence,
  purchase_completed_at,
  email_type,
  email_status
)
select
  'stripe',
  'legacy-session:' || pss.stripe_session_id,
  pss.stripe_session_id,
  btrim(pss.secretary_email),
  lower(btrim(pss.secretary_email)),
  pss.matched_user_id,
  pss.matched_plan,
  row_number() over (
    partition by lower(btrim(pss.secretary_email))
    order by pss.processed_at, pss.stripe_session_id
  )::integer,
  pss.processed_at,
  'historical',
  'not_applicable'
from public.processed_stripe_sessions pss
where nullif(lower(btrim(coalesce(pss.secretary_email, ''))), '') is not null
on conflict (provider, provider_transaction_id) do nothing;

create or replace function public.claim_license_purchase_email(
  p_provider text,
  p_provider_event_id text,
  p_provider_transaction_id text,
  p_secretary_email text,
  p_matched_user_id uuid,
  p_matched_plan text,
  p_purchase_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_event_id text := btrim(coalesce(p_provider_event_id, ''));
  v_transaction_id text := btrim(coalesce(p_provider_transaction_id, ''));
  v_email text := lower(btrim(coalesce(p_secretary_email, '')));
  v_existing public.license_purchase_email_events%rowtype;
  v_sequence integer;
  v_email_type text;
  v_first_purchase_at timestamptz;
  v_latest_purchase_at timestamptz;
begin
  if v_provider = '' or v_event_id = '' or v_transaction_id = ''
     or v_email = '' or position('@' in v_email) <= 1 then
    raise exception 'Provider, event, transaction, and secretary email are required';
  end if;

  -- Serialize classification for the durable user when available, otherwise
  -- for the normalized secretary email supplied during purchase.
  perform pg_advisory_xact_lock(
    hashtextextended(
      case
        when p_matched_user_id is not null then 'user:' || p_matched_user_id::text
        else 'email:' || v_email
      end,
      0
    )
  );

  select * into v_existing
  from public.license_purchase_email_events e
  where e.provider = v_provider
    and (
      e.provider_event_id = v_event_id
      or e.provider_transaction_id = v_transaction_id
    )
  order by e.created_at
  limit 1;

  if found then
    if v_existing.email_status = 'failed'
       and v_existing.email_type in ('welcome', 'returning') then
      update public.license_purchase_email_events
      set email_status = 'pending',
          email_attempt_count = email_attempt_count + 1,
          email_error = null,
          updated_at = now()
      where id = v_existing.id
      returning * into v_existing;

      return jsonb_build_object(
        'claimed', true,
        'event_id', v_existing.id,
        'purchase_count', v_existing.purchase_sequence,
        'email_type', v_existing.email_type,
        'email_status', v_existing.email_status
      );
    end if;

    return jsonb_build_object(
      'claimed', false,
      'event_id', v_existing.id,
      'purchase_count', v_existing.purchase_sequence,
      'email_type', v_existing.email_type,
      'email_status', v_existing.email_status
    );
  end if;

  select count(*)::integer + 1,
         min(e.purchase_completed_at),
         max(e.purchase_completed_at)
  into v_sequence, v_first_purchase_at, v_latest_purchase_at
  from public.license_purchase_email_events e
  where e.normalized_secretary_email = v_email
     or (
       p_matched_user_id is not null
       and e.matched_user_id = p_matched_user_id
     );

  v_email_type := case when v_sequence = 1 then 'welcome' else 'returning' end;

  insert into public.license_purchase_email_events (
    provider,
    provider_event_id,
    provider_transaction_id,
    secretary_email,
    normalized_secretary_email,
    matched_user_id,
    matched_plan,
    purchase_sequence,
    purchase_completed_at,
    email_type,
    email_status,
    email_attempt_count
  ) values (
    v_provider,
    v_event_id,
    v_transaction_id,
    btrim(p_secretary_email),
    v_email,
    p_matched_user_id,
    nullif(btrim(coalesce(p_matched_plan, '')), ''),
    v_sequence,
    coalesce(p_purchase_completed_at, now()),
    v_email_type,
    'pending',
    1
  )
  returning * into v_existing;

  return jsonb_build_object(
    'claimed', true,
    'event_id', v_existing.id,
    'purchase_count', v_sequence,
    'first_purchase_at', coalesce(
      v_first_purchase_at,
      v_existing.purchase_completed_at
    ),
    'latest_purchase_at', greatest(
      coalesce(v_latest_purchase_at, v_existing.purchase_completed_at),
      v_existing.purchase_completed_at
    ),
    'email_type', v_email_type,
    'email_status', v_existing.email_status
  );
end;
$function$;

comment on function public.claim_license_purchase_email(
  text, text, text, text, uuid, text, timestamptz
) is
  'Atomically classifies a completed license purchase and claims exactly one customer email send.';

revoke execute on function public.claim_license_purchase_email(
  text, text, text, text, uuid, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.claim_license_purchase_email(
  text, text, text, text, uuid, text, timestamptz
) to service_role;
