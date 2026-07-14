-- Isolated compile/contract fixture. Run the migration under test after this
-- file, then run closeout_scoped_financial_balances_test.sql.
create schema if not exists auth;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

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

select set_config('request.jwt.claims', '{"role":"service_role"}', false);
