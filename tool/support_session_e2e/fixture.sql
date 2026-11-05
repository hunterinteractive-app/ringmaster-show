create table public.super_admins(user_id uuid primary key);
create function public.is_super_admin(uid uuid) returns boolean language sql stable as $$select exists(select from public.super_admins where user_id=uid)$$;
create table public.account_license_balances(user_id uuid primary key,unlimited_active boolean default false,unlimited_expires_at timestamptz,purchased_show_days int default 0,consumed_show_days int default 0,updated_at timestamptz);
create table public.shows(id uuid primary key default gen_random_uuid(),created_by uuid,owner_user_id uuid,name text,start_date date,end_date date,location_name text,timezone text,is_published boolean);
create table public.role_assignments(show_id uuid,user_id uuid,role text,unique(show_id,user_id,role));
alter table public.super_admins enable row level security;
alter table public.account_license_balances enable row level security;
alter table public.role_assignments enable row level security;
alter table public.shows enable row level security;
create policy own_shows on public.shows for all to authenticated using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());

create policy support_test_files on storage.objects for all to authenticated
  using (bucket_id='support-smoke' and (storage.foldername(name))[1]=auth.uid()::text)
  with check (bucket_id='support-smoke' and (storage.foldername(name))[1]=auth.uid()::text);
insert into storage.buckets(id,name) values('support-smoke','support-smoke');
