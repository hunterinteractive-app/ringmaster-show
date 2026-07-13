-- Provider-neutral payment attempts, replay-safe events, and exactly-once cart
-- finalization. All changes preserve existing Stripe columns and rows.

create extension if not exists pgcrypto with schema extensions;

comment on column public.shows.platform_fee_percent is
  'Authoritative show-specific platform fee in percentage points (2.00 = 2%). Backend environment configuration is used only when this value is null; clients are never authoritative.';

alter table public.show_payment_sessions
  alter column show_payment_id drop not null,
  add column if not exists idempotency_key text,
  add column if not exists quote_hash text,
  add column if not exists quote_version integer not null default 1,
  add column if not exists attempt_status text,
  add column if not exists provider_attempt_id text,
  add column if not exists expected_amount_cents integer,
  add column if not exists expected_currency text,
  add column if not exists online_fee_cents integer not null default 0,
  add column if not exists finalized_at timestamptz,
  add column if not exists failure_code text,
  add column if not exists failure_message text,
  add column if not exists quote_snapshot jsonb;

update public.show_payment_sessions
set
  attempt_status = coalesce(attempt_status, status, 'created'),
  expected_amount_cents = coalesce(expected_amount_cents, amount_cents),
  expected_currency = lower(coalesce(expected_currency, currency))
where attempt_status is null
   or expected_amount_cents is null
   or expected_currency is null;

alter table public.show_payment_sessions
  alter column attempt_status set default 'created',
  alter column attempt_status set not null,
  alter column expected_amount_cents set not null,
  alter column expected_currency set not null;

alter table public.show_payments
  add column if not exists payment_session_id uuid,
  add column if not exists provider_payment_id text,
  add column if not exists provider_refund_id text,
  add column if not exists gross_charged_cents integer not null default 0,
  add column if not exists online_fee_cents integer not null default 0,
  add column if not exists refunded_cents integer not null default 0,
  add column if not exists application_fee_refunded_cents integer not null default 0;

-- provider, currency, platform_fee_cents, paid_at, and refunded_at already
-- exist. They remain the authoritative provider-neutral columns going forward.

alter table public.show_payment_events
  add column if not exists processing_status text not null default 'received',
  add column if not exists processing_error text,
  add column if not exists received_at timestamptz not null default now(),
  add column if not exists processed_at timestamptz,
  add column if not exists payment_session_id uuid,
  add column if not exists provider_payment_id text;

alter table public.show_payment_line_items
  alter column show_payment_id drop not null,
  add column if not exists payment_session_id uuid,
  add column if not exists cart_id uuid,
  add column if not exists exhibitor_id uuid,
  add column if not exists balance_id uuid,
  add column if not exists line_type text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.entry_carts
  add column if not exists active_payment_session_id uuid,
  add column if not exists completed_payment_session_id uuid,
  add column if not exists provider_payment_id text,
  add column if not exists payment_finalized_at timestamptz,
  add column if not exists payment_attempt_started_at timestamptz;

-- These provenance columns provide a database uniqueness boundary for entry
-- creation under concurrent webhook delivery and repeated at-show submission.
alter table public.entries
  add column if not exists source_cart_id uuid,
  add column if not exists source_cart_item_id uuid,
  add column if not exists payment_session_id uuid,
  add column if not exists cart_entry_kind text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.show_payments'::regclass
      and conname = 'show_payments_payment_session_id_fkey'
  ) then
    alter table public.show_payments
      add constraint show_payments_payment_session_id_fkey
      foreign key (payment_session_id)
      references public.show_payment_sessions(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.show_payment_events'::regclass
      and conname = 'show_payment_events_payment_session_id_fkey'
  ) then
    alter table public.show_payment_events
      add constraint show_payment_events_payment_session_id_fkey
      foreign key (payment_session_id)
      references public.show_payment_sessions(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.show_payment_line_items'::regclass
      and conname = 'show_payment_line_items_payment_session_id_fkey'
  ) then
    alter table public.show_payment_line_items
      add constraint show_payment_line_items_payment_session_id_fkey
      foreign key (payment_session_id)
      references public.show_payment_sessions(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.show_payment_line_items'::regclass
      and conname = 'show_payment_line_items_cart_id_fkey'
  ) then
    alter table public.show_payment_line_items
      add constraint show_payment_line_items_cart_id_fkey
      foreign key (cart_id)
      references public.entry_carts(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.show_payment_line_items'::regclass
      and conname = 'show_payment_line_items_exhibitor_id_fkey'
  ) then
    alter table public.show_payment_line_items
      add constraint show_payment_line_items_exhibitor_id_fkey
      foreign key (exhibitor_id)
      references public.exhibitors(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.show_payment_line_items'::regclass
      and conname = 'show_payment_line_items_balance_id_fkey'
  ) then
    alter table public.show_payment_line_items
      add constraint show_payment_line_items_balance_id_fkey
      foreign key (balance_id)
      references public.show_exhibitor_balances(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.entry_carts'::regclass
      and conname = 'entry_carts_active_payment_session_id_fkey'
  ) then
    alter table public.entry_carts
      add constraint entry_carts_active_payment_session_id_fkey
      foreign key (active_payment_session_id)
      references public.show_payment_sessions(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.entry_carts'::regclass
      and conname = 'entry_carts_completed_payment_session_id_fkey'
  ) then
    alter table public.entry_carts
      add constraint entry_carts_completed_payment_session_id_fkey
      foreign key (completed_payment_session_id)
      references public.show_payment_sessions(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.entries'::regclass
      and conname = 'entries_source_cart_id_fkey'
  ) then
    alter table public.entries
      add constraint entries_source_cart_id_fkey
      foreign key (source_cart_id)
      references public.entry_carts(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.entries'::regclass
      and conname = 'entries_source_cart_item_id_fkey'
  ) then
    alter table public.entries
      add constraint entries_source_cart_item_id_fkey
      foreign key (source_cart_item_id)
      references public.entry_cart_items(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.entries'::regclass
      and conname = 'entries_payment_session_id_fkey'
  ) then
    alter table public.entries
      add constraint entries_payment_session_id_fkey
      foreign key (payment_session_id)
      references public.show_payment_sessions(id) on delete set null;
  end if;
end
$$;

alter table public.show_payment_sessions
  add constraint show_payment_sessions_attempt_status_chk
  check (attempt_status in (
    'created', 'pending', 'processing', 'finalized', 'failed', 'cancelled',
    'expired', 'superseded'
  )) not valid,
  add constraint show_payment_sessions_expected_amount_chk
  check (expected_amount_cents >= 0) not valid,
  add constraint show_payment_sessions_expected_currency_chk
  check (char_length(expected_currency) = 3) not valid;

alter table public.show_payment_events
  add constraint show_payment_events_processing_status_chk
  check (processing_status in (
    'received', 'processing', 'processed', 'ignored', 'failed'
  )) not valid;

alter table public.show_payment_line_items
  add constraint show_payment_line_items_line_type_chk
  check (line_type is null or line_type in (
    'entry_fee', 'fur_fee', 'per_show_fee', 'discount', 'online_fee',
    'platform_fee', 'adjustment'
  )) not valid;

alter table public.entries
  add constraint entries_cart_entry_kind_chk
  check (cart_entry_kind is null or cart_entry_kind in ('entry', 'fur'))
  not valid;

create unique index if not exists show_payment_sessions_provider_idempotency_uidx
  on public.show_payment_sessions(provider, idempotency_key)
  where idempotency_key is not null;
create index if not exists show_payment_sessions_cart_attempt_idx
  on public.show_payment_sessions(cart_id, provider, attempt_status);
create index if not exists show_payments_payment_session_id_idx
  on public.show_payments(payment_session_id);
create index if not exists show_payments_provider_payment_id_idx
  on public.show_payments(provider, provider_payment_id)
  where provider_payment_id is not null;
create index if not exists show_payment_events_payment_session_id_idx
  on public.show_payment_events(payment_session_id);
create index if not exists show_payment_events_provider_payment_id_idx
  on public.show_payment_events(provider, provider_payment_id)
  where provider_payment_id is not null;
create index if not exists show_payment_line_items_payment_session_id_idx
  on public.show_payment_line_items(payment_session_id);
create index if not exists show_payment_line_items_cart_id_idx
  on public.show_payment_line_items(cart_id);
create index if not exists show_payment_line_items_exhibitor_id_idx
  on public.show_payment_line_items(exhibitor_id);
create index if not exists show_payment_line_items_balance_id_idx
  on public.show_payment_line_items(balance_id);
create index if not exists entry_carts_active_payment_session_id_idx
  on public.entry_carts(active_payment_session_id);
create index if not exists entry_carts_completed_payment_session_id_idx
  on public.entry_carts(completed_payment_session_id);
create unique index if not exists entries_cart_item_kind_uidx
  on public.entries(source_cart_id, source_cart_item_id, cart_entry_kind)
  where source_cart_id is not null
    and source_cart_item_id is not null
    and cart_entry_kind is not null;

-- RLS remains enabled. Payment attempts/events are written only through
-- service-role RPCs; existing user/manager SELECT policies are preserved.
alter table public.show_payment_sessions enable row level security;
alter table public.show_payments enable row level security;
alter table public.show_payment_events enable row level security;
alter table public.show_payment_line_items enable row level security;

-- Preserve already-issued Stripe Checkout Sessions. Only pending rows with a
-- concrete session ID are backfilled; paid historical rows remain untouched.
with legacy_attempts as (
  select
    min(sp.show_id::text)::uuid as show_id,
    sp.cart_id,
    min(c.user_id::text)::uuid as user_id,
    max(sh.name) as show_name,
    sp.provider,
    coalesce(sp.stripe_checkout_session_id, sp.checkout_session_id)
      as provider_session_id,
    lower(min(sp.currency)) as currency,
    coalesce(
      max((sp.metadata ->> 'cart_total_cents')::integer),
      round(max(c.payment_amount_total) * 100)::integer,
      sum(sp.amount_cents)
    )::integer as expected_amount_cents,
    sum(sp.amount_cents)::integer as show_balance_total_cents,
    sum(sp.platform_fee_cents)::integer as platform_fee_cents,
    coalesce(max((sp.metadata ->> 'online_payment_fee_cents')::integer), 0)
      as online_fee_cents,
    max(sh.online_payment_fee_mode) as online_payment_fee_mode,
    max(sh.online_payment_fee_label) as online_payment_fee_label,
    max(sh.online_payment_fee_description) as online_payment_fee_description,
    max(sp.checkout_url) as checkout_url,
    min(sp.created_at) as created_at,
    jsonb_agg(jsonb_build_object(
      'show_payment_id', sp.id,
      'balance_id', sp.balance_id,
      'exhibitor_id', sp.exhibitor_id,
      'amount_cents', sp.amount_cents
    ) order by sp.id) as balances
  from public.show_payments sp
  left join public.entry_carts c on c.id = sp.cart_id
  left join public.shows sh on sh.id = sp.show_id
  where sp.provider = 'stripe'
    and sp.status in ('pending', 'processing', 'requires_action')
    and sp.cart_id is not null
    and coalesce(sp.stripe_checkout_session_id, sp.checkout_session_id)
      is not null
  group by
    sp.cart_id,
    sp.provider,
    coalesce(sp.stripe_checkout_session_id, sp.checkout_session_id)
), inserted as (
  insert into public.show_payment_sessions (
    show_id, cart_id, provider, stripe_checkout_session_id,
    provider_session_id, checkout_url, expires_at, status, currency,
    amount_cents, platform_fee_cents, online_fee_cents, metadata,
    idempotency_key, quote_hash, quote_version, attempt_status,
    provider_attempt_id, expected_amount_cents, expected_currency,
    quote_snapshot, created_at, updated_at
  )
  select
    la.show_id, la.cart_id, 'stripe', la.provider_session_id,
    la.provider_session_id, la.checkout_url,
    la.created_at + interval '24 hours', 'pending', la.currency,
    la.expected_amount_cents, la.platform_fee_cents, la.online_fee_cents,
    jsonb_build_object('legacy_backfill', true),
    'legacy:' || la.provider_session_id,
    'legacy:' || la.provider_session_id,
    1, 'pending', la.provider_session_id, la.expected_amount_cents,
    la.currency,
    jsonb_build_object(
      'version', 1,
      'legacy_backfill', true,
      'cart_id', la.cart_id,
      'show_id', la.show_id,
      'show_name', la.show_name,
      'user_id', la.user_id,
      'provider', 'stripe',
      'currency', la.currency,
      'show_balance_total_cents', la.show_balance_total_cents,
      'expected_amount_cents', la.expected_amount_cents,
      'online_fee_cents', la.online_fee_cents,
      'platform_fee_cents', la.platform_fee_cents,
      'online_payment_fee_mode', la.online_payment_fee_mode,
      'online_payment_fee_label', la.online_payment_fee_label,
      'online_payment_fee_description', la.online_payment_fee_description,
      'balances', la.balances
    ),
    la.created_at, now()
  from legacy_attempts la
  on conflict (stripe_checkout_session_id) do nothing
  returning id, cart_id, provider_session_id
)
update public.entry_carts c
set
  active_payment_session_id = i.id,
  payment_attempt_started_at = coalesce(c.payment_attempt_started_at, now()),
  selected_payment_timing = 'online',
  selected_payment_provider = 'stripe'
from inserted i
where c.id = i.cart_id
  and c.status = 'active'
  and c.payment_status <> 'paid'
  and c.active_payment_session_id is null;

update public.show_payments sp
set
  payment_session_id = s.id,
  gross_charged_cents = sp.amount_cents + coalesce(
    (sp.metadata ->> 'proportional_online_payment_fee_cents')::integer, 0
  ),
  online_fee_cents = coalesce(
    (sp.metadata ->> 'proportional_online_payment_fee_cents')::integer, 0
  )
from public.show_payment_sessions s
where sp.provider = 'stripe'
  and sp.status in ('pending', 'processing', 'requires_action')
  and s.provider = 'stripe'
  and s.provider_session_id = coalesce(
    sp.stripe_checkout_session_id, sp.checkout_session_id
  )
  and sp.payment_session_id is null;

-- This existing entries trigger used an unqualified table and inherited the
-- caller's search_path. Qualify it so hardened empty-search-path RPCs can
-- safely insert entries.
create or replace function public.prevent_changes_when_locked()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_show_id uuid;
begin
  v_show_id := coalesce(new.show_id, old.show_id);
  if (select s.is_locked from public.shows s where s.id = v_show_id) then
    raise exception 'Show is locked. Changes are not allowed.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- Preserve both the quoted fee state and all payment state after an attempt
-- starts. This trigger separates recalculation from payment-state mutation
-- without changing calculate_entry_cart_balance's return type.
create or replace function public.protect_cart_balance_after_payment_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('ringmaster.payment_state_write', true) = 'on' then
    return new;
  end if;

  if old.entry_cart_id is not null and (
    old.paid_online_cents <> 0
    or old.paid_manual_cents <> 0
    or old.refunded_cents <> 0
    or old.payment_status in ('pending', 'partial', 'paid', 'overpaid', 'refunded')
    or exists (
      select 1
      from public.entry_carts c
      where c.id = old.entry_cart_id
        and (
          c.active_payment_session_id is not null
          or c.completed_payment_session_id is not null
          or c.payment_status in ('pending', 'paid', 'refunded')
        )
    )
  ) then
    new.currency := old.currency;
    new.entry_count := old.entry_count;
    new.fur_count := old.fur_count;
    new.entries_subtotal_cents := old.entries_subtotal_cents;
    new.fur_subtotal_cents := old.fur_subtotal_cents;
    new.show_fee_subtotal_cents := old.show_fee_subtotal_cents;
    new.subtotal_before_discount_cents := old.subtotal_before_discount_cents;
    new.discount_cents := old.discount_cents;
    new.calculated_total_cents := old.calculated_total_cents;
    new.paid_online_cents := old.paid_online_cents;
    new.paid_manual_cents := old.paid_manual_cents;
    new.refunded_cents := old.refunded_cents;
    new.balance_due_cents := old.balance_due_cents;
    new.payment_status := old.payment_status;
    new.latest_show_payment_id := old.latest_show_payment_id;
    new.latest_checkout_session_id := old.latest_checkout_session_id;
    new.latest_payment_intent_id := old.latest_payment_intent_id;
    new.section_breakdown := old.section_breakdown;
    new.fee_snapshot := old.fee_snapshot;
    new.calculated_at := old.calculated_at;
  end if;

  return new;
end;
$$;

create or replace function public.finalize_entry_cart_paid(
  p_cart_id uuid,
  p_payment_session_id uuid,
  p_provider text,
  p_provider_payment_id text,
  p_amount_cents integer,
  p_currency text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart public.entry_carts%rowtype;
  v_session public.show_payment_sessions%rowtype;
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_currency text := lower(btrim(coalesce(p_currency, '')));
  v_payment record;
  v_payment_count integer;
  v_pending_count integer;
  v_added integer;
  v_entries_created integer := 0;
  v_result jsonb;
  v_now timestamptz := now();
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;

  select * into v_cart
  from public.entry_carts
  where id = p_cart_id
  for update;

  if not found then
    raise exception 'Cart not found';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = p_payment_session_id
  for update;

  if not found or v_session.cart_id is distinct from p_cart_id then
    raise exception 'Payment session does not belong to this cart';
  end if;
  if v_session.provider <> v_provider then
    raise exception 'Payment provider does not match the attempt';
  end if;

  if v_session.attempt_status = 'finalized' then
    return coalesce(
      v_session.metadata -> 'finalization_result',
      jsonb_build_object(
        'finalized', true,
        'already_finalized', true,
        'entries_created', (
          select count(*) from public.entries
          where payment_session_id = p_payment_session_id
        ),
        'payment_session_id', p_payment_session_id
      )
    ) || jsonb_build_object('already_finalized', true);
  end if;

  if v_session.attempt_status in ('failed', 'cancelled', 'expired', 'superseded') then
    raise exception 'Payment attempt cannot be finalized from status %',
      v_session.attempt_status;
  end if;
  if v_cart.active_payment_session_id is distinct from p_payment_session_id then
    raise exception 'This payment attempt is no longer active';
  end if;
  if p_amount_cents is distinct from v_session.expected_amount_cents then
    raise exception 'Charged amount does not match the saved quote';
  end if;
  if v_currency is distinct from lower(v_session.expected_currency) then
    raise exception 'Charged currency does not match the saved quote';
  end if;
  if nullif(btrim(coalesce(p_provider_payment_id, '')), '') is null then
    raise exception 'Provider payment ID is required';
  end if;
  if v_session.provider_payment_id is not null
     and v_session.provider_payment_id <> p_provider_payment_id then
    raise exception 'Provider payment ID does not match the attempt';
  end if;

  -- Acquire ledger locks in a consistent order before any writes.
  perform 1
  from public.show_payments
  where payment_session_id = p_payment_session_id and provider = v_provider
  order by id
  for update;

  select
    count(*),
    count(*) filter (where status in ('pending', 'processing', 'requires_action'))
  into v_payment_count, v_pending_count
  from public.show_payments
  where payment_session_id = p_payment_session_id and provider = v_provider;

  if v_payment_count = 0 then
    raise exception 'No matching payment ledger rows exist';
  end if;
  if v_pending_count <> v_payment_count then
    raise exception 'Payment ledger rows are not all pending';
  end if;

  update public.show_payments
  set
    status = 'paid',
    payment_status = 'paid',
    provider_payment_id = p_provider_payment_id,
    payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else payment_intent_id end,
    stripe_payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else stripe_payment_intent_id end,
    paid_at = v_now,
    updated_at = v_now
  where payment_session_id = p_payment_session_id and provider = v_provider;

  perform set_config('ringmaster.payment_state_write', 'on', true);
  for v_payment in
    select id from public.show_payments
    where payment_session_id = p_payment_session_id and provider = v_provider
    order by id
  loop
    perform public.apply_show_payment_to_balance(v_payment.id);
  end loop;
  perform set_config('ringmaster.payment_state_write', 'off', true);

  insert into public.entries (
    show_id, exhibitor_id, animal_id, species, tattoo, animal_name, breed,
    variety, fur_variety, sex, class_name, status, section_id,
    exhibitor_user_id, created_at, is_fur, payment_status, paid_at,
    source_cart_id, source_cart_item_id, payment_session_id, cart_entry_kind
  )
  select
    v_cart.show_id, i.exhibitor_id, i.animal_id, i.species, i.tattoo,
    coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed, i.variety,
    null, i.sex, i.class_name, 'entered', i.section_id, v_cart.user_id,
    v_now, false, 'paid', v_now, p_cart_id, i.id,
    p_payment_session_id, 'entry'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_entries_created := v_entries_created + v_added;

  insert into public.entries (
    show_id, exhibitor_id, animal_id, species, tattoo, animal_name, breed,
    variety, fur_variety, sex, class_name, status, section_id,
    exhibitor_user_id, created_at, is_fur, payment_status, paid_at,
    source_cart_id, source_cart_item_id, payment_session_id, cart_entry_kind
  )
  select
    v_cart.show_id, i.exhibitor_id, i.animal_id, i.species, i.tattoo,
    coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed, i.variety,
    coalesce(
      nullif(btrim(i.fur_variety), ''),
      case when lower(coalesce(i.variety, '')) in (
        'white', 'blue eyed white', 'blue-eyed white', 'bew',
        'ruby eyed white', 'ruby-eyed white', 'rew'
      ) then 'White' else 'Colored' end
    ),
    null, 'Fur / Wool', 'entered', i.section_id, v_cart.user_id,
    v_now, true, 'paid', v_now, p_cart_id, i.id,
    p_payment_session_id, 'fur'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id and coalesce(i.is_fur, false)
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_entries_created := v_entries_created + v_added;

  update public.entry_carts
  set
    status = 'submitted',
    submitted_at = coalesce(submitted_at, v_now),
    payment_status = 'paid',
    payment_provider = v_provider,
    selected_payment_timing = 'online',
    selected_payment_provider = v_provider,
    completed_payment_session_id = p_payment_session_id,
    provider_payment_id = p_provider_payment_id,
    payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else payment_intent_id end,
    checkout_session_id = coalesce(v_session.provider_session_id,
      checkout_session_id),
    payment_amount_total = p_amount_cents::numeric / 100,
    payment_currency = v_currency,
    paid_at = v_now,
    payment_finalized_at = v_now,
    updated_at = v_now
  where id = p_cart_id;

  v_result := jsonb_build_object(
    'finalized', true,
    'already_finalized', false,
    'entries_created', v_entries_created,
    'payment_session_id', p_payment_session_id
  );

  update public.show_payment_sessions
  set
    provider_payment_id = p_provider_payment_id,
    stripe_payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else stripe_payment_intent_id end,
    attempt_status = 'finalized',
    status = 'paid',
    finalized_at = v_now,
    metadata = coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object('finalization_result', v_result),
    updated_at = v_now
  where id = p_payment_session_id;

  return v_result;
end;
$$;

create or replace function public.commit_entry_cart_day_of(p_cart_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart public.entry_carts%rowtype;
  v_show public.shows%rowtype;
  v_added integer;
  v_inserted integer := 0;
  v_now timestamptz := now();
  v_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  select * into v_cart
  from public.entry_carts
  where id = p_cart_id
  for update;

  if not found then
    raise exception 'Cart not found';
  end if;
  if not v_is_service
     and auth.uid() is distinct from v_cart.user_id
     and not public.user_can_manage_entries(v_cart.show_id)
     and not public.user_can_manage_show_settings(v_cart.show_id) then
    raise exception 'You do not have access to this cart'
      using errcode = '42501';
  end if;
  if v_cart.status = 'submitted' then
    return 0;
  end if;
  if v_cart.status <> 'active' then
    raise exception 'Only active carts can be submitted';
  end if;

  select * into v_show from public.shows where id = v_cart.show_id;
  if not found then
    raise exception 'Show not found';
  end if;
  if v_show.entry_close_at is not null and v_now > v_show.entry_close_at then
    raise exception 'This show''s entry deadline has passed';
  end if;
  if v_show.payment_timing_mode not in ('pay_at_show_only', 'online_or_at_show') then
    raise exception 'This show does not allow payment at the show';
  end if;
  if not exists (
    select 1 from public.entry_cart_items where cart_id = p_cart_id
  ) then
    raise exception 'Cart is empty';
  end if;
  if exists (
    select 1 from public.entry_cart_items
    where cart_id = p_cart_id and exhibitor_id is null
  ) then
    raise exception 'One or more cart items are missing an exhibitor assignment';
  end if;
  if v_cart.active_payment_session_id is not null
     or v_cart.payment_status in ('pending', 'paid') then
    raise exception 'Cart has an online payment attempt in progress';
  end if;

  update public.entry_carts
  set
    selected_payment_timing = 'at_show',
    selected_payment_provider = null,
    payment_provider = 'offline',
    payment_status = 'unpaid',
    updated_at = v_now
  where id = p_cart_id;

  insert into public.entries (
    show_id, exhibitor_user_id, exhibitor_id, animal_id, species, tattoo,
    animal_name, breed, variety, fur_variety, sex, class_name, status,
    section_id, is_fur, payment_status, source_cart_id,
    source_cart_item_id, cart_entry_kind
  )
  select
    v_cart.show_id, v_cart.user_id, i.exhibitor_id, i.animal_id, i.species,
    i.tattoo, coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed,
    i.variety, null, i.sex, i.class_name, 'submitted', i.section_id, false,
    'unpaid', p_cart_id, i.id, 'entry'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_inserted := v_inserted + v_added;

  insert into public.entries (
    show_id, exhibitor_user_id, exhibitor_id, animal_id, species, tattoo,
    animal_name, breed, variety, fur_variety, sex, class_name, status,
    section_id, is_fur, payment_status, source_cart_id,
    source_cart_item_id, cart_entry_kind
  )
  select
    v_cart.show_id, v_cart.user_id, i.exhibitor_id, i.animal_id, i.species,
    i.tattoo, coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed,
    i.variety, coalesce(nullif(btrim(i.fur_variety), ''), 'Colored'),
    null, 'Fur / Wool', 'submitted', i.section_id, true, 'unpaid',
    p_cart_id, i.id, 'fur'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id and coalesce(i.is_fur, false)
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_inserted := v_inserted + v_added;

  update public.entry_carts
  set status = 'submitted', submitted_at = coalesce(submitted_at, v_now),
      updated_at = v_now
  where id = p_cart_id;

  return v_inserted;
end;
$$;

-- Deployment bridge for the previously deployed Stripe webhook. It resolves
-- the exact active attempt and delegates to the hardened finalizer. New code
-- must call finalize_entry_cart_paid directly.
create or replace function public.commit_entry_cart_paid(p_cart_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart public.entry_carts%rowtype;
  v_session public.show_payment_sessions%rowtype;
  v_amount_cents integer;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;

  select * into v_cart
  from public.entry_carts where id = p_cart_id for update;
  if not found then raise exception 'Cart not found'; end if;
  if v_cart.active_payment_session_id is null then
    raise exception 'Cart has no active payment attempt';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = v_cart.active_payment_session_id;
  if not found or v_session.cart_id is distinct from p_cart_id
     or v_session.provider <> 'stripe' then
    raise exception 'Active Stripe payment attempt not found';
  end if;
  if v_session.attempt_status = 'finalized' then return; end if;
  if v_session.provider_session_id is distinct from v_cart.checkout_session_id then
    raise exception 'Checkout Session does not match the active attempt';
  end if;
  if nullif(btrim(coalesce(v_cart.payment_intent_id, '')), '') is null then
    raise exception 'Provider payment ID is missing';
  end if;

  v_amount_cents := round(v_cart.payment_amount_total * 100)::integer;
  if v_amount_cents is distinct from v_session.expected_amount_cents
     or lower(v_cart.payment_currency) is distinct from
       lower(v_session.expected_currency) then
    raise exception 'Cart payment does not match the saved quote';
  end if;
  if not exists (
    select 1 from public.show_payments
    where payment_session_id = v_session.id and provider = 'stripe'
  ) then
    raise exception 'No matching payment ledger rows exist';
  end if;

  -- The legacy webhook marks these rows paid before invoking this RPC. Return
  -- only the exact attempt to pending so the transactional finalizer performs
  -- the authoritative paid transition and balance application atomically.
  update public.show_payments
  set status = 'pending', payment_status = 'pending', paid_at = null,
      updated_at = now()
  where payment_session_id = v_session.id
    and provider = 'stripe'
    and status = 'paid';

  perform public.finalize_entry_cart_paid(
    p_cart_id,
    v_session.id,
    'stripe',
    v_cart.payment_intent_id,
    v_amount_cents,
    v_cart.payment_currency
  );
end;
$$;


create or replace function public.attach_provider_payment_session(
  p_payment_session_id uuid,
  p_provider text,
  p_provider_session_id text,
  p_checkout_url text,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_payment_sessions%rowtype;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = p_payment_session_id
  for update;

  if not found or v_session.provider <> lower(btrim(p_provider)) then
    raise exception 'Payment session not found';
  end if;
  if v_session.attempt_status not in ('created', 'pending') then
    raise exception 'Payment session is not attachable';
  end if;
  if v_session.provider_session_id is not null
     and v_session.provider_session_id <> p_provider_session_id then
    raise exception 'Provider session is already set';
  end if;

  update public.show_payment_sessions
  set
    provider_session_id = p_provider_session_id,
    provider_attempt_id = coalesce(provider_attempt_id, p_provider_session_id),
    stripe_checkout_session_id = case when provider = 'stripe'
      then p_provider_session_id else stripe_checkout_session_id end,
    checkout_url = p_checkout_url,
    expires_at = coalesce(p_expires_at, expires_at),
    attempt_status = 'pending',
    status = 'pending',
    updated_at = now()
  where id = p_payment_session_id;

  update public.show_payments
  set
    checkout_session_id = p_provider_session_id,
    stripe_checkout_session_id = case when provider = 'stripe'
      then p_provider_session_id else stripe_checkout_session_id end,
    checkout_url = p_checkout_url,
    updated_at = now()
  where payment_session_id = p_payment_session_id
    and provider = lower(btrim(p_provider));

  update public.entry_carts
  set
    checkout_session_id = p_provider_session_id,
    updated_at = now()
  where active_payment_session_id = p_payment_session_id;

  return jsonb_build_object(
    'payment_session_id', p_payment_session_id,
    'provider_session_id', p_provider_session_id,
    'attached', true
  );
end;
$$;

create or replace function public.mark_payment_attempt_terminal(
  p_payment_session_id uuid,
  p_provider text,
  p_status text,
  p_failure_code text default null,
  p_failure_message text default null,
  p_provider_payment_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_payment_sessions%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;
  if v_status not in ('failed', 'cancelled', 'expired', 'superseded') then
    raise exception 'Invalid terminal payment status';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = p_payment_session_id
  for update;

  if not found or v_session.provider <> lower(btrim(p_provider)) then
    raise exception 'Payment session not found';
  end if;
  if v_session.attempt_status = 'finalized' then
    return jsonb_build_object('updated', false, 'already_finalized', true);
  end if;

  update public.show_payment_sessions
  set
    attempt_status = v_status,
    status = case when v_status = 'superseded' then 'expired' else v_status end,
    failure_code = p_failure_code,
    failure_message = left(p_failure_message, 1000),
    provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
    updated_at = now()
  where id = p_payment_session_id;

  update public.show_payments
  set
    status = case when v_status in ('expired', 'superseded')
      then 'cancelled' else v_status end,
    payment_status = case when v_status in ('expired', 'superseded')
      then 'cancelled' else v_status end,
    provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
    failure_reason = left(p_failure_message, 1000),
    failed_at = case when v_status = 'failed' then now() else failed_at end,
    updated_at = now()
  where payment_session_id = p_payment_session_id
    and provider = lower(btrim(p_provider))
    and status not in ('paid', 'partially_refunded', 'refunded');

  update public.entry_carts
  set
    active_payment_session_id = null,
    payment_status = case when v_status = 'failed' then 'failed' else 'cancelled' end,
    provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id),
    updated_at = now()
  where id = v_session.cart_id
    and active_payment_session_id = p_payment_session_id
    and payment_status <> 'paid';

  return jsonb_build_object('updated', true, 'already_finalized', false);
end;
$$;

create or replace function public.record_payment_event(
  p_provider text,
  p_event_id text,
  p_event_type text,
  p_payload jsonb default '{}'::jsonb,
  p_payment_session_id uuid default null,
  p_provider_payment_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.show_payment_events%rowtype;
  v_inserted boolean := false;
  v_claimed boolean := false;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;
  if lower(btrim(coalesce(p_provider, ''))) not in ('stripe', 'square', 'paypal')
     or nullif(btrim(coalesce(p_event_id, '')), '') is null then
    raise exception 'Valid provider and event ID are required';
  end if;

  insert into public.show_payment_events (
    provider, event_id, event_type, payload, processing_status, received_at,
    payment_session_id, provider_payment_id
  ) values (
    lower(btrim(p_provider)), btrim(p_event_id), p_event_type,
    coalesce(p_payload, '{}'::jsonb), 'processing', now(),
    p_payment_session_id, p_provider_payment_id
  )
  on conflict (provider, event_id) do nothing
  returning * into v_event;

  v_inserted := found;
  v_claimed := v_inserted;
  if not v_inserted then
    select * into v_event
    from public.show_payment_events
    where provider = lower(btrim(p_provider)) and event_id = btrim(p_event_id)
    for update;

    if v_event.processing_status in ('received', 'failed') then
      update public.show_payment_events
      set processing_status = 'processing', processing_error = null,
          processed_at = null
      where id = v_event.id
      returning * into v_event;
      v_claimed := true;
    end if;
  end if;

  return jsonb_build_object(
    'event_row_id', v_event.id,
    'duplicate', not v_inserted,
    'claimed', v_claimed,
    'already_processed', v_event.processing_status in ('processed', 'ignored'),
    'processing_status', v_event.processing_status
  );
end;
$$;

create or replace function public.set_payment_event_status(
  p_provider text,
  p_event_id text,
  p_processing_status text,
  p_processing_error text default null,
  p_payment_session_id uuid default null,
  p_provider_payment_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;
  if p_processing_status not in ('received', 'processing', 'processed', 'ignored', 'failed') then
    raise exception 'Invalid event processing status';
  end if;

  update public.show_payment_events
  set
    processing_status = p_processing_status,
    processing_error = case when p_processing_status = 'failed'
      then left(p_processing_error, 1000) else null end,
    processed_at = case when p_processing_status in ('processed', 'ignored', 'failed')
      then now() else null end,
    payment_session_id = coalesce(payment_session_id, p_payment_session_id),
    provider_payment_id = coalesce(provider_payment_id, p_provider_payment_id)
  where provider = lower(btrim(p_provider)) and event_id = btrim(p_event_id);

  if not found then
    raise exception 'Payment event not found';
  end if;
end;
$$;


drop trigger if exists protect_cart_balance_after_payment_attempt
  on public.show_exhibitor_balances;
create trigger protect_cart_balance_after_payment_attempt
before update on public.show_exhibitor_balances
for each row execute function public.protect_cart_balance_after_payment_attempt();

-- Keep the deployed calculation intact behind an authorization wrapper.
alter function public.calculate_entry_cart_balance(uuid)
  rename to calculate_entry_cart_balance_internal;

create or replace function public.calculate_entry_cart_balance(p_cart_id uuid)
returns setof public.show_exhibitor_balances
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart public.entry_carts%rowtype;
  v_is_service boolean :=
    coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  select * into v_cart
  from public.entry_carts
  where id = p_cart_id;

  if not found then
    raise exception 'Cart % not found', p_cart_id;
  end if;

  if not v_is_service
     and auth.uid() is distinct from v_cart.user_id
     and not public.user_can_manage_entries(v_cart.show_id)
     and not public.user_can_manage_show_settings(v_cart.show_id) then
    raise exception 'You do not have access to this cart'
      using errcode = '42501';
  end if;

  return query
  select *
  from public.calculate_entry_cart_balance_internal(p_cart_id);
end;
$$;

create or replace function public.create_payment_quote_attempt(
  p_cart_id uuid,
  p_user_id uuid,
  p_provider text,
  p_platform_fee_default_percent numeric default 0.02,
  p_processing_fee_percent numeric default 0.029,
  p_processing_fee_fixed_cents integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart public.entry_carts%rowtype;
  v_show public.shows%rowtype;
  v_active public.show_payment_sessions%rowtype;
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_enabled boolean := false;
  v_ready boolean := false;
  v_currency text;
  v_show_total integer;
  v_online_fee integer := 0;
  v_total integer;
  v_platform_fee integer;
  v_platform_raw numeric;
  v_platform_rate numeric;
  v_processing_rate numeric;
  v_combined_rate numeric;
  v_required_fee integer;
  v_snapshot jsonb;
  v_quote_hash text;
  v_idempotency_key text;
  v_attempt_number integer;
  v_session_id uuid;
  v_now timestamptz := now();
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;

  if v_provider not in ('stripe', 'square', 'paypal') then
    raise exception 'Unsupported payment provider';
  end if;

  select * into v_cart
  from public.entry_carts
  where id = p_cart_id
  for update;

  if not found then
    raise exception 'Cart not found';
  end if;
  if v_cart.user_id is distinct from p_user_id then
    raise exception 'You do not have access to this cart' using errcode = '42501';
  end if;
  if v_cart.status <> 'active' then
    raise exception 'Only active carts can be checked out';
  end if;
  if v_cart.payment_status = 'paid' then
    raise exception 'Cart is already paid';
  end if;

  if v_cart.active_payment_session_id is not null then
    select * into v_active
    from public.show_payment_sessions
    where id = v_cart.active_payment_session_id
    for update;

    if found
       and v_active.provider = v_provider
       and v_active.attempt_status in ('created', 'pending', 'processing')
       and (v_active.expires_at is null or v_active.expires_at > v_now) then
      return jsonb_build_object(
        'reused', true,
        'payment_session_id', v_active.id,
        'idempotency_key', v_active.idempotency_key,
        'quote_hash', v_active.quote_hash,
        'quote', v_active.quote_snapshot,
        'provider_session_id', v_active.provider_session_id,
        'checkout_url', v_active.checkout_url,
        'expires_at', v_active.expires_at
      );
    end if;

    if found
       and v_active.provider = v_provider
       and v_active.attempt_status in ('created', 'pending', 'processing')
       and v_active.expires_at is not null
       and v_active.expires_at <= v_now then
      update public.show_payment_sessions
      set attempt_status = 'expired', status = 'expired',
          failure_code = 'expired',
          failure_message = 'The checkout attempt expired.', updated_at = v_now
      where id = v_active.id;
      update public.show_payments
      set status = 'cancelled', payment_status = 'cancelled', updated_at = v_now
      where payment_session_id = v_active.id
        and status not in ('paid', 'partially_refunded', 'refunded');
      update public.entry_carts
      set active_payment_session_id = null, payment_status = 'cancelled',
          updated_at = v_now
      where id = p_cart_id and active_payment_session_id = v_active.id;
    end if;

    if found
       and v_active.provider <> v_provider
       and v_active.attempt_status in ('created', 'pending', 'processing') then
      raise exception 'Another online payment attempt is already active';
    end if;
  end if;

  select * into v_show
  from public.shows
  where id = v_cart.show_id;

  if not found then
    raise exception 'Show not found';
  end if;
  if v_show.entry_close_at is not null and v_now > v_show.entry_close_at then
    raise exception 'This show''s entry deadline has passed';
  end if;
  if v_show.payment_timing_mode not in ('online_only', 'online_or_at_show') then
    raise exception 'This show does not allow online payment';
  end if;
  if not exists (
    select 1 from public.entry_cart_items where cart_id = p_cart_id
  ) then
    raise exception 'Cart is empty';
  end if;
  if exists (
    select 1 from public.entry_cart_items
    where cart_id = p_cart_id and exhibitor_id is null
  ) then
    raise exception 'One or more cart items are missing an exhibitor assignment';
  end if;

  select
    case v_provider
      when 'stripe' then coalesce(ps.stripe_enabled, false)
      when 'square' then coalesce(ps.square_enabled, false)
      when 'paypal' then coalesce(ps.paypal_enabled, false)
    end
  into v_enabled
  from public.show_payment_settings ps
  where ps.show_id = v_show.id;

  if v_provider = 'stripe' then
    select exists (
      select 1 from public.show_payment_account_links l
      where l.show_id = v_show.id
        and l.provider = 'stripe'
        and l.stripe_account_id is not null
        and coalesce(l.charges_enabled, false)
        and coalesce(l.account_status, '') = 'ready'
    ) into v_ready;
  elsif v_provider = 'square' then
    select exists (
      select 1 from public.show_payment_account_links l
      where l.show_id = v_show.id
        and l.provider = 'square'
        and l.provider_account_id is not null
        and l.provider_location_id is not null
        and coalesce(l.status, '') in ('ready', 'connected', 'active')
    ) into v_ready;
  else
    select exists (
      select 1 from public.show_payment_account_links l
      where l.show_id = v_show.id
        and l.provider = 'paypal'
        and l.provider_account_id is not null
        and coalesce(l.status, '') in ('ready', 'connected', 'active')
    ) into v_ready;
  end if;

  if not coalesce(v_enabled, false) then
    raise exception 'The selected online payment provider is not enabled';
  end if;
  if not coalesce(v_ready, false) then
    raise exception 'The selected online payment provider is not ready';
  end if;

  -- Exactly one authoritative calculation occurs before the attempt begins.
  perform public.calculate_entry_cart_balance(p_cart_id);

  select
    min(lower(currency)),
    sum(balance_due_cents)::integer
  into v_currency, v_show_total
  from public.show_exhibitor_balances
  where entry_cart_id = p_cart_id and source = 'cart';

  if v_show_total is null or v_show_total <= 0 then
    raise exception 'Calculated checkout total must be greater than zero';
  end if;
  if exists (
    select 1 from public.show_exhibitor_balances
    where entry_cart_id = p_cart_id
      and source = 'cart'
      and lower(currency) <> v_currency
  ) then
    raise exception 'Cart contains mixed currencies';
  end if;
  if char_length(v_currency) <> 3 then
    raise exception 'Invalid checkout currency';
  end if;

  v_platform_raw := coalesce(v_show.platform_fee_percent,
    p_platform_fee_default_percent, 0.02);
  v_platform_rate := case
    when v_platform_raw > 1 then v_platform_raw / 100.0
    else v_platform_raw
  end;
  v_processing_rate := case
    when coalesce(p_processing_fee_percent, 0) > 1
      then p_processing_fee_percent / 100.0
    else coalesce(p_processing_fee_percent, 0)
  end;

  if v_platform_rate < 0 or v_processing_rate < 0 then
    raise exception 'Fee percentages cannot be negative';
  end if;
  v_combined_rate := v_platform_rate + v_processing_rate;
  if v_combined_rate >= 1 then
    raise exception 'Configured fee percentages are too high';
  end if;

  if v_show.online_payment_fee_mode = 'pass_to_exhibitor' then
    v_online_fee := greatest(ceil(
      (v_show_total + greatest(coalesce(p_processing_fee_fixed_cents, 0), 0))
      / (1 - v_combined_rate) - v_show_total
    )::integer, 0);

    for i in 1..10 loop
      v_total := v_show_total + v_online_fee;
      v_required_fee := round(v_total * v_platform_rate)::integer
        + ceil(v_total * v_processing_rate
          + greatest(coalesce(p_processing_fee_fixed_cents, 0), 0))::integer;
      exit when v_online_fee >= v_required_fee;
      v_online_fee := v_required_fee;
    end loop;
  end if;

  v_total := v_show_total + v_online_fee;
  v_platform_fee := round(v_total * v_platform_rate)::integer;
  if v_platform_fee < 1 and v_platform_rate > 0 then
    v_platform_fee := 1;
  end if;
  if v_platform_fee >= v_total then
    raise exception 'Platform fee must be less than the charged amount';
  end if;

  select jsonb_build_object(
    'version', 1,
    'cart_id', p_cart_id,
    'show_id', v_show.id,
    'show_name', v_show.name,
    'user_id', p_user_id,
    'provider', v_provider,
    'currency', v_currency,
    'show_balance_total_cents', v_show_total,
    'online_fee_cents', v_online_fee,
    'platform_fee_cents', v_platform_fee,
    'expected_amount_cents', v_total,
    'platform_fee_rate', v_platform_rate,
    'processing_fee_rate', v_processing_rate,
    'processing_fee_fixed_cents', greatest(coalesce(p_processing_fee_fixed_cents, 0), 0),
    'online_payment_fee_mode', v_show.online_payment_fee_mode,
    'online_payment_fee_label', v_show.online_payment_fee_label,
    'online_payment_fee_description', v_show.online_payment_fee_description,
    'balances', coalesce(jsonb_agg(jsonb_build_object(
      'balance_id', b.id,
      'exhibitor_id', b.exhibitor_id,
      'exhibitor_user_id', b.exhibitor_user_id,
      'entry_count', b.entry_count,
      'fur_count', b.fur_count,
      'entries_subtotal_cents', b.entries_subtotal_cents,
      'fur_subtotal_cents', b.fur_subtotal_cents,
      'show_fee_subtotal_cents', b.show_fee_subtotal_cents,
      'subtotal_before_discount_cents', b.subtotal_before_discount_cents,
      'discount_cents', b.discount_cents,
      'amount_cents', b.balance_due_cents,
      'fee_snapshot', b.fee_snapshot,
      'section_breakdown', b.section_breakdown
    ) order by b.id), '[]'::jsonb)
  ) into v_snapshot
  from public.show_exhibitor_balances b
  where b.entry_cart_id = p_cart_id and b.source = 'cart';

  v_quote_hash := encode(
    extensions.digest(convert_to(v_snapshot::text, 'UTF8'), 'sha256'),
    'hex'
  );
  select count(*) + 1 into v_attempt_number
  from public.show_payment_sessions
  where cart_id = p_cart_id and provider = v_provider;
  v_idempotency_key := format(
    'cart:%s:%s:%s:v%s', p_cart_id, v_provider, v_quote_hash, v_attempt_number
  );

  update public.show_payment_sessions
  set
    attempt_status = 'superseded',
    status = 'expired',
    failure_code = 'superseded',
    failure_message = 'A newer checkout attempt replaced this attempt.',
    updated_at = v_now
  where cart_id = p_cart_id
    and provider = v_provider
    and attempt_status in ('created', 'pending', 'processing');

  insert into public.show_payment_sessions (
    show_id, cart_id, provider, status, currency, amount_cents,
    platform_fee_cents, online_fee_cents, metadata, idempotency_key,
    quote_hash, quote_version, attempt_status, expected_amount_cents,
    expected_currency, quote_snapshot, created_at, updated_at
  ) values (
    v_show.id, p_cart_id, v_provider, 'created', v_currency, v_total,
    v_platform_fee, v_online_fee,
    jsonb_build_object('source', 'provider_neutral_checkout'),
    v_idempotency_key, v_quote_hash, 1, 'created', v_total, v_currency,
    v_snapshot, v_now, v_now
  ) returning id into v_session_id;

  with balances as (
    select
      b.*,
      row_number() over (order by b.id) as rn,
      count(*) over () as row_count,
      floor(b.balance_due_cents::numeric * v_platform_fee / v_show_total)::integer
        as platform_base,
      floor(b.balance_due_cents::numeric * v_online_fee / v_show_total)::integer
        as online_base
    from public.show_exhibitor_balances b
    where b.entry_cart_id = p_cart_id and b.source = 'cart'
  ), allocated as (
    select balances.*,
      platform_base + case when rn = row_count then
        v_platform_fee - sum(platform_base) over () else 0 end
        as allocated_platform_fee,
      online_base + case when rn = row_count then
        v_online_fee - sum(online_base) over () else 0 end
        as allocated_online_fee
    from balances
  )
  insert into public.show_payments (
    show_id, exhibitor_user_id, exhibitor_id, entry_cart_id, cart_id,
    currency, subtotal_cents, total_cents, platform_fee_cents, status,
    payment_method, provider, payment_type, amount_cents,
    platform_fee_percent, platform_fee_amount_cents, payer_user_id,
    payment_method_type, balance_id, metadata, payment_status,
    payment_session_id, gross_charged_cents, online_fee_cents,
    refunded_cents, application_fee_refunded_cents, created_at, updated_at
  )
  select
    v_show.id, a.exhibitor_user_id, a.exhibitor_id, p_cart_id, p_cart_id,
    v_currency, a.subtotal_before_discount_cents, a.balance_due_cents,
    a.allocated_platform_fee, 'pending', v_provider, v_provider, 'checkout',
    a.balance_due_cents, v_platform_rate * 100,
    a.allocated_platform_fee, p_user_id, 'card', a.id,
    jsonb_build_object(
      'quote_hash', v_quote_hash,
      'payment_session_id', v_session_id,
      'allocated_online_fee_cents', a.allocated_online_fee,
      'fee_snapshot', a.fee_snapshot,
      'section_breakdown', a.section_breakdown
    ),
    'pending', v_session_id,
    a.balance_due_cents + a.allocated_online_fee,
    a.allocated_online_fee, 0, 0, v_now, v_now
  from allocated a;

  insert into public.show_payment_line_items (
    show_payment_id, payment_session_id, cart_id, exhibitor_id, balance_id,
    item_type, line_type, label, quantity, unit_amount_cents,
    total_amount_cents, metadata
  )
  select null, v_session_id, p_cart_id, b.exhibitor_id, b.id,
    case when x.line_type = 'entry_fee' then 'entry_fee' else 'other' end,
    x.line_type, x.label, 1, x.amount, x.amount,
    jsonb_build_object('quote_hash', v_quote_hash)
  from public.show_exhibitor_balances b
  cross join lateral (values
    ('entry_fee', 'Entry fees', b.entries_subtotal_cents),
    ('fur_fee', 'Fur / Wool fees', b.fur_subtotal_cents),
    ('per_show_fee', 'Per-show fees', b.show_fee_subtotal_cents),
    ('discount', 'Discount', -b.discount_cents)
  ) as x(line_type, label, amount)
  where b.entry_cart_id = p_cart_id
    and b.source = 'cart'
    and x.amount <> 0;

  if v_online_fee <> 0 then
    insert into public.show_payment_line_items (
      show_payment_id, payment_session_id, cart_id, item_type, line_type,
      label, quantity, unit_amount_cents, total_amount_cents, metadata
    ) values (
      null, v_session_id, p_cart_id, 'other', 'online_fee',
      v_show.online_payment_fee_label, 1, v_online_fee, v_online_fee,
      jsonb_build_object('quote_hash', v_quote_hash)
    );
  end if;

  insert into public.show_payment_line_items (
    show_payment_id, payment_session_id, cart_id, item_type, line_type,
    label, quantity, unit_amount_cents, total_amount_cents, metadata
  ) values (
    null, v_session_id, p_cart_id, 'other', 'platform_fee',
    'Platform fee', 1, v_platform_fee, v_platform_fee,
    jsonb_build_object('included_in_online_fee',
      v_show.online_payment_fee_mode = 'pass_to_exhibitor')
  );

  update public.entry_carts
  set
    active_payment_session_id = v_session_id,
    selected_payment_timing = 'online',
    selected_payment_provider = v_provider,
    payment_provider = v_provider,
    payment_status = 'pending',
    payment_attempt_started_at = v_now,
    payment_amount_total = v_total::numeric / 100,
    payment_currency = v_currency,
    updated_at = v_now
  where id = p_cart_id;

  return jsonb_build_object(
    'reused', false,
    'payment_session_id', v_session_id,
    'idempotency_key', v_idempotency_key,
    'quote_hash', v_quote_hash,
    'quote', v_snapshot
  );
end;
$$;

-- Table-level defense in depth: clients retain RLS-filtered reads, while all
-- financial writes must use the backend/service-role path.
revoke insert, update, delete, truncate
  on public.show_payment_sessions,
     public.show_payments,
     public.show_payment_events,
     public.show_payment_line_items,
     public.show_exhibitor_balances
  from anon, authenticated;

revoke execute on function public.protect_cart_balance_after_payment_attempt()
  from public, anon, authenticated;
revoke execute on function public.calculate_entry_cart_balance_internal(uuid)
  from public, anon, authenticated;
revoke execute on function public.create_payment_quote_attempt(
  uuid, uuid, text, numeric, numeric, integer
) from public, anon, authenticated;
revoke execute on function public.attach_provider_payment_session(
  uuid, text, text, text, timestamptz
) from public, anon, authenticated;
revoke execute on function public.mark_payment_attempt_terminal(
  uuid, text, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.record_payment_event(
  text, text, text, jsonb, uuid, text
) from public, anon, authenticated;
revoke execute on function public.set_payment_event_status(
  text, text, text, text, uuid, text
) from public, anon, authenticated;
revoke execute on function public.finalize_entry_cart_paid(
  uuid, uuid, text, text, integer, text
) from public, anon, authenticated;
revoke execute on function public.apply_show_payment_to_balance(uuid)
  from public, anon, authenticated;
revoke execute on function public.commit_entry_cart_paid(uuid)
  from public, anon, authenticated;

grant execute on function public.calculate_entry_cart_balance(uuid)
  to authenticated, service_role;
grant execute on function public.commit_entry_cart_day_of(uuid)
  to authenticated, service_role;

grant execute on function public.calculate_entry_cart_balance_internal(uuid),
  public.create_payment_quote_attempt(uuid, uuid, text, numeric, numeric, integer),
  public.attach_provider_payment_session(uuid, text, text, text, timestamptz),
  public.mark_payment_attempt_terminal(uuid, text, text, text, text, text),
  public.record_payment_event(text, text, text, jsonb, uuid, text),
  public.set_payment_event_status(text, text, text, text, uuid, text),
  public.finalize_entry_cart_paid(uuid, uuid, text, text, integer, text),
  public.apply_show_payment_to_balance(uuid),
  public.commit_entry_cart_paid(uuid)
  to service_role;
