-- Exhibitor numbers are stored as bigint. Compare their display value to the
-- public form's text input instead of coercing a numeric column with ''.
create or replace function public.authenticate_exhibitor_checkin(
  p_portal_token text,
  p_exhibitor_number text,
  p_last_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.show_checkin_settings%rowtype;
  v_exhibitor_id uuid;
  v_session_id uuid;
  v_session_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires_at timestamptz := now() + interval '30 minutes';
begin
  select * into v_settings
  from public.show_checkin_settings
  where portal_token_hash = encode(
    extensions.digest(btrim(coalesce(p_portal_token, '')), 'sha256'),
    'hex'
  )
  for update;

  if not found
     or not v_settings.is_enabled
     or (v_settings.opens_at is not null and now() < v_settings.opens_at)
     or (v_settings.closes_at is not null and now() > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;

  select e.id into v_exhibitor_id
  from public.exhibitors e
  where btrim(e.exhibitor_number::text)
      = btrim(coalesce(p_exhibitor_number, ''))
    and lower(btrim(coalesce(e.last_name, '')))
      = lower(btrim(coalesce(p_last_name, '')))
    and exists (
      select 1 from public.entries en
      where en.show_id = v_settings.show_id and en.exhibitor_id = e.id
    )
  order by e.created_at
  limit 1;

  if v_exhibitor_id is null then
    raise exception 'We could not verify those check-in details';
  end if;

  update public.show_checkin_sessions
  set revoked_at = now()
  where show_id = v_settings.show_id
    and exhibitor_id = v_exhibitor_id
    and revoked_at is null;

  insert into public.show_checkin_sessions(
    show_id, exhibitor_id, session_token_hash, expires_at
  ) values (
    v_settings.show_id,
    v_exhibitor_id,
    encode(extensions.digest(v_session_token, 'sha256'), 'hex'),
    v_expires_at
  ) returning id into v_session_id;

  insert into public.show_checkin_audit_events(
    show_id, exhibitor_id, event_type, actor_type, session_id, details
  ) values (
    v_settings.show_id, v_exhibitor_id, 'identity_verified',
    'exhibitor_portal', v_session_id,
    jsonb_build_object('expires_at', v_expires_at)
  );

  return jsonb_build_object(
    'session_token', v_session_token,
    'expires_at', v_expires_at,
    'show_id', v_settings.show_id,
    'exhibitor_id', v_exhibitor_id
  );
end;
$$;

revoke all on function public.authenticate_exhibitor_checkin(text, text, text) from public;
grant execute on function public.authenticate_exhibitor_checkin(text, text, text)
  to anon, authenticated, service_role;
