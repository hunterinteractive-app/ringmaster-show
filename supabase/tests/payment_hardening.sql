-- Payment hardening regression suite.
-- Run against a disposable database after all migrations:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/payment_hardening.sql
-- Every fixture and assertion is rolled back.

begin;

create or replace function pg_temp.assert_true(value boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(value, false) then
    raise exception 'assertion failed: %', message;
  end if;
end;
$$;

create temporary table payment_test_context (
  owner_id uuid not null,
  other_id uuid not null,
  show_id uuid not null,
  cart_id uuid not null,
  day_show_id uuid not null,
  day_cart_id uuid not null,
  first_session_id uuid,
  active_session_id uuid
);

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_show uuid := gen_random_uuid();
  v_cart uuid := gen_random_uuid();
  v_day_show uuid := gen_random_uuid();
  v_day_cart uuid := gen_random_uuid();
  v_exhibitor uuid := gen_random_uuid();
  v_day_exhibitor uuid := gen_random_uuid();
  v_section uuid := gen_random_uuid();
  v_day_section uuid := gen_random_uuid();
begin
  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values
    (v_owner, 'authenticated', 'authenticated',
      'payment-owner-' || v_owner || '@example.invalid', '', now(),
      '{}'::jsonb, '{}'::jsonb, now(), now()),
    (v_other, 'authenticated', 'authenticated',
      'payment-other-' || v_other || '@example.invalid', '', now(),
      '{}'::jsonb, '{}'::jsonb, now(), now());

  insert into public.shows (
    id, created_by, name, start_date, end_date, entry_close_at,
    payment_timing_mode, platform_fee_percent, online_payment_fee_mode,
    is_test
  ) values
    (v_show, v_owner, 'Payment hardening test', current_date,
      current_date + 1, now() + interval '1 day', 'online_only', 2.00,
      'pass_to_exhibitor', true),
    (v_day_show, v_owner, 'Day-of hardening test', current_date,
      current_date + 1, now() + interval '1 day', 'pay_at_show_only', 2.00,
      'club_absorbs', true);

  insert into public.exhibitors (
    id, type, display_name, email, is_local_only, exhibitor_number,
    owner_user_id, created_for_show_id, is_test
  ) values
    (v_exhibitor, 'adult', 'Payment Test Exhibitor',
      'payment-exhibitor@example.invalid', true, 990001, v_owner, v_show, true),
    (v_day_exhibitor, 'adult', 'Day Test Exhibitor',
      'day-exhibitor@example.invalid', true, 990002, v_owner, v_day_show, true);

  insert into public.show_sections (
    id, show_id, kind, letter, display_name
  ) values
    (v_section, v_show, 'open', 'A', 'Open A'),
    (v_day_section, v_day_show, 'open', 'A', 'Open A');

  insert into public.show_fee_settings (show_id, currency)
  values (v_show, 'USD'), (v_day_show, 'USD');
  insert into public.show_section_fee_settings (
    section_id, fee_per_entry, fee_per_show, fur_fee
  ) values
    (v_section, 10.00, 2.00, 3.00),
    (v_day_section, 10.00, 2.00, 3.00)
  on conflict (section_id) do update set
    fee_per_entry = excluded.fee_per_entry,
    fee_per_show = excluded.fee_per_show,
    fur_fee = excluded.fur_fee;

  insert into public.show_payment_settings (
    show_id, stripe_enabled, square_enabled, paypal_enabled,
    default_online_provider
  ) values (v_show, true, false, false, 'stripe');
  insert into public.show_payment_account_links (
    show_id, provider, status, account_status, charges_enabled,
    stripe_account_id, provider_account_id
  ) values (
    v_show, 'stripe', 'active', 'ready', true,
    'acct_payment_hardening_test', 'acct_payment_hardening_test'
  );

  insert into public.entry_carts (id, user_id, show_id)
  values (v_cart, v_owner, v_show), (v_day_cart, v_owner, v_day_show);
  insert into public.entry_cart_items (
    cart_id, section_id, species, tattoo, breed, variety, sex,
    class_name, exhibitor_id, is_fur
  ) values
    (v_cart, v_section, 'rabbit', 'PAY-1', 'Test Breed', 'Test Variety',
      'Buck', 'Senior', v_exhibitor, true),
    (v_day_cart, v_day_section, 'rabbit', 'DAY-1', 'Test Breed',
      'Test Variety', 'Doe', 'Senior', v_day_exhibitor, false);

  insert into payment_test_context
  values (v_owner, v_other, v_show, v_cart, v_day_show, v_day_cart, null, null);
end;
$$;

-- Backend RPCs inspect this request claim even though the suite runs as a
-- database owner.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'service_role',
    'sub', (select owner_id from payment_test_context)
  )::text,
  true
);

-- 1. Duplicate webhook delivery is claimed once and replay-protected.
do $$
declare
  v_first jsonb;
  v_duplicate jsonb;
begin
  v_first := public.record_payment_event(
    'stripe', 'evt_payment_hardening', 'checkout.session.completed', '{}'::jsonb
  );
  perform pg_temp.assert_true((v_first ->> 'claimed')::boolean,
    'first event delivery must be claimed');
  perform public.set_payment_event_status(
    'stripe', 'evt_payment_hardening', 'processed'
  );
  v_duplicate := public.record_payment_event(
    'stripe', 'evt_payment_hardening', 'checkout.session.completed', '{}'::jsonb
  );
  perform pg_temp.assert_true((v_duplicate ->> 'duplicate')::boolean,
    'second event delivery must be a duplicate');
  perform pg_temp.assert_true(not (v_duplicate ->> 'claimed')::boolean,
    'processed duplicate must not be claimed');
end;
$$;

-- Create attempt 1, terminate it, then create the retry that will be paid.
do $$
declare
  v_ctx payment_test_context%rowtype;
  v_attempt jsonb;
begin
  select * into v_ctx from payment_test_context;
  v_attempt := public.create_payment_quote_attempt(
    v_ctx.cart_id, v_ctx.owner_id, 'stripe', 0.02, 0.029, 30
  );
  update payment_test_context
  set first_session_id = (v_attempt ->> 'payment_session_id')::uuid;
  perform public.mark_payment_attempt_terminal(
    (v_attempt ->> 'payment_session_id')::uuid,
    'stripe', 'failed', 'test_retry', 'Test retry'
  );
  v_attempt := public.create_payment_quote_attempt(
    v_ctx.cart_id, v_ctx.owner_id, 'stripe', 0.02, 0.029, 30
  );
  update payment_test_context
  set active_session_id = (v_attempt ->> 'payment_session_id')::uuid;
end;
$$;

-- 3. An old Stripe session cannot finalize after a newer retry.
do $$
declare v_ctx payment_test_context%rowtype;
begin
  select * into v_ctx from payment_test_context;
  begin
    perform public.finalize_entry_cart_paid(
      v_ctx.cart_id, v_ctx.first_session_id, 'stripe', 'pi_old',
      (select expected_amount_cents from public.show_payment_sessions
       where id = v_ctx.first_session_id), 'usd'
    );
    raise exception 'old attempt unexpectedly finalized';
  exception when others then
    if sqlerrm = 'old attempt unexpectedly finalized' then raise; end if;
  end;
end;
$$;

-- 4. Amount mismatch is rejected.
do $$
declare v_ctx payment_test_context%rowtype; v_expected integer;
begin
  select * into v_ctx from payment_test_context;
  select expected_amount_cents into v_expected
  from public.show_payment_sessions where id = v_ctx.active_session_id;
  begin
    perform public.finalize_entry_cart_paid(
      v_ctx.cart_id, v_ctx.active_session_id, 'stripe', 'pi_test',
      v_expected + 1, 'usd'
    );
    raise exception 'amount mismatch unexpectedly finalized';
  exception when others then
    if sqlerrm = 'amount mismatch unexpectedly finalized' then raise; end if;
  end;
end;
$$;

-- 5. Currency mismatch is rejected.
do $$
declare v_ctx payment_test_context%rowtype; v_expected integer;
begin
  select * into v_ctx from payment_test_context;
  select expected_amount_cents into v_expected
  from public.show_payment_sessions where id = v_ctx.active_session_id;
  begin
    perform public.finalize_entry_cart_paid(
      v_ctx.cart_id, v_ctx.active_session_id, 'stripe', 'pi_test',
      v_expected, 'eur'
    );
    raise exception 'currency mismatch unexpectedly finalized';
  exception when others then
    if sqlerrm = 'currency mismatch unexpectedly finalized' then raise; end if;
  end;
end;
$$;

-- 9. Recalculation after a pending attempt preserves quoted/payment state.
do $$
declare v_ctx payment_test_context%rowtype; v_before jsonb; v_after jsonb;
begin
  select * into v_ctx from payment_test_context;
  select to_jsonb(b) into v_before from public.show_exhibitor_balances b
  where entry_cart_id = v_ctx.cart_id;
  perform public.calculate_entry_cart_balance(v_ctx.cart_id);
  select to_jsonb(b) into v_after from public.show_exhibitor_balances b
  where entry_cart_id = v_ctx.cart_id;
  perform pg_temp.assert_true(
    v_before -> 'calculated_total_cents' = v_after -> 'calculated_total_cents'
    and v_before -> 'payment_status' = v_after -> 'payment_status'
    and v_before -> 'latest_show_payment_id' = v_after -> 'latest_show_payment_id',
    'pending recalculation changed protected financial state'
  );
end;
$$;

-- Finalize once so duplicate/exactly-once and paid recalculation can be tested.
do $$
declare v_ctx payment_test_context%rowtype; v_expected integer; v_result jsonb;
begin
  select * into v_ctx from payment_test_context;
  select expected_amount_cents into v_expected
  from public.show_payment_sessions where id = v_ctx.active_session_id;
  v_result := public.finalize_entry_cart_paid(
    v_ctx.cart_id, v_ctx.active_session_id, 'stripe', 'pi_payment_hardening',
    v_expected, 'usd'
  );
  perform pg_temp.assert_true((v_result ->> 'finalized')::boolean,
    'first finalization did not finalize');
end;
$$;

-- 2. The second finalization is stable and creates no duplicate entries.
-- Row locks plus entries_cart_item_kind_uidx provide the same invariant when
-- these two calls are issued concurrently from separate sessions.
do $$
declare
  v_ctx payment_test_context%rowtype;
  v_expected integer;
  v_before integer;
  v_after integer;
  v_result jsonb;
begin
  select * into v_ctx from payment_test_context;
  select expected_amount_cents into v_expected
  from public.show_payment_sessions where id = v_ctx.active_session_id;
  select count(*) into v_before from public.entries
  where source_cart_id = v_ctx.cart_id;
  v_result := public.finalize_entry_cart_paid(
    v_ctx.cart_id, v_ctx.active_session_id, 'stripe', 'pi_payment_hardening',
    v_expected, 'usd'
  );
  select count(*) into v_after from public.entries
  where source_cart_id = v_ctx.cart_id;
  perform pg_temp.assert_true((v_result ->> 'already_finalized')::boolean,
    'second finalization was not idempotent');
  perform pg_temp.assert_true(v_before = v_after,
    'second finalization inserted duplicate entries');
end;
$$;

-- 10. Recalculation after payment preserves paid state.
do $$
declare v_ctx payment_test_context%rowtype; v_paid integer; v_status text;
begin
  select * into v_ctx from payment_test_context;
  select paid_online_cents, payment_status into v_paid, v_status
  from public.show_exhibitor_balances where entry_cart_id = v_ctx.cart_id;
  perform public.calculate_entry_cart_balance(v_ctx.cart_id);
  perform pg_temp.assert_true(exists (
    select 1 from public.show_exhibitor_balances
    where entry_cart_id = v_ctx.cart_id
      and paid_online_cents = v_paid
      and payment_status = v_status
      and payment_status = 'paid'
  ), 'paid recalculation changed payment state');
end;
$$;

-- 6. A session with no matching pending ledger cannot finalize.
do $$
declare
  v_ctx payment_test_context%rowtype;
  v_empty_session uuid := gen_random_uuid();
begin
  select * into v_ctx from payment_test_context;
  insert into public.show_payment_sessions (
    id, show_id, cart_id, provider, status, currency, amount_cents,
    platform_fee_cents, metadata, attempt_status, expected_amount_cents,
    expected_currency
  ) values (
    v_empty_session, v_ctx.day_show_id, v_ctx.day_cart_id, 'stripe',
    'pending', 'usd', 100, 2, '{}'::jsonb, 'pending', 100, 'usd'
  );
  update public.entry_carts
  set active_payment_session_id = v_empty_session, payment_status = 'pending'
  where id = v_ctx.day_cart_id;
  begin
    perform public.finalize_entry_cart_paid(
      v_ctx.day_cart_id, v_empty_session, 'stripe', 'pi_empty', 100, 'usd'
    );
    raise exception 'empty ledger unexpectedly finalized';
  exception when others then
    if sqlerrm = 'empty ledger unexpectedly finalized' then raise; end if;
  end;
  perform public.mark_payment_attempt_terminal(
    v_empty_session, 'stripe', 'failed', 'test_cleanup', 'Test cleanup'
  );
end;
$$;

-- 7. Provider-neutral direct-payment helpers bind one client key and persist
-- an exact provider payment ID without exposing a second ledger path.
do $$
declare
  v_ctx payment_test_context%rowtype;
  v_session uuid := gen_random_uuid();
  v_claim jsonb;
begin
  select * into v_ctx from payment_test_context;
  insert into public.show_payment_sessions (
    id, show_id, cart_id, provider, status, currency, amount_cents,
    platform_fee_cents, metadata, attempt_status, expected_amount_cents,
    expected_currency
  ) values (
    v_session, v_ctx.day_show_id, v_ctx.day_cart_id, 'square', 'created',
    'usd', 100, 2, '{}'::jsonb, 'created', 100, 'usd'
  );
  v_claim := public.claim_payment_attempt_client_key(
    v_session, 'square', 'test-client-key-hash'
  );
  perform pg_temp.assert_true(
    (v_claim ->> 'payment_session_id')::uuid = v_session,
    'client attempt key claim returned the wrong session'
  );
  perform public.claim_payment_attempt_client_key(
    v_session, 'square', 'test-client-key-hash'
  );
  begin
    perform public.claim_payment_attempt_client_key(
      v_session, 'square', 'different-client-key-hash'
    );
    raise exception 'different client key unexpectedly claimed the attempt';
  exception when others then
    if sqlerrm = 'different client key unexpectedly claimed the attempt' then raise; end if;
  end;
  perform public.set_provider_payment_state(
    v_session, 'square', 'square_payment_test', 'PENDING'
  );
  perform pg_temp.assert_true((select provider_payment_id = 'square_payment_test'
    and attempt_status = 'processing' from public.show_payment_sessions
    where id = v_session), 'provider payment state was not persisted');
  perform public.mark_payment_attempt_terminal(
    v_session, 'square', 'failed', 'test_cleanup', 'Test cleanup',
    'square_payment_test'
  );
end;
$$;

-- 8. Repeated day-of-show submission is idempotent.
do $$
declare v_ctx payment_test_context%rowtype; v_first integer; v_second integer;
begin
  select * into v_ctx from payment_test_context;
  v_first := public.commit_entry_cart_day_of(v_ctx.day_cart_id);
  v_second := public.commit_entry_cart_day_of(v_ctx.day_cart_id);
  perform pg_temp.assert_true(v_first > 0, 'first day-of submit inserted nothing');
  perform pg_temp.assert_true(v_second = 0, 'repeated day-of submit was not idempotent');
end;
$$;

-- 9. Another authenticated user cannot calculate the owner's cart.
do $$
declare v_ctx payment_test_context%rowtype;
begin
  select * into v_ctx from payment_test_context;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'authenticated', 'sub', v_ctx.other_id)::text,
    true
  );
  begin
    perform public.calculate_entry_cart_balance(v_ctx.cart_id);
    raise exception 'unauthorized calculation unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role', 'sub', v_ctx.owner_id)::text,
    true
  );
end;
$$;

-- True two-session concurrency check (run these two statements at the same
-- time after replacing the psql variables with the active fixture IDs):
--   select finalize_entry_cart_paid(:cart_id, :session_id, 'stripe',
--     'pi_concurrent', :amount_cents, 'usd');
--   select finalize_entry_cart_paid(:cart_id, :session_id, 'stripe',
--     'pi_concurrent', :amount_cents, 'usd');
-- Both return successfully; exactly one reports already_finalized=false.

rollback;
