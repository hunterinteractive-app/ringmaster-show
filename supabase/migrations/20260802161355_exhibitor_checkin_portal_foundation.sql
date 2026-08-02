-- Exhibitor Check-In Portal: secure, public-session foundation.
--
-- Portal tables stay protected by RLS. The only anonymous database entry
-- point is authenticate_exhibitor_checkin(), which returns a short-lived,
-- opaque session only after both the QR token and exhibitor identity match.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.show_checkin_settings (
  show_id uuid primary key references public.shows(id) on delete cascade,
  is_enabled boolean not null default false,
  portal_token_hash text,
  opens_at timestamptz,
  closes_at timestamptz,
  require_initials boolean not null default false,
  require_signature boolean not null default false,
  entry_edit_permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint show_checkin_settings_window_chk
    check (closes_at is null or opens_at is null or closes_at > opens_at)
);

create unique index if not exists show_checkin_settings_portal_token_hash_uidx
  on public.show_checkin_settings(portal_token_hash)
  where portal_token_hash is not null;

create table if not exists public.show_checkin_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_id uuid not null references public.exhibitors(id) on delete cascade,
  session_token_hash text not null unique,
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint show_checkin_sessions_expiry_chk check (expires_at > created_at)
);

create index if not exists show_checkin_sessions_active_lookup_idx
  on public.show_checkin_sessions(show_id, exhibitor_id, expires_at)
  where revoked_at is null;

create table if not exists public.show_checkin_records (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_id uuid not null references public.exhibitors(id) on delete cascade,
  status text not null default 'not_started',
  confirmed_at timestamptz,
  confirmed_by_type text,
  confirmed_by_user_id uuid,
  confirmation_initials text,
  signature_data text,
  receipt_preference text,
  completed_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by_user_id uuid,
  locked_at timestamptz,
  locked_by_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(show_id, exhibitor_id),
  constraint show_checkin_records_status_chk check (status in (
    'not_started', 'in_progress', 'completed', 'reviewed_by_secretary', 'locked'
  )),
  constraint show_checkin_records_actor_chk check (
    confirmed_by_type is null or confirmed_by_type in ('exhibitor', 'secretary')
  ),
  constraint show_checkin_records_receipt_chk check (
    receipt_preference is null or receipt_preference in ('email_receipt', 'no_receipt')
  )
);

create index if not exists show_checkin_records_show_status_idx
  on public.show_checkin_records(show_id, status);

-- This ledger is append-only. It captures both portal and staff activity,
-- without storing raw QR/session secrets or browser fingerprints.
create table if not exists public.show_checkin_audit_events (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_id uuid references public.exhibitors(id) on delete set null,
  checkin_record_id uuid references public.show_checkin_records(id) on delete set null,
  event_type text not null,
  actor_type text not null,
  actor_user_id uuid,
  session_id uuid references public.show_checkin_sessions(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint show_checkin_audit_events_actor_chk check (
    actor_type in ('exhibitor_portal', 'secretary', 'system')
  )
);

create index if not exists show_checkin_audit_events_show_created_idx
  on public.show_checkin_audit_events(show_id, created_at desc);
create index if not exists show_checkin_audit_events_exhibitor_created_idx
  on public.show_checkin_audit_events(exhibitor_id, created_at desc);

alter table public.show_checkin_settings enable row level security;
alter table public.show_checkin_sessions enable row level security;
alter table public.show_checkin_records enable row level security;
alter table public.show_checkin_audit_events enable row level security;

create policy "Managers manage check-in settings"
on public.show_checkin_settings
for all to authenticated
using (
  public.user_can_manage_entries(show_id)
  or public.user_can_manage_show_settings(show_id)
)
with check (
  public.user_can_manage_entries(show_id)
  or public.user_can_manage_show_settings(show_id)
);

create policy "Managers read check-in sessions"
on public.show_checkin_sessions
for select to authenticated
using (
  public.user_can_manage_entries(show_id)
  or public.user_can_manage_show_settings(show_id)
);

create policy "Managers read check-in records"
on public.show_checkin_records
for select to authenticated
using (
  public.user_can_manage_entries(show_id)
  or public.user_can_manage_show_settings(show_id)
);

create policy "Managers read check-in audit events"
on public.show_checkin_audit_events
for select to authenticated
using (
  public.user_can_manage_entries(show_id)
  or public.user_can_manage_show_settings(show_id)
);

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
     and not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
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
  where lower(btrim(coalesce(e.exhibitor_number, '')))
      = lower(btrim(coalesce(p_exhibitor_number, '')))
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

revoke all on function public.regenerate_show_checkin_portal_token(uuid) from public;
revoke all on function public.authenticate_exhibitor_checkin(text, text, text) from public;
grant execute on function public.regenerate_show_checkin_portal_token(uuid)
  to authenticated, service_role;
grant execute on function public.authenticate_exhibitor_checkin(text, text, text)
  to anon, authenticated, service_role;
