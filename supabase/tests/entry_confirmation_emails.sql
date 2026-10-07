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



update public.shows set is_test=false,auto_email_checkin_sheets=true where id=(select day_show_id from payment_test_context);
select is((select count(*)::int from public.entry_confirmation_emails),0,'no historical backfill');
savepoint abandoned;
select public.commit_entry_cart_day_of(day_cart_id) from payment_test_context;
set constraints entry_cart_confirmation_after_submission immediate;
select is((select count(*)::int from public.entry_confirmation_emails),1,'submitted cart creates one confirmation');
rollback to savepoint abandoned;
select is((select count(*)::int from public.entry_confirmation_emails),0,'rollback leaves no confirmation');
select public.commit_entry_cart_day_of(day_cart_id) from payment_test_context;
set constraints entry_cart_confirmation_after_submission immediate;
select is((select status from public.entry_confirmation_emails),'pending','real submission is pending');
select is((select (snapshot->>'entry_count')::int from public.entry_confirmation_emails),2,'count includes regular and fur entries');
select is((select (snapshot->>'paid_cents')::int from public.entry_confirmation_emails),0,'pay at show paid zero');
select is((select (snapshot->>'balance_due_cents')::int from public.entry_confirmation_emails),1500,'pay at show balance includes fees');
select ok((select (snapshot->>'auto_checkin')::boolean from public.entry_confirmation_emails),'check-in setting captured');
select public.commit_entry_cart_day_of(day_cart_id) from payment_test_context;
select is((select count(*)::int from public.entry_confirmation_emails),1,'resubmission does not duplicate');
select is((select snapshot->>'to' from public.entry_confirmation_emails),(select email::text from auth.users where id=(select owner_id from payment_test_context)),'confirmation goes to checkout account');
select ok(not has_table_privilege('authenticated','public.entry_confirmation_emails','SELECT'),'other users cannot read email queue');
select ok(not has_function_privilege('authenticated','public.claim_entry_confirmation_emails(uuid)','EXECUTE'),'only backend can claim mail');
create temp table claimed as select * from public.claim_entry_confirmation_emails('00000000-0000-0000-0000-000000000001');
select is((select count(*)::int from claimed),1,'worker claims pending confirmation');
select is((select count(*)::int from public.claim_entry_confirmation_emails(gen_random_uuid())),0,'concurrent worker cannot claim leased confirmation');
update public.entry_confirmation_emails set first_attempt_at=now()-interval '24 hours',lease_until=now()-interval '1 minute';
select count(*) from public.claim_entry_confirmation_emails(gen_random_uuid());
select is((select status from public.entry_confirmation_emails),'blocked','stop retrying before provider idempotency expires');
-- An online cart must not confirm while its payment is still pending.
savepoint premature;
update public.entry_carts set status='submitted',selected_payment_timing='online',payment_status='pending' where id=(select cart_id from payment_test_context);
set constraints entry_cart_confirmation_after_submission immediate;
select is((select count(*)::int from public.entry_confirmation_emails),1,'pending online payment sends no confirmation');
rollback to savepoint premature;
update public.shows set is_test=false,auto_email_checkin_sheets=false where id=(select show_id from payment_test_context);
create temp table online_quote as select public.create_payment_quote_attempt(cart_id,owner_id,'stripe',0.02,0.029,30) q from payment_test_context;
select public.finalize_entry_cart_paid(cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_confirm_test',(q->'quote'->>'expected_amount_cents')::int,q->'quote'->>'currency') from payment_test_context,online_quote;
set constraints entry_cart_confirmation_after_submission immediate;
select is((select status from public.entry_confirmation_emails where cart_id=(select cart_id from payment_test_context)),'pending','confirmed online payment queues email');
select is((select (snapshot->>'paid_cents')::int from public.entry_confirmation_emails where cart_id=(select cart_id from payment_test_context)),(select (q->'quote'->>'expected_amount_cents')::int from online_quote),'paid amount includes actual checkout fees');
select is((select (snapshot->>'balance_due_cents')::int from public.entry_confirmation_emails where cart_id=(select cart_id from payment_test_context)),0,'paid checkout owes zero');
select ok(not (select (snapshot->>'auto_checkin')::boolean from public.entry_confirmation_emails where cart_id=(select cart_id from payment_test_context)),'disabled check-in setting captured');
select public.finalize_entry_cart_paid(cart_id,(q->>'payment_session_id')::uuid,'stripe','pi_confirm_test',(q->'quote'->>'expected_amount_cents')::int,q->'quote'->>'currency') from payment_test_context,online_quote;
select is((select count(*)::int from public.entry_confirmation_emails),2,'duplicate payment callback does not duplicate confirmation');
select is((select sum((line->>'amount_cents')::int)::int from public.entry_confirmation_emails q cross join lateral jsonb_array_elements(q.snapshot->'charges') line where q.cart_id=(select cart_id from payment_test_context)),(select (q->'quote'->>'expected_amount_cents')::int from online_quote),'paid breakdown reconciles to charged total');
select is((select sum((line->>'amount_cents')::int)::int from public.entry_confirmation_emails q cross join lateral jsonb_array_elements(q.snapshot->'charges') line where q.cart_id=(select day_cart_id from payment_test_context)),1500,'pay at show breakdown reconciles');
select ok(not exists(select 1 from public.entry_confirmation_emails q cross join lateral jsonb_array_elements(q.snapshot->'charges') line where (line->>'amount_cents')::int=0),'zero fees omitted');
select * from finish();
rollback;
