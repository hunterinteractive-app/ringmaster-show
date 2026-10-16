-- Auth tables intentionally deny service_role direct SELECT in production.
-- Expose only a boolean account-status check in an unexposed private schema.
create schema if not exists herdmaster_private;
revoke all on schema herdmaster_private from public,anon,authenticated;
grant usage on schema herdmaster_private to service_role;
create function herdmaster_private.account_active(p_owner uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is distinct from p_owner
    and coalesce(auth.jwt()->>'role','')<>'service_role'
    and session_user not in ('postgres','supabase_admin') then
    raise exception using errcode='42501',message='Account status check is server-only';
  end if;
  return exists(select 1 from auth.users u where u.id=p_owner
    and u.email_confirmed_at is not null and u.deleted_at is null
    and (u.banned_until is null or u.banned_until<now()));
end $$;
revoke all on function herdmaster_private.account_active(uuid) from public,anon,authenticated;
grant execute on function herdmaster_private.account_active(uuid) to service_role;
create or replace function public.herdmaster_authorize(p_hash text)
returns public.herdmaster_connections language plpgsql security invoker set search_path = '' as $$
declare c public.herdmaster_connections;
begin
  select hc.* into c from public.herdmaster_connections hc
  where hc.token_hash=p_hash and hc.revoked_at is null and hc.expires_at>now()
    and herdmaster_private.account_active(hc.owner_user_id) for share of hc;
  if c.id is null then raise exception using errcode='28000',message='Invalid connection token'; end if;
  return c;
end $$;
revoke all on function public.herdmaster_authorize(text) from public,anon,authenticated;
grant execute on function public.herdmaster_authorize(text) to service_role;
