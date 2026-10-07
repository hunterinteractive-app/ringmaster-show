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
  v_day_show uuid := '2f3246f9-7174-4ce8-a4fd-9ae80cbcf35f';
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

update public.entries set result_status='No Show',is_shown=false where source_cart_id=(select day_cart_id from payment_test_context) and not is_fur;
set constraints all immediate;
alter table public.entries disable trigger require_matching_cart_entry_kind;
insert into public.entries(id,show_id,exhibitor_id,section_id,species,breed,variety,tattoo,sex,class_name,is_fur,source_cart_id,source_cart_item_id,animal_id,result_status,is_shown)
 select 'cc49b1f3-eb48-47e2-a02f-44b23f5679a4',c.day_show_id,i.exhibitor_id,i.section_id,i.species,i.breed,i.variety,i.tattoo,i.sex,i.class_name,false,i.cart_id,i.id,'00000000-0000-4000-8000-000000000091','No Show',false from public.entry_cart_items i join payment_test_context c on c.day_cart_id=i.cart_id where i.is_fur;
set constraints all immediate;
alter table public.entries enable trigger require_matching_cart_entry_kind;
create temp table retained_entries as select id,to_jsonb(e) snapshot from public.entries e where source_cart_id=(select day_cart_id from payment_test_context) and id<>'cc49b1f3-eb48-47e2-a02f-44b23f5679a4';
do $$
declare e public.entries; candidate uuid;
begin
 foreach candidate in array array[
   'cc49b1f3-eb48-47e2-a02f-44b23f5679a4'::uuid,
   '05714113-f7f4-471f-87c3-6938a88b8377'::uuid
 ] loop
   select * into e from public.entries where id=candidate for update;
   if not found then continue; end if;
   if e.show_id<>'2f3246f9-7174-4ce8-a4fd-9ae80cbcf35f'::uuid
     or coalesce(e.is_fur,false) or e.result_status is distinct from 'No Show'
     or e.placement is not null or e.fur_placement is not null
     or nullif(to_jsonb(e)->>'special_awards','') is not null
     or nullif(to_jsonb(e)->>'fur_award','') is not null
     or checkout_private.entry_has_references(e.id)
     or exists(select 1 from entry_refunds_private.entries where entry_id=e.id)
     or exists(select 1 from public.shows where id=e.show_id and is_locked)
     or not exists(select 1 from public.entry_cart_items i where i.id=e.source_cart_item_id and i.cart_id=e.source_cart_id and i.is_fur)
     or not exists(select 1 from public.entries f where f.is_fur and f.source_cart_item_id=e.source_cart_item_id and f.source_cart_id=e.source_cart_id)
     or not exists(select 1 from public.entries r join public.entry_cart_items i on i.id=r.source_cart_item_id and i.cart_id=r.source_cart_id
       where r.show_id=e.show_id and r.section_id=e.section_id and r.animal_id=e.animal_id
       and r.exhibitor_id=e.exhibitor_id and r.source_cart_id=e.source_cart_id and not coalesce(r.is_fur,false)
       and not coalesce(i.is_fur,false) and r.result_status='No Show')
   then raise exception 'Oregon duplicate % changed since review; inspect before cleanup',candidate; end if;
   insert into checkout_private.fur_duplicate_audit(entry_id,entry_snapshot,disposition)
   values(e.id,to_jsonb(e),'removed_reviewed_no_show_duplicate')
   on conflict(entry_id) do update set disposition=excluded.disposition,reviewed_at=now();
   delete from public.entries where id=e.id;
 end loop;
end $$;

select is((select count(*)::int from public.entries where id='cc49b1f3-eb48-47e2-a02f-44b23f5679a4'),0,'reviewed No Show duplicate removed');
select is((select disposition from checkout_private.fur_duplicate_audit where entry_id='cc49b1f3-eb48-47e2-a02f-44b23f5679a4'),'removed_reviewed_no_show_duplicate','complete evidence archived');
select is((select count(*)::int from retained_entries r join public.entries e on e.id=r.id and to_jsonb(e)=r.snapshot),2,'legitimate breed and fur results unchanged');
do $$
declare e public.entries; candidate uuid;
begin
 foreach candidate in array array[
   'cc49b1f3-eb48-47e2-a02f-44b23f5679a4'::uuid,
   '05714113-f7f4-471f-87c3-6938a88b8377'::uuid
 ] loop
   select * into e from public.entries where id=candidate for update;
   if not found then continue; end if;
   if e.show_id<>'2f3246f9-7174-4ce8-a4fd-9ae80cbcf35f'::uuid
     or coalesce(e.is_fur,false) or e.result_status is distinct from 'No Show'
     or e.placement is not null or e.fur_placement is not null
     or nullif(to_jsonb(e)->>'special_awards','') is not null
     or nullif(to_jsonb(e)->>'fur_award','') is not null
     or checkout_private.entry_has_references(e.id)
     or exists(select 1 from entry_refunds_private.entries where entry_id=e.id)
     or exists(select 1 from public.shows where id=e.show_id and is_locked)
     or not exists(select 1 from public.entry_cart_items i where i.id=e.source_cart_item_id and i.cart_id=e.source_cart_id and i.is_fur)
     or not exists(select 1 from public.entries f where f.is_fur and f.source_cart_item_id=e.source_cart_item_id and f.source_cart_id=e.source_cart_id)
     or not exists(select 1 from public.entries r join public.entry_cart_items i on i.id=r.source_cart_item_id and i.cart_id=r.source_cart_id
       where r.show_id=e.show_id and r.section_id=e.section_id and r.animal_id=e.animal_id
       and r.exhibitor_id=e.exhibitor_id and r.source_cart_id=e.source_cart_id and not coalesce(r.is_fur,false)
       and not coalesce(i.is_fur,false) and r.result_status='No Show')
   then raise exception 'Oregon duplicate % changed since review; inspect before cleanup',candidate; end if;
   insert into checkout_private.fur_duplicate_audit(entry_id,entry_snapshot,disposition)
   values(e.id,to_jsonb(e),'removed_reviewed_no_show_duplicate')
   on conflict(entry_id) do update set disposition=excluded.disposition,reviewed_at=now();
   delete from public.entries where id=e.id;
 end loop;
end $$;
select is((select count(*)::int from public.entries where source_cart_id=(select day_cart_id from payment_test_context)),2,'cleanup is idempotent');
select * from finish();
rollback;
