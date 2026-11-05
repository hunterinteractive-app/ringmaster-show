-- The support broker is the only caller. Never expose target credentials or
-- auditing tables through the Data API, even to the acting administrator.
create schema support_session_private;
revoke all on schema support_session_private from public, anon, authenticated;
-- Explicit per-operator rollout: being able to inspect accounts alone does not
-- grant the ability to act for them. Removing this row revokes existing sessions.
create table support_session_private.operators (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table support_session_private.operators enable row level security;
create table support_session_private.sessions (
  id uuid primary key default gen_random_uuid(),
  actor uuid not null, actor_session uuid not null, target uuid not null,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 minutes',
  ended_at timestamptz, target_auth_session uuid, sealed_access text,
  check (actor <> target)
);
create index on support_session_private.sessions (actor, actor_session) where ended_at is null;
create table support_session_private.requests (
  id bigint generated always as identity primary key,
  session_id uuid not null references support_session_private.sessions(id),
  requested_at timestamptz not null default now(),
  method text not null, resource text not null
);
create index on support_session_private.requests (session_id, requested_at);
alter table support_session_private.sessions enable row level security;
alter table support_session_private.requests enable row level security;
revoke all on all tables in schema support_session_private from public, anon, authenticated;
grant usage on schema support_session_private to service_role;
grant select, insert, update on support_session_private.sessions to service_role;
grant insert on support_session_private.requests to service_role;

create function public.manage_support_session(
  p_action text, p_actor uuid, p_actor_session uuid,
  p_target uuid default null, p_session uuid default null,
  p_method text default null, p_resource text default null, p_sealed text default null, p_target_session uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s support_session_private.sessions;
begin
  if not exists (select from auth.sessions where id=p_actor_session and user_id=p_actor)
    or not coalesce(public.is_super_admin(p_actor),false) then
    raise exception 'An active super administrator login is required.' using errcode='42501';
  end if;
  if p_action<>'end' and not exists(select from support_session_private.operators where user_id=p_actor) then
    if p_action='start' then return jsonb_build_object('mode','preview'); end if;
    raise exception 'Support session ended.' using errcode='42501';
  end if;
  if p_action='start' then
    if p_target is null or p_target=p_actor or coalesce(public.is_super_admin(p_target),false)
       or not exists (select from auth.users where id=p_target and email_confirmed_at is not null
         and deleted_at is null and not coalesce(is_sso_user,false) and (banned_until is null or banned_until<=now()))
       or exists(select from auth.mfa_factors f where f.user_id=p_target and f.status='verified') then
      raise exception 'Select a verified non-administrator email account without SSO or MFA.' using errcode='42501';
    end if;
    if exists (select from auth.users where id=p_target and nullif(confirmation_token,'') is not null
        and confirmation_sent_at > now()-interval '1 hour') then
      raise exception 'The user has a pending login code. Retry after they sign in.' using errcode='42501';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(p_actor_session::text, 0));
    update support_session_private.sessions set ended_at=now(),sealed_access=null
      where actor=p_actor and actor_session=p_actor_session and ended_at is null;
    insert into support_session_private.sessions(actor,actor_session,target)
      values(p_actor,p_actor_session,p_target) returning * into s;
  else
    select * into s from support_session_private.sessions
      where id=p_session and actor=p_actor and actor_session=p_actor_session;
    if not found then raise exception 'Support session unavailable.' using errcode='42501'; end if;
    if p_action='end' then
      update support_session_private.sessions set ended_at=coalesce(ended_at,now()),sealed_access=null where id=s.id;
    elsif p_action in ('activate','request') then
      if s.ended_at is not null or s.expires_at<=now() or coalesce(public.is_super_admin(s.target),false)
        or not exists (select from auth.users where id=s.target and email_confirmed_at is not null
          and deleted_at is null and not coalesce(is_sso_user,false) and (banned_until is null or banned_until<=now()))
        or exists(select from auth.mfa_factors f where f.user_id=s.target and f.status='verified') then
        raise exception 'Support session ended. Return to the administrator account.' using errcode='42501';
      end if;
      if p_action='activate' then
        if p_sealed is null or not exists (select from auth.sessions where id=p_target_session and user_id=s.target) then
          raise exception 'Invalid delegated credential.' using errcode='42501';
        end if;
        update support_session_private.sessions set sealed_access=p_sealed, target_auth_session=p_target_session
          where id=s.id and ended_at is null and sealed_access is null;
        if not found then raise exception 'Invalid session activation.'; end if;
      else
        if s.sealed_access is null or not exists (select from auth.sessions where id=s.target_auth_session and user_id=s.target) then
          raise exception 'Support session ended.' using errcode='42501';
        end if;
        if p_method is null or p_method not in ('GET','HEAD','POST','PUT','PATCH','DELETE') or p_resource is null then
          raise exception 'Invalid support request.';
        end if;
        insert into support_session_private.requests(session_id,method,resource)
          values(s.id,p_method,left(p_resource,200));
      end if;
    else raise exception 'Unknown support session action.'; end if;
  end if;
  return jsonb_build_object('id',s.id,'target',s.target,'expires_at',s.expires_at, 'sealed',case when p_action in ('end','request') then s.sealed_access end);
end $$;
revoke all on function public.manage_support_session(text,uuid,uuid,uuid,uuid,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.manage_support_session(text,uuid,uuid,uuid,uuid,text,text,text,uuid) to service_role;
