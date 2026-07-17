-- Isolated compile/contract fixture. Run the migration under test after this
-- file, then run closeout_scoped_financial_balances_test.sql.
create schema if not exists auth;
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end $$;

create or replace function auth.jwt()
returns jsonb language sql stable
as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;
create or replace function auth.uid()
returns uuid language sql stable
as $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;

create table public.shows (id uuid primary key);
create table public.show_sections (
  id uuid primary key,
  show_id uuid not null references public.shows(id),
  is_enabled boolean not null default true
);
create table public.legacy_balance_fixture (value jsonb not null);
create table public.exhibitors (
  id uuid primary key,
  exhibitor_user_id uuid,
  display_name text,
  showing_name text,
  first_name text,
  last_name text,
  type text,
  phone text,
  email text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  zip text,
  arba_number text
);
create table public.show_exhibitor_balances (
  id uuid primary key,
  show_id uuid not null references public.shows(id),
  exhibitor_id uuid not null references public.exhibitors(id),
  entry_count integer not null default 0,
  fur_count integer not null default 0,
  entries_subtotal_cents integer not null default 0,
  fur_subtotal_cents integer not null default 0,
  show_fee_subtotal_cents integer not null default 0,
  subtotal_before_discount_cents integer not null default 0,
  discount_cents integer not null default 0,
  calculated_total_cents integer not null default 0,
  paid_online_cents integer not null default 0,
  paid_manual_cents integer not null default 0,
  refunded_cents integer not null default 0,
  balance_due_cents integer not null default 0,
  payment_status text,
  source text,
  section_breakdown jsonb not null default '[]'::jsonb
);

create or replace function public.user_can_manage_entries(uuid)
returns boolean language sql stable as $$ select false $$;
create or replace function public.user_can_manage_show_settings(uuid)
returns boolean language sql stable as $$ select false $$;
create or replace function public.report_show_exhibitor_balances(uuid)
returns setof jsonb language sql stable
as $$ select value from public.legacy_balance_fixture $$;

insert into public.shows values ('10000000-0000-0000-0000-000000000001');
insert into public.show_sections values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', true),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', true),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', false);

insert into public.exhibitors (id, display_name)
values ('40000000-0000-0000-0000-000000000001', 'Read Only Exhibitor');

insert into public.show_exhibitor_balances (
  id, show_id, exhibitor_id, entry_count, entries_subtotal_cents,
  show_fee_subtotal_cents, subtotal_before_discount_cents,
  calculated_total_cents, balance_due_cents, payment_status,
  source, section_breakdown
) values (
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  2, 2000, 400, 2400, 2400, 2400, 'unpaid', 'cart',
  jsonb_build_array(jsonb_build_object(
    'section_id', '20000000-0000-0000-0000-000000000001',
    'kind', 'open', 'letter', 'A', 'label', 'Rabbit Open A',
    'entry_count', 2, 'fur_count', 0,
    'entries_subtotal_cents', 2000, 'fur_subtotal_cents', 0,
    'show_fee_cents', 400
  ))
);

insert into public.show_exhibitor_balances (
  id, show_id, exhibitor_id, entry_count, entries_subtotal_cents,
  show_fee_subtotal_cents, subtotal_before_discount_cents,
  calculated_total_cents, balance_due_cents, payment_status,
  source, section_breakdown
) values (
  '30000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  3, 3000, 400, 3400, 3400, 3400, 'unpaid', 'entries',
  jsonb_build_array(jsonb_build_object(
    'section_id', '20000000-0000-0000-0000-000000000001',
    'kind', 'open', 'letter', 'A', 'label', 'Rabbit Open A',
    'entry_count', 3, 'fur_count', 0,
    'entries_subtotal_cents', 3000, 'fur_subtotal_cents', 0,
    'show_fee_cents', 400
  ))
);

select set_config('request.jwt.claims', '{"role":"service_role"}', false);
