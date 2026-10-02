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


select public.commit_entry_cart_day_of(day_cart_id) from payment_test_context;
-- Fixtures have no animal record; create one to test identity-based duplicate repair.
insert into public.animals(id,owner_user_id,species,breed,tattoo) select '00000000-0000-4000-8000-000000000091',owner_id,'rabbit','Test Breed','DAY-1' from payment_test_context;
update public.entries set animal_id='00000000-0000-4000-8000-000000000091' where source_cart_id=(select day_cart_id from payment_test_context);
create temp table before_balances as select to_jsonb(b) row from public.show_exhibitor_balances b where entry_cart_id=(select day_cart_id from payment_test_context);
select throws_ok($t$insert into public.entries(show_id,exhibitor_id,section_id,species,breed,variety,tattoo,sex,class_name,is_fur,source_cart_id,source_cart_item_id,animal_id)
 select c.day_show_id,i.exhibitor_id,i.section_id,i.species,i.breed,i.variety,i.tattoo,i.sex,i.class_name,false,i.cart_id,i.id,'00000000-0000-4000-8000-000000000091' from public.entry_cart_items i join payment_test_context c on c.day_cart_id=i.cart_id where i.is_fur$t$,'P0001','A fur cart item cannot create a regular breed entry.','future duplicate is rejected');
alter table public.entries disable trigger require_matching_cart_entry_kind;
insert into public.entries(show_id,exhibitor_id,section_id,species,breed,variety,tattoo,sex,class_name,is_fur,source_cart_id,source_cart_item_id,animal_id)
 select c.day_show_id,i.exhibitor_id,i.section_id,i.species,i.breed,i.variety,i.tattoo,i.sex,i.class_name,false,i.cart_id,i.id,'00000000-0000-4000-8000-000000000091' from public.entry_cart_items i join payment_test_context c on c.day_cart_id=i.cart_id where i.is_fur;
alter table public.entries enable trigger require_matching_cart_entry_kind;
savepoint historical_result;
update public.entries set placement=1 where source_cart_id=(select day_cart_id from payment_test_context) and not is_fur and variety='White';
select is(checkout_private.repair_fur_duplicates(),0,'judged duplicate is preserved for review');
rollback to savepoint historical_result;
select is(checkout_private.repair_fur_duplicates(),1,'one proven duplicate removed');
select is((select count(*)::int from public.entries where source_cart_id=(select day_cart_id from payment_test_context)),2,'legitimate breed and fur rows preserved');
select is((select count(*)::int from checkout_private.fur_duplicate_audit where disposition='removed_confirmed_duplicate'),1,'removed row is archived');
select is(checkout_private.repair_fur_duplicates(),0,'repair is idempotent');
select ok(not exists(select to_jsonb(b) from public.show_exhibitor_balances b where entry_cart_id=(select day_cart_id from payment_test_context) except select row from before_balances),'payment balances unchanged');
select * from finish();
rollback;
