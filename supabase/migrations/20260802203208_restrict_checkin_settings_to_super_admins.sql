-- The public QR link controls every exhibitor's access to a show. Keep its
-- configuration and token rotation under the platform Super Admin boundary.

drop policy if exists "Managers manage check-in settings"
  on public.show_checkin_settings;

create policy "Super admins manage check-in settings"
on public.show_checkin_settings
for all to authenticated
using ((select public.is_super_admin()))
with check ((select public.is_super_admin()));

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
     and not public.is_super_admin() then
    raise exception 'Only Super Admins can manage a show''s check-in portal'
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

revoke all on function public.regenerate_show_checkin_portal_token(uuid) from public;
grant execute on function public.regenerate_show_checkin_portal_token(uuid)
  to authenticated, service_role;
