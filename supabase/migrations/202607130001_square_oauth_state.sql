create table if not exists public.payment_provider_oauth_states (
  id uuid primary key default gen_random_uuid(),
  state_hash text not null unique,
  provider text not null,
  show_id uuid not null references public.shows(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint payment_provider_oauth_states_provider_check
    check (provider in ('square'))
);

create index if not exists payment_provider_oauth_states_lookup_idx
  on public.payment_provider_oauth_states (provider, state_hash, expires_at)
  where consumed_at is null;

alter table public.payment_provider_oauth_states enable row level security;

revoke all on public.payment_provider_oauth_states from anon, authenticated;
grant all on public.payment_provider_oauth_states to service_role;

comment on table public.payment_provider_oauth_states is
  'Short-lived, one-time OAuth CSRF state hashes. Raw state values are never stored.';

create unique index if not exists show_payment_account_links_show_provider_uidx
  on public.show_payment_account_links (show_id, provider);

create unique index if not exists payment_provider_credentials_link_provider_uidx
  on public.payment_provider_credentials (payment_account_link_id, provider);
