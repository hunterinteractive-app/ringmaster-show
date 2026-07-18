set lock_timeout = '5s';

alter table public.account_license_balances
  add column if not exists secretary_license_expires_at timestamptz null;

comment on column public.account_license_balances.can_change_host_club is
  'Grants the Secretary License capability to manage shows under multiple host clubs. Effective access also requires secretary_license_expires_at to be NULL or in the future.';

comment on column public.account_license_balances.secretary_license_expires_at is
  'Secretary License expiration. NULL means lifetime access when can_change_host_club is true.';

create or replace function public.has_active_secretary_license()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select exists (
    select 1
    from public.account_license_balances as alb
    where alb.user_id = (select auth.uid())
      and alb.can_change_host_club
      and (
        alb.secretary_license_expires_at is null
        or alb.secretary_license_expires_at > now()
      )
  );
$function$;

comment on function public.has_active_secretary_license() is
  'Returns whether the signed-in user currently has an effective Secretary License.';

revoke execute on function public.has_active_secretary_license() from public;
revoke execute on function public.has_active_secretary_license() from anon;
grant execute on function public.has_active_secretary_license() to authenticated;
grant execute on function public.has_active_secretary_license() to service_role;;
