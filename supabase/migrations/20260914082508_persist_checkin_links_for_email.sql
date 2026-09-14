-- Keep the reusable show link out of public table reads. This is the shared
-- portal link, not an exhibitor session or a replacement for verification.
create schema checkin_links_private;
revoke all on schema checkin_links_private from public, anon;
grant usage on schema checkin_links_private to authenticated, service_role;

create table checkin_links_private.portal_links (
  show_id uuid primary key references public.show_checkin_settings(show_id) on delete cascade,
  portal_token text not null check (portal_token ~ '^[a-f0-9]{64}$'),
  updated_at timestamptz not null default now()
);
alter table checkin_links_private.portal_links enable row level security;
revoke all on checkin_links_private.portal_links from public, anon, authenticated;
grant select on checkin_links_private.portal_links to service_role;
create policy service_reads_portal_links on checkin_links_private.portal_links
  for select to service_role using (true);

-- An older QR link can be retained only if it still matches the current hash.
-- This never rotates a link, changes availability, or revokes a session.
create function checkin_links_private.remember_token(p_show_id uuid,p_token text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role'
     and ((select auth.uid()) is null or not public.user_can_manage_show_checkin_settings(p_show_id)) then
    raise exception 'You do not have permission to manage this show''s check-in portal' using errcode='42501';
  end if;
  perform 1 from public.show_checkin_settings
  where show_id=p_show_id
    and portal_token_hash=encode(extensions.digest(btrim(p_token),'sha256'),'hex')
  for update;
  if not found then
    raise exception 'This link does not match the show''s current check-in page.' using errcode='22023';
  end if;
  insert into checkin_links_private.portal_links(show_id,portal_token)
  values(p_show_id,btrim(p_token))
  on conflict(show_id) do update set portal_token=excluded.portal_token,updated_at=now();
end $$;

create function checkin_links_private.generate_token(p_show_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare v_token text := encode(extensions.gen_random_bytes(32),'hex');
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role'
     and ((select auth.uid()) is null or not public.user_can_manage_show_checkin_settings(p_show_id)) then
    raise exception 'You do not have permission to manage this show''s check-in portal' using errcode='42501';
  end if;
  insert into public.show_checkin_settings(show_id,portal_token_hash,updated_at)
  values(p_show_id,encode(extensions.digest(v_token,'sha256'),'hex'),now())
  on conflict(show_id) do update set portal_token_hash=excluded.portal_token_hash,updated_at=excluded.updated_at;
  perform checkin_links_private.remember_token(p_show_id,v_token);
  update public.show_checkin_sessions set revoked_at=now()
  where show_id=p_show_id and revoked_at is null;
  insert into public.show_checkin_audit_events(show_id,event_type,actor_type,actor_user_id,details)
  values(p_show_id,'portal_token_regenerated',
    case when coalesce(auth.jwt()->>'role','')='service_role' then 'system' else 'secretary' end,
    auth.uid(),'{}'::jsonb);
  return v_token;
end $$;

-- Preserve the existing generated-link API and its authorization boundary.
create or replace function public.regenerate_show_checkin_portal_token(p_show_id uuid)
returns text language sql security invoker set search_path='' as $$
  select checkin_links_private.generate_token(p_show_id);
$$;
create function public.remember_show_checkin_portal_token(p_show_id uuid,p_token text)
returns void language sql security invoker set search_path='' as $$
  select checkin_links_private.remember_token(p_show_id,p_token);
$$;

-- Include links ahead of opening time because sheets are sent in advance.
-- Portal APIs still enforce their existing time, wave, and identity checks.
create function public.get_show_checkin_email_link(p_show_id uuid)
returns text language sql stable security invoker set search_path='' as $$
  select 'https://checkin.ringmasterone.com/#/checkin?token=' || l.portal_token
  from checkin_links_private.portal_links l
  join public.show_checkin_settings s on s.show_id=l.show_id
  where s.show_id=p_show_id and s.is_enabled
    and s.portal_token_hash=encode(extensions.digest(l.portal_token,'sha256'),'hex');
$$;

revoke all on all functions in schema checkin_links_private from public, anon, authenticated;
grant execute on function checkin_links_private.generate_token(uuid) to authenticated,service_role;
grant execute on function checkin_links_private.remember_token(uuid,text) to service_role;
revoke all on function public.regenerate_show_checkin_portal_token(uuid) from public,anon;
grant execute on function public.regenerate_show_checkin_portal_token(uuid) to authenticated,service_role;
revoke all on function public.remember_show_checkin_portal_token(uuid,text),public.get_show_checkin_email_link(uuid) from public,anon,authenticated;
grant execute on function public.remember_show_checkin_portal_token(uuid,text),public.get_show_checkin_email_link(uuid) to service_role;
