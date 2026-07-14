-- Compatibility prelude for compiling the local bootstrap in plain Postgres.
-- A real Supabase database already provides these roles and auth functions.
create schema if not exists auth;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)
$$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt()->>'sub','')::uuid
$$;
create table if not exists auth.users(id uuid primary key);
