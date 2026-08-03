-- Keep Check-In configuration tightly scoped.  These two designated account
-- owners may configure the portal only for shows they themselves own; all
-- other users remain subject to the existing Super Admin boundary.
create or replace function public.user_can_manage_show_checkin_settings(
  p_show_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = 'public'
as $$
  select public.is_super_admin()
    or exists (
      select 1
      from public.shows s
      where s.id = p_show_id
        and s.owner_user_id = auth.uid()
        and auth.uid() in (
          '96d62792-7aad-49da-a27a-4fb496289176'::uuid,
          '8bbd00a2-5659-4828-a686-009f7a58f085'::uuid
        )
    );
$$;

revoke all on function public.user_can_manage_show_checkin_settings(uuid)
  from public, anon;
grant execute on function public.user_can_manage_show_checkin_settings(uuid)
  to authenticated, service_role;

drop policy if exists "Super admins manage check-in settings"
  on public.show_checkin_settings;

create policy "Authorized owners manage check-in settings"
on public.show_checkin_settings
for all to authenticated
using ((select public.user_can_manage_show_checkin_settings(show_id)))
with check ((select public.user_can_manage_show_checkin_settings(show_id)));

create or replace function public.regenerate_show_checkin_portal_token(
  p_show_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not public.user_can_manage_show_checkin_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s check-in portal'
      using errcode = '42501';
  end if;

  insert into public.show_checkin_settings(show_id, portal_token_hash, updated_at)
  values (
    p_show_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    now()
  )
  on conflict (show_id) do update
  set portal_token_hash = excluded.portal_token_hash,
      updated_at = excluded.updated_at;

  update public.show_checkin_sessions
  set revoked_at = now()
  where show_id = p_show_id and revoked_at is null;

  insert into public.show_checkin_audit_events(
    show_id, event_type, actor_type, actor_user_id, details
  ) values (
    p_show_id,
    'portal_token_regenerated',
    case when coalesce(auth.jwt() ->> 'role', '') = 'service_role'
      then 'system' else 'secretary' end,
    auth.uid(),
    '{}'::jsonb
  );

  return v_token;
end;
$$;

revoke all on function public.regenerate_show_checkin_portal_token(uuid)
  from public, anon;
grant execute on function public.regenerate_show_checkin_portal_token(uuid)
  to authenticated, service_role;
