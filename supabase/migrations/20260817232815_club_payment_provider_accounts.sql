-- Club-owned payment-provider accounts.  A show retains its own payment link
-- for audit/history, while new shows can safely inherit the hosting club's
-- verified provider connection.

create table if not exists public.club_payment_provider_accounts (
  id uuid primary key default extensions.gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  provider text not null check (provider in ('stripe', 'square', 'paypal')),
  stripe_account_id text,
  provider_account_id text,
  provider_location_id text,
  charges_enabled boolean not null default false,
  payouts_enabled boolean not null default false,
  details_submitted boolean not null default false,
  account_status text,
  status text,
  authorization_expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  source_show_payment_account_link_id uuid references public.show_payment_account_links(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (club_id, provider)
);

create table if not exists public.club_payment_provider_migration_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  club_id uuid references public.clubs(id) on delete set null,
  show_id uuid references public.shows(id) on delete set null,
  provider text not null check (provider in ('stripe', 'square', 'paypal')),
  show_payment_account_link_id uuid references public.show_payment_account_links(id) on delete cascade,
  reason text not null,
  details jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'resolved', 'ignored')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (show_payment_account_link_id, reason)
);

alter table public.show_payment_account_links
  add column if not exists club_payment_provider_account_id uuid
    references public.club_payment_provider_accounts(id) on delete set null;

create index if not exists show_payment_account_links_club_provider_account_idx
  on public.show_payment_account_links(club_payment_provider_account_id);
create index if not exists club_payment_provider_accounts_club_provider_idx
  on public.club_payment_provider_accounts(club_id, provider);
create index if not exists club_payment_provider_migration_reviews_pending_idx
  on public.club_payment_provider_migration_reviews(status, club_id, provider)
  where status = 'pending';

alter table public.club_payment_provider_accounts enable row level security;
alter table public.club_payment_provider_migration_reviews enable row level security;

create policy "Club managers read club payment providers"
on public.club_payment_provider_accounts for select to authenticated
using (exists (
  select 1 from public.shows s
  where s.club_id = club_payment_provider_accounts.club_id
    and public.user_can_manage_show_settings(s.id)
));

create policy "Super admins read payment provider migration reviews"
on public.club_payment_provider_migration_reviews for select to authenticated
using (public.is_super_admin());

-- Promote a show-owned link only when no club account exists.  If the club
-- already points to a different merchant/account, do not guess: queue review.
create or replace function public.promote_show_payment_provider_link_to_club(
  p_show_id uuid,
  p_provider text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_show public.shows%rowtype;
  v_link public.show_payment_account_links%rowtype;
  v_club_account public.club_payment_provider_accounts%rowtype;
  v_provider text;
  v_link_identity text;
  v_club_identity text;
  v_promoted integer := 0;
  v_review integer := 0;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage payment providers for this show.' using errcode = '42501';
  end if;
  select * into v_show from public.shows where id = p_show_id;
  if not found or v_show.club_id is null then
    return jsonb_build_object('promoted', 0, 'review_required', 0, 'reason', 'no_hosting_club');
  end if;

  for v_link in
    select * from public.show_payment_account_links
    where show_id = p_show_id
      and (p_provider is null or provider = lower(trim(p_provider)))
  loop
    v_provider := lower(trim(v_link.provider));
    if v_provider not in ('stripe', 'square', 'paypal') then continue; end if;
    v_link_identity := coalesce(nullif(trim(v_link.stripe_account_id), ''), nullif(trim(v_link.provider_account_id), ''));
    if v_link_identity is null then
      insert into public.club_payment_provider_migration_reviews(
        club_id, show_id, provider, show_payment_account_link_id, reason, details
      ) values (
        v_show.club_id, p_show_id, v_provider, v_link.id, 'missing_provider_account_identifier',
        jsonb_build_object('link_status', v_link.status, 'account_status', v_link.account_status)
      ) on conflict (show_payment_account_link_id, reason) do nothing;
      v_review := v_review + 1;
      continue;
    end if;

    select * into v_club_account from public.club_payment_provider_accounts
    where club_id = v_show.club_id and provider = v_provider;
    if not found then
      insert into public.club_payment_provider_accounts(
        club_id, provider, stripe_account_id, provider_account_id, provider_location_id,
        charges_enabled, payouts_enabled, details_submitted, account_status, status,
        authorization_expires_at, metadata, source_show_payment_account_link_id
      ) values (
        v_show.club_id, v_provider, v_link.stripe_account_id, v_link.provider_account_id,
        v_link.provider_location_id, coalesce(v_link.charges_enabled, false),
        coalesce(v_link.payouts_enabled, false), coalesce(v_link.details_submitted, false),
        v_link.account_status, v_link.status, v_link.authorization_expires_at,
        coalesce(v_link.metadata, '{}'::jsonb), v_link.id
      ) returning * into v_club_account;
      v_promoted := v_promoted + 1;
    else
      v_club_identity := coalesce(nullif(trim(v_club_account.stripe_account_id), ''), nullif(trim(v_club_account.provider_account_id), ''));
      if v_club_identity is distinct from v_link_identity then
        insert into public.club_payment_provider_migration_reviews(
          club_id, show_id, provider, show_payment_account_link_id, reason, details
        ) values (
          v_show.club_id, p_show_id, v_provider, v_link.id, 'conflicting_provider_account',
          jsonb_build_object('club_account_id', v_club_account.id, 'existing_identity', v_club_identity, 'show_identity', v_link_identity)
        ) on conflict (show_payment_account_link_id, reason) do nothing;
        v_review := v_review + 1;
        continue;
      end if;
    end if;
    update public.show_payment_account_links
    set club_payment_provider_account_id = v_club_account.id, updated_at = now()
    where id = v_link.id;
  end loop;
  return jsonb_build_object('promoted', v_promoted, 'review_required', v_review);
end;
$$;

-- Attach a new show to saved club accounts.  It copies the link snapshot so
-- existing checkout and webhook code remains audit-safe, and copies encrypted
-- Square credentials from the club account's canonical legacy link.
create or replace function public.ensure_show_club_payment_provider_links(p_show_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_show public.shows%rowtype;
  v_account public.club_payment_provider_accounts%rowtype;
  v_link_id uuid;
  v_attached integer := 0;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage payment providers for this show.' using errcode = '42501';
  end if;
  select * into v_show from public.shows where id = p_show_id;
  if not found or v_show.club_id is null then
    return jsonb_build_object('attached', 0, 'reason', 'no_hosting_club');
  end if;
  perform public.promote_show_payment_provider_link_to_club(p_show_id);
  for v_account in select * from public.club_payment_provider_accounts where club_id = v_show.club_id loop
    if exists (select 1 from public.show_payment_account_links where show_id=p_show_id and provider=v_account.provider) then continue; end if;
    insert into public.show_payment_account_links(
      show_id, provider, stripe_account_id, provider_account_id, provider_location_id,
      charges_enabled, payouts_enabled, details_submitted, account_status, status,
      authorization_expires_at, metadata, club_payment_provider_account_id
    ) values (
      p_show_id, v_account.provider, v_account.stripe_account_id, v_account.provider_account_id,
      v_account.provider_location_id, v_account.charges_enabled, v_account.payouts_enabled,
      v_account.details_submitted, v_account.account_status, v_account.status,
      v_account.authorization_expires_at, v_account.metadata, v_account.id
    ) returning id into v_link_id;
    insert into public.payment_provider_credentials(
      payment_account_link_id, provider, access_token_encrypted, refresh_token_encrypted,
      granted_scopes, token_expires_at, credential_metadata
    ) select v_link_id, c.provider, c.access_token_encrypted, c.refresh_token_encrypted,
      c.granted_scopes, c.token_expires_at, c.credential_metadata
    from public.payment_provider_credentials c
    where c.payment_account_link_id = v_account.source_show_payment_account_link_id
      and c.provider = v_account.provider
    on conflict (payment_account_link_id, provider) do nothing;
    v_attached := v_attached + 1;
  end loop;
  return jsonb_build_object('attached', v_attached);
end;
$$;

revoke all on function public.promote_show_payment_provider_link_to_club(uuid, text) from public, anon;
grant execute on function public.promote_show_payment_provider_link_to_club(uuid, text) to authenticated, service_role;
revoke all on function public.ensure_show_club_payment_provider_links(uuid) from public, anon;
grant execute on function public.ensure_show_club_payment_provider_links(uuid) to authenticated, service_role;

-- Initial migration: promote each legacy link in chronological order.  First
-- account for a club/provider becomes canonical; later conflicting accounts
-- remain linked to their historic show and are queued for manual review.
do $$
declare
  r record;
begin
  for r in
    select distinct l.show_id, l.provider
    from public.show_payment_account_links l
    join public.shows s on s.id = l.show_id
    where s.club_id is not null and l.provider in ('stripe', 'square', 'paypal')
    order by l.show_id, l.provider
  loop
    -- Run as migration owner; the helper's user check is deliberately bypassed
    -- only for this one-time controlled data migration.
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    perform public.promote_show_payment_provider_link_to_club(r.show_id, r.provider);
  end loop;
end;
$$;
