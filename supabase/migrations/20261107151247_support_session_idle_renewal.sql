-- Only explicit foreground activity renews the idle deadline. Data requests,
-- polling and credential rotation do not. Keep all actor and target checks.
set lock_timeout='5s';
drop function public.manage_support_session(text,uuid,uuid,uuid,uuid,text,text,text,uuid);
create function public.manage_support_session(
  p_action text, p_actor uuid, p_actor_session uuid,
  p_target uuid default null, p_session uuid default null,
  p_method text default null, p_resource text default null, p_sealed text default null, p_target_session uuid default null,
  p_expected_sealed text default null
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
      where id=p_session and actor=p_actor and actor_session=p_actor_session for update;
    if not found then raise exception 'Support session unavailable.' using errcode='42501'; end if;
    if p_action='end' then
      update support_session_private.sessions set ended_at=coalesce(ended_at,now()),sealed_access=null where id=s.id;
    elsif p_action in ('activate','request','continue','refresh') then
      if s.ended_at is not null or s.expires_at<=clock_timestamp() or coalesce(public.is_super_admin(s.target),false)
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
        if p_action='continue' then
          update support_session_private.sessions set expires_at=clock_timestamp()+interval '30 minutes'
            where id=s.id returning * into s;
          insert into support_session_private.requests(session_id,method,resource)
            values(s.id,'POST','session/continue');
        elsif p_action='refresh' then
          if p_sealed is null or p_expected_sealed is null or not exists (
            select from auth.sessions where id=p_target_session and user_id=s.target
          ) then raise exception 'Invalid session renewal.' using errcode='42501'; end if;
          -- A concurrent refresh or Exit must never be overwritten by an older response.
          if s.sealed_access=p_expected_sealed then
            update support_session_private.sessions set sealed_access=p_sealed,
              target_auth_session=p_target_session where id=s.id returning * into s;
          end if;
        else
        if p_method is null or p_method not in ('GET','HEAD','POST','PUT','PATCH','DELETE') or p_resource is null then
          raise exception 'Invalid support request.';
        end if;
        insert into support_session_private.requests(session_id,method,resource)
          values(s.id,p_method,left(p_resource,200));
        end if;
      end if;
    else raise exception 'Unknown support session action.'; end if;
  end if;
  return jsonb_build_object('id',s.id,'target',s.target,'expires_at',s.expires_at, 'sealed',case when p_action in ('end','request','refresh') then s.sealed_access end);
end $$;
revoke all on function public.manage_support_session(text,uuid,uuid,uuid,uuid,text,text,text,uuid,text) from public, anon, authenticated;
grant execute on function public.manage_support_session(text,uuid,uuid,uuid,uuid,text,text,text,uuid,text) to service_role;
