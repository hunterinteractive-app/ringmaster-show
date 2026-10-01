-- Payment hardening regression suite.
-- Run against a disposable database after all migrations:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/payment_hardening.sql
-- Every fixture and assertion is rolled back.

begin;

-- supabase test db executes SQL suites through pg_prove, so emit a proper
-- pgTAP plan/result while retaining the exception-based assertions below.
select no_plan();

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
      'Buck', 'Senior', v_exhibitor, false),
    (v_cart, v_section, 'rabbit', 'PAY-1', 'Test Breed', 'White',
      'Buck', 'Senior', v_exhibitor, true),
    (v_day_cart, v_day_section, 'rabbit', 'DAY-1', 'Test Breed',
      'White', 'Doe', 'Senior', v_day_exhibitor, true),
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


-- Submit day-of entries first, then enable online collection without rollback.
select public.commit_entry_cart_day_of(day_cart_id) from payment_test_context;
update public.shows set payment_timing_mode='online_only' where id=(select day_show_id from payment_test_context);
insert into public.show_payment_settings(show_id,stripe_enabled,default_online_provider)
select day_show_id,true,'stripe' from payment_test_context
on conflict(show_id) do update set stripe_enabled=true,default_online_provider='stripe';
insert into public.show_payment_account_links(show_id,provider,status,account_status,charges_enabled,stripe_account_id,provider_account_id)
select day_show_id,'stripe','active','ready',true,'acct_test','acct_test' from payment_test_context;
create temp table original_entries as select e.* from public.entries e join payment_test_context c on e.source_cart_id=c.day_cart_id;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select other_id from payment_test_context))::text,true);
select is((select jsonb_array_length(public.list_my_submitted_balances(day_show_id)) from payment_test_context),0,'unrelated household cannot list balances');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select owner_id from payment_test_context))::text,true);
select is((select jsonb_array_length(public.list_my_submitted_balances(day_show_id)) from payment_test_context),1,'owner can list unpaid submitted cart');
select set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',(select owner_id from payment_test_context))::text,true);
savepoint changed_entry;
update public.entries set scratched_at=now()+interval '2 days' where source_cart_id=(select day_cart_id from payment_test_context);
select throws_ok($t$select public.create_payment_quote_attempt(day_cart_id,owner_id,'stripe',0.02,0.029,30) from payment_test_context$t$,'P0001','This submission has changes or prior payments. Please contact the show secretary to confirm the remaining balance.','scratched entries require balance review');
rollback to savepoint changed_entry;
savepoint regular_scratch;
update public.entries set scratched_at=now(),status='scratched'
 where source_cart_id=(select day_cart_id from payment_test_context) and not is_fur;
select public.create_payment_quote_attempt(day_cart_id,owner_id,'stripe',0.02,0.029,30) from payment_test_context;
select is((select sum(balance_due_cents)::int from public.show_exhibitor_balances where entry_cart_id=(select day_cart_id from payment_test_context)),500,'pre-deadline regular scratch excluded; fur and show fee remain');
rollback to savepoint regular_scratch;
savepoint missing_scratch_time;
update public.entries set status='scratched',scratched_at=null where source_cart_id=(select day_cart_id from payment_test_context) and not is_fur;
select throws_ok($t$select checkout_private.validate_submitted_cart(day_cart_id) from payment_test_context$t$,'P0001','This submission has changes or prior payments. Please contact the show secretary to confirm the remaining balance.','unknown scratch time requires review');
rollback to savepoint missing_scratch_time;
-- A pre-deadline fur scratch is excluded from the fresh quote and payment.
savepoint eligible_scratch;
update public.entries set scratched_at=now(),status='scratched'
 where source_cart_id=(select day_cart_id from payment_test_context) and is_fur;
select lives_ok($t$select checkout_private.validate_submitted_cart(day_cart_id) from payment_test_context$t$,'pre-deadline scratch is eligible for checkout');
create temp table scratch_quote as select public.create_payment_quote_attempt(day_cart_id,owner_id,'stripe',0.02,0.029,30) q from payment_test_context;
select is((select sum(balance_due_cents)::int from public.show_exhibitor_balances where entry_cart_id=(select day_cart_id from payment_test_context)),1200,'fresh pricing excludes scratched fur and retains regular entry and show fee');
savepoint changed_after_quote;
update public.entries set scratched_at=now(),status='scratched' where source_cart_id=(select day_cart_id from payment_test_context) and not is_fur;
select throws_ok($t$select public.finalize_entry_cart_paid(day_cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_changed',(q->'quote'->>'expected_amount_cents')::int,q->'quote'->>'currency') from payment_test_context,scratch_quote$t$,'P0001',null,'scratch after quote cannot finalize stale payment');
rollback to savepoint changed_after_quote;
select is((select count(*)::int from public.entry_cart_items where cart_id=(select day_cart_id from payment_test_context)),2,'original cart items retained');
select public.finalize_entry_cart_paid(day_cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_scratch_test',(q->'quote'->>'expected_amount_cents')::int,q->'quote'->>'currency') from payment_test_context,scratch_quote;
select is((select count(*)::int from public.entries where source_cart_id=(select day_cart_id from payment_test_context) and payment_status='paid'),1,'only billable entry marked paid');
select is((select status from public.entries where source_cart_id=(select day_cart_id from payment_test_context) and is_fur),'scratched','scratch retained after payment');
rollback to savepoint eligible_scratch;
create temp table quote as select public.create_payment_quote_attempt(day_cart_id,owner_id,'stripe',0.02,0.029,30) q from payment_test_context;
select is((select status from public.entry_carts where id=(select day_cart_id from payment_test_context)),'submitted','checkout does not reopen the cart');
select is((select count(*)::int from original_entries),2,'fixture contains regular and fur entries');
select ok((select (q->'quote'->>'settles_submitted_entries')::boolean from quote),'quote identifies a balance-only payment');
select is((select public.create_payment_quote_attempt(day_cart_id,owner_id,'stripe',0.02,0.029,30)->>'payment_session_id' from payment_test_context),(select q->>'payment_session_id' from quote),'repeated checkout reuses identical attempt');
select throws_ok($t$select public.create_payment_quote_attempt(day_cart_id,other_id,'stripe',0.02,0.029,30) from payment_test_context$t$,'42501','You do not have access to this cart','unrelated account cannot pay or inspect submission');
select throws_ok($t$select public.finalize_entry_cart_paid(day_cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_test',1,'usd') from payment_test_context,quote$t$,'P0001','Charged amount does not match the saved quote','incorrect charged amount rejected');
select throws_ok($t$select public.finalize_entry_cart_paid(day_cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_test',(q->'quote'->>'expected_amount_cents')::int,'eur') from payment_test_context,quote$t$,'P0001','Charged currency does not match the saved quote','wrong currency rejected');
savepoint prior_payment;
select set_config('ringmaster.payment_state_write','on',true);
update public.show_exhibitor_balances set paid_manual_cents=100 where entry_cart_id=(select day_cart_id from payment_test_context);
select throws_ok($t$select public.finalize_entry_cart_paid(day_cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_test',(q->'quote'->>'expected_amount_cents')::int,q->'quote'->>'currency') from payment_test_context,quote$t$,'P0001','This submission has changes or prior payments. Please contact the show secretary to confirm the remaining balance.','intervening manual payment cannot be collected twice');
rollback to savepoint prior_payment;
select set_config('ringmaster.payment_state_write','on',true);
create temp table finalized as select public.finalize_entry_cart_paid(day_cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_test',(q->'quote'->>'expected_amount_cents')::int,q->'quote'->>'currency') r from payment_test_context,quote;
select is((select (r->>'entries_created')::int from finalized),0,'no entries created for balance payment');
select is((select count(*)::int from public.entries where source_cart_id=(select day_cart_id from payment_test_context)),2,'regular and fur entries are not duplicated');
select is((select count(*)::int from original_entries o join public.entries e using(id)),2,'original entry IDs retained');
select is((select count(*)::int from public.entries where source_cart_id=(select day_cart_id from payment_test_context) and payment_status='paid'),2,'existing entries marked paid');
select is((select sum(balance_due_cents)::int from public.show_exhibitor_balances where entry_cart_id=(select day_cart_id from payment_test_context)),0,'balance cleared');
select ok((select (public.finalize_entry_cart_paid(day_cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_test',(q->'quote'->>'expected_amount_cents')::int,q->'quote'->>'currency')->>'already_finalized')::boolean from payment_test_context,quote),'duplicate webhook is idempotent');
select * from finish();
rollback;
