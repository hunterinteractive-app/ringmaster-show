-- Canada Special regression suite.
-- Run against a disposable database after all migrations. Every fixture is
-- rolled back.

begin;

select plan(8);

create temporary table canada_special_test_context (
  show_id uuid not null,
  cart_id uuid not null,
  canadian_exhibitor_id uuid not null,
  us_exhibitor_id uuid not null
);

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_show uuid := gen_random_uuid();
  v_cart uuid := gen_random_uuid();
  v_section uuid := gen_random_uuid();
  v_canadian uuid := gen_random_uuid();
  v_us uuid := gen_random_uuid();
begin
  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    v_owner, 'authenticated', 'authenticated',
    'canada-special-' || v_owner || '@example.invalid', '', now(),
    '{}'::jsonb, '{}'::jsonb, now(), now()
  );

  insert into public.shows (
    id, created_by, name, start_date, end_date, entry_close_at, is_test
  ) values (
    v_show, v_owner, 'Canada Special test', current_date,
    current_date + 1, now() + interval '1 day', true
  );

  insert into public.show_sections (
    id, show_id, kind, letter, display_name
  ) values (v_section, v_show, 'open', 'A', 'Open A');

  insert into public.show_fee_settings (
    show_id, currency,
    multi_show_discount_enabled, multi_show_discount_type,
    multi_show_discount_value, multi_show_discount_basis,
    multi_show_discount_scope, multi_show_discount_min_entries,
    multi_show_discount_required_shows,
    canada_special_discount_enabled, canada_special_discount_type,
    canada_special_discount_value, canada_special_discount_scope
  ) values (
    v_show, 'USD',
    true, 'amount', 1, 'each_show', 'both', 1, 1,
    true, 'amount', 3, 'both'
  );

  insert into public.show_section_fee_settings (
    section_id, fee_per_entry, fee_per_show, fur_fee
  ) values (v_section, 10, 0, 0);

  insert into public.exhibitors (
    id, owner_user_id, type, display_name, state, zip, is_active,
    is_local_only, created_for_show_id, is_test
  ) values
    (v_canadian, v_owner, 'adult', 'Canadian Exhibitor', 'ON', 'K1A 0B1',
      true, true, v_show, true),
    (v_us, v_owner, 'adult', 'US Exhibitor', 'IN', '46204',
      true, true, v_show, true);

  insert into public.entry_carts (id, user_id, show_id)
  values (v_cart, v_owner, v_show);

  insert into public.entry_cart_items (
    cart_id, section_id, species, tattoo, breed, variety, sex,
    class_name, exhibitor_id, is_fur
  ) values
    (v_cart, v_section, 'rabbit', 'CAN-1', 'Test Breed', 'Test Variety',
      'Buck', 'Senior', v_canadian, false),
    (v_cart, v_section, 'rabbit', 'USA-1', 'Test Breed', 'Test Variety',
      'Doe', 'Senior', v_us, false);

  insert into canada_special_test_context
  values (v_show, v_cart, v_canadian, v_us);

  perform 1
  from public.calculate_entry_cart_balance_internal(v_cart);
end;
$$;

select ok(
  public.is_canadian_exhibitor_address('Ontario', null),
  'province names identify Canadian exhibitors'
);
select ok(
  public.is_canadian_exhibitor_address(null, 'V6B 1A1'),
  'postal codes identify Canadian exhibitors'
);
select ok(
  not public.is_canadian_exhibitor_address('CA', '90210'),
  'US addresses are not mistaken for Canada'
);

select is(
  (
    select discount_cents
    from public.show_exhibitor_balances
    where entry_cart_id = (select cart_id from canada_special_test_context)
      and exhibitor_id = (
        select canadian_exhibitor_id from canada_special_test_context
      )
  ),
  300,
  'Canadian exhibitor receives the better Canada Special discount'
);
select is(
  (
    select discount_cents
    from public.show_exhibitor_balances
    where entry_cart_id = (select cart_id from canada_special_test_context)
      and exhibitor_id = (select us_exhibitor_id from canada_special_test_context)
  ),
  100,
  'non-Canadian exhibitor receives only the volume discount'
);
select is(
  (
    select fee_snapshot ->> 'applied_discount'
    from public.show_exhibitor_balances
    where entry_cart_id = (select cart_id from canada_special_test_context)
      and exhibitor_id = (
        select canadian_exhibitor_id from canada_special_test_context
      )
  ),
  'special',
  'balance snapshot records that the special discount won'
);

update public.show_fee_settings
set canada_special_discount_value = 0.50
where show_id = (select show_id from canada_special_test_context);

do $$
begin
  perform 1
  from public.calculate_entry_cart_balance_internal(
    (select cart_id from canada_special_test_context)
  );
end;
$$;

select is(
  (
    select discount_cents
    from public.show_exhibitor_balances
    where entry_cart_id = (select cart_id from canada_special_test_context)
      and exhibitor_id = (
        select canadian_exhibitor_id from canada_special_test_context
      )
  ),
  100,
  'volume discount wins when it is better than Canada Special'
);
select is(
  (
    select fee_snapshot ->> 'applied_discount'
    from public.show_exhibitor_balances
    where entry_cart_id = (select cart_id from canada_special_test_context)
      and exhibitor_id = (
        select canadian_exhibitor_id from canada_special_test_context
      )
  ),
  'volume',
  'balance snapshot records that the volume discount won'
);

select * from finish();

rollback;
