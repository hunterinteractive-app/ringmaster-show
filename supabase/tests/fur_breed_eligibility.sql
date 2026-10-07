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

create temp table fur_test_ids as select id, is_fur from public.entries
 where source_cart_id=(select day_cart_id from payment_test_context);
select is((select blocked_reason from public.report_fur_breed_eligibility(
 (select day_show_id from payment_test_context),array[(select id from fur_test_ids where is_fur)])),
 'Record the breed judging result first.','unjudged breed blocks fur');
select throws_ok($t$update public.entries set result_status='Shown',fur_placement=1 where id=(select id from fur_test_ids where is_fur)$t$,
 'P0001','Fur / Wool result cannot be saved: Record the breed judging result first.','API cannot place unjudged fur');
update public.entries set result_status='Shown',is_shown=true,placement=1 where id=(select id from fur_test_ids where not is_fur);
select lives_ok($t$update public.entries set result_status='Shown',fur_placement=1 where id=(select id from fur_test_ids where is_fur)$t$,'eligible fur can be placed');
update public.entries set result_status='Disqualified - Overweight',is_disqualified=true,disqualified_reason='Overweight',placement=null where id=(select id from fur_test_ids where not is_fur);
select is((select blocked_reason from public.report_fur_breed_eligibility(
 (select day_show_id from payment_test_context),array[(select id from fur_test_ids where is_fur)])),
 'Breed entry disqualified: Overweight','breed DQ flags existing fur without rewriting historical result');
select lives_ok($t$update public.entries set paid_at=now() where id=(select id from fur_test_ids where is_fur)$t$,'historical fur issue does not block payment bookkeeping');
select throws_ok($t$update public.entries set fur_placement=2 where id=(select id from fur_test_ids where is_fur)$t$,
 'P0001','Fur / Wool result cannot be saved: Breed entry disqualified: Overweight','DQ blocks new fur placement');
select lives_ok($t$update public.entries set result_status='Disqualified - Overweight',fur_placement=null,is_disqualified=true where id=(select id from fur_test_ids where is_fur)$t$,'writer may record fur DQ');
update public.entries set result_status='No Show',is_disqualified=false,is_shown=false where id=(select id from fur_test_ids where not is_fur);
select throws_ok($t$update public.entries set result_status='Shown',fur_placement=1 where id=(select id from fur_test_ids where is_fur)$t$,
 'P0001','Fur / Wool result cannot be saved: The animal did not show in its breed class.','No Show blocks fur');
update public.entries set scratched_at=now() where id=(select id from fur_test_ids where not is_fur);
select is((select blocked_reason from public.report_fur_breed_eligibility(
 (select day_show_id from payment_test_context),array[(select id from fur_test_ids where is_fur)])),
 'The breed entry is scratched.','scratch blocks fur');
update public.entries set animal_id=null where id=(select id from fur_test_ids where not is_fur);
select is((select blocked_reason from public.report_fur_breed_eligibility(
 (select day_show_id from payment_test_context),array[(select id from fur_test_ids where is_fur)])),
 'No matching breed entry in this show section.','tattoo alone never matches an unrelated animal');
select ok(not has_function_privilege('anon','public.report_fur_breed_eligibility(uuid,uuid[])','EXECUTE'),'anonymous cannot query eligibility');
select ok(not has_function_privilege('authenticated','checkout_private.guard_fur_result_eligibility()','EXECUTE'),'write guard cannot be called directly');
grant select on payment_test_context,fur_test_ids to authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select owner_id from payment_test_context))::text,true);
set local role authenticated;
select is((select count(*)::int from public.report_fur_breed_eligibility(
 (select day_show_id from payment_test_context),array[(select id from fur_test_ids where is_fur)])),1,'authorized secretary can see eligibility through RLS');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select other_id from payment_test_context))::text,true);
set local role authenticated;
select is((select count(*)::int from public.report_fur_breed_eligibility(
 (select day_show_id from payment_test_context),array[(select id from fur_test_ids where is_fur)])),0,'unrelated user cannot see eligibility');
reset role;
select * from finish();
rollback;
