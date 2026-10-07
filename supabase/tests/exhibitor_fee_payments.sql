-- One-time fee payment integration; all fixtures roll back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;

-- supabase test db executes SQL suites through pg_prove, so emit a proper
-- pgTAP plan/result while retaining the exception-based assertions below.
select plan(1);

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
    (v_cart, v_section, 'rabbit', 'PAY-1', 'Dutch', 'Test Variety',
      'Buck', 'Senior', v_exhibitor, false),
    (v_cart, v_section, 'rabbit', 'PAY-1', 'Dutch', 'White',
      'Buck', 'Senior', v_exhibitor, true),
    (v_day_cart, v_day_section, 'rabbit', 'DAY-1', 'Dutch',
      'White', 'Doe', 'Senior', v_day_exhibitor, true),
    (v_day_cart, v_day_section, 'rabbit', 'DAY-1', 'Dutch',
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

update public.show_fee_settings set exhibitor_fee_enabled=true,exhibitor_fee_label='Facility Fee',exhibitor_fee_amount=7.50
where show_id=(select show_id from payment_test_context);
do $$
declare c payment_test_context%rowtype; q jsonb; sid uuid; b public.show_exhibitor_balances%rowtype; ex uuid; sec uuid; fee_cart uuid; due integer; n integer;
begin
 select * into c from payment_test_context;
 q:=public.create_payment_quote_attempt(c.cart_id,c.owner_id,'stripe',0.02,0.029,30);
 sid:=(q->>'payment_session_id')::uuid;
 select * into b from public.show_exhibitor_balances where entry_cart_id=c.cart_id;
 perform pg_temp.assert_true(b.calculated_total_cents=2250,'entry, fur, section, and exhibitor fee total must be 2250');
 perform pg_temp.assert_true((select sum(total_amount_cents)=750 from public.show_payment_line_items where payment_session_id=sid and label='Facility Fee'),'receipt itemizes custom fee once');
 perform pg_temp.assert_true((select sum(total_amount_cents)=200 from public.show_payment_line_items where payment_session_id=sid and label='Per-show fees'),'ordinary section fee excludes the new fee');
 perform pg_temp.assert_true((select sum(total_amount_cents)=(select expected_amount_cents from public.show_payment_sessions where id=sid) from public.show_payment_line_items where payment_session_id=sid and line_type<>'platform_fee'),'receipt lines reconcile to amount collected');
 perform public.calculate_entry_cart_balance(c.cart_id);
 perform pg_temp.assert_true((select calculated_total_cents=2250 and (fee_snapshot->>'exhibitor_fee_cents')::int=750 from public.show_exhibitor_balances where entry_cart_id=c.cart_id),'pending quote retains exactly one fee');
 -- A newly added exhibitor must be fully priced, including their one-time fee.
 select exhibitor_id into ex from public.entry_cart_items where cart_id=c.day_cart_id limit 1;
 select section_id into sec from public.entry_cart_items where cart_id=c.cart_id limit 1;
 insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name)
 values(c.cart_id,sec,ex,'rabbit','LATE-EX','Test Breed','Test Variety','Buck','Senior');
 q:=public.create_payment_quote_attempt(c.cart_id,c.owner_id,'stripe',0.02,0.029,30);
 perform pg_temp.assert_true((q->'quote'->>'show_balance_total_cents')::int=4200,
   'late exhibitor must add entry, section fee, and one-time fee');
 delete from public.entry_cart_items where cart_id=c.cart_id and tattoo='LATE-EX';
 q:=public.create_payment_quote_attempt(c.cart_id,c.owner_id,'stripe',0.02,0.029,30);
 perform pg_temp.assert_true((q->'quote'->>'show_balance_total_cents')::int=2250,
   'removed exhibitor balance must not remain in checkout');
 sid:=(q->>'payment_session_id')::uuid;
 -- Drop only this temporary test fee assessment so the later secretary-entry
 -- fixture can exercise the existing fresh fee-only cart path.
 delete from exhibitor_fees_private.charges where show_id=c.show_id and exhibitor_id=ex;
 select expected_amount_cents into due from public.show_payment_sessions where id=sid;
 perform public.finalize_entry_cart_paid(c.cart_id,sid,'stripe','pi_exhibitor_fee',due,'usd');
 perform public.finalize_entry_cart_paid(c.cart_id,sid,'stripe','pi_exhibitor_fee',due,'usd');
 perform public.calculate_entry_cart_balance(c.cart_id);
 perform pg_temp.assert_true((select paid_online_cents=2250 and balance_due_cents=0 from public.show_exhibitor_balances where entry_cart_id=c.cart_id and exhibitor_id in (select exhibitor_id from public.entry_cart_items where cart_id=c.cart_id)),'paid fee remains paid after retry and recalculation');
 perform pg_temp.assert_true((select count(*)=2 from public.entries where source_cart_id=c.cart_id),'one regular animal and fur result, with no fee entry');
 -- A secretary-entered exhibitor gets a separate fee-only cart that can also be paid online.
 select exhibitor_id into ex from public.entry_cart_items where cart_id=c.day_cart_id limit 1;
 select section_id into sec from public.entry_cart_items where cart_id=c.cart_id limit 1;
 insert into public.entries(show_id,section_id,exhibitor_id,exhibitor_user_id,species,breed,tattoo)
 values(c.show_id,sec,ex,c.owner_id,'rabbit','Dutch','MANUAL-FEE');
 select cart_id into fee_cart from exhibitor_fees_private.charges where show_id=c.show_id and exhibitor_id=ex;
 q:=public.create_payment_quote_attempt(fee_cart,c.owner_id,'stripe',0.02,0.029,30);
 sid:=(q->>'payment_session_id')::uuid;
 select * into b from public.show_exhibitor_balances where entry_cart_id=fee_cart;
 perform pg_temp.assert_true(b.calculated_total_cents=750 and b.entry_count=0 and b.entries_subtotal_cents=0,'fee-only checkout contains no animal or section fee');
 perform pg_temp.assert_true((select count(*)=1 from public.show_payment_line_items where payment_session_id=sid and line_type='per_show_fee' and label='Facility Fee' and total_amount_cents=750),'fee-only receipt shows the custom name and correct amount');
 select count(*) into n from public.entries where show_id=c.show_id;
 select expected_amount_cents into due from public.show_payment_sessions where id=sid;
 perform public.finalize_entry_cart_paid(fee_cart,sid,'stripe','pi_exhibitor_fee_only',due,'usd');
 perform pg_temp.assert_true((select count(*)=n from public.entries where show_id=c.show_id),'paying only the exhibitor fee creates no extra animal');
 perform pg_temp.assert_true((select balance_due_cents=0 from public.show_exhibitor_balances where entry_cart_id=fee_cart),'fee-only balance is fully paid');
end;
$$;
select pass('custom fee receipts, payment totals, retries, and fee-only checkout');
rollback;
