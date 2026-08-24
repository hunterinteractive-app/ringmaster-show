create table if not exists public.auth_user_cleanup_log (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique,
  auth_user_created_at timestamptz not null,
  deleted_at timestamptz not null default now(),
  reason text not null
);

alter table public.auth_user_cleanup_log enable row level security;
revoke all on public.auth_user_cleanup_log from anon, authenticated;

create or replace function public.cleanup_unverified_auth_users(p_apply boolean default false)
returns table (auth_user_id uuid)
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if not p_apply then
    return query
    select u.id
    from auth.users u
    where u.created_at < now() - interval '7 days'
      and u.email_confirmed_at is null and u.phone_confirmed_at is null
      and u.last_sign_in_at is null and not u.is_sso_user and u.deleted_at is null
      and not exists (select 1 from public.profiles p where p.id = u.id)
      and not exists (select 1 from public.exhibitors e where e.owner_user_id = u.id);
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext('public.cleanup_unverified_auth_users'));
  return query
  with candidates as (
    select u.id, u.created_at
    from auth.users u
    where u.created_at < now() - interval '7 days'
      and u.email_confirmed_at is null and u.phone_confirmed_at is null
      and u.last_sign_in_at is null and not u.is_sso_user and u.deleted_at is null
      and not exists (select 1 from public.profiles p where p.id = u.id)
      and not exists (select 1 from public.exhibitors e where e.owner_user_id = u.id)
  ), deleted as (
    delete from auth.users u using candidates c where u.id = c.id
    returning u.id, c.created_at
  ), logged as (
    insert into public.auth_user_cleanup_log (auth_user_id, auth_user_created_at, reason)
    select id, created_at, 'Unverified for more than seven days with no sign-in, profile, or exhibitor ownership.'
    from deleted
  ) select id from deleted;
end;
$$;

revoke execute on function public.cleanup_unverified_auth_users(boolean) from public, anon, authenticated;

do $$
declare existing_job_id bigint;
begin
  select jobid into existing_job_id from cron.job where jobname = 'monthly-unverified-auth-user-cleanup';
  if existing_job_id is not null then perform cron.unschedule(existing_job_id); end if;
  perform cron.schedule('monthly-unverified-auth-user-cleanup', '30 5 1 * *', 'select public.cleanup_unverified_auth_users(true);');
end;
$$;
