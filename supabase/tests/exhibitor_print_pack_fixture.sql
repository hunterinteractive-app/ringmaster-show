-- Standalone isolated-Postgres fixture. Never run against the application DB.
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create schema storage;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth,storage to anon,authenticated,service_role;
create table public.shows(id uuid primary key);
create function public.user_can_manage_show_settings(uuid) returns boolean
language sql stable as $$ select auth.uid() is not null $$;
create function public.user_can_email_reports(uuid) returns boolean
language sql stable as $$ select auth.uid() is not null $$;
create table public.exhibitors(id uuid primary key,display_name text,first_name text,last_name text);
create table public.show_report_artifacts(id uuid primary key,show_id uuid,
  generation int,storage_bucket text,storage_path text,file_hash_sha256 text,
  report_name text,metadata jsonb,scope_key text,is_current boolean,artifact_status text);
create table storage.buckets(id text primary key,name text,public boolean,
  file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
alter table storage.objects enable row level security;
grant all on storage.objects to authenticated,service_role;
grant select on storage.objects to anon;
create policy existing_broad_access on storage.objects for all to authenticated using(true) with check(true);
insert into auth.users values
('3e8dddf9-3a17-4ebb-aeab-9b51d31e7871'),('cad4eb5f-239a-4990-b372-e8a43e3faee8'),
('11111111-1111-4111-8111-111111111111');
insert into shows values ('22222222-2222-4222-8222-222222222222');
insert into exhibitors values
('33333333-3333-4333-8333-333333333333','Zoe Adams','Zoe','Adams'),
('44444444-4444-4444-8444-444444444444','Aaron Brown','Aaron','Brown');
insert into show_report_artifacts
select gen_random_uuid(),'22222222-2222-4222-8222-222222222222',1,'show-files',
 e.id::text || '-' || r || '.pdf',null,r,jsonb_build_object('exhibitor_id',e.id),
 'scope',true,'generated' from exhibitors e cross join unnest(array['legs','exhibitor_report']) r;
