-- Run only against an isolated test database. Fixtures roll back.
begin;
do $$
declare a uuid:=gen_random_uuid(); t uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  actor_session uuid:=gen_random_uuid(); target_session uuid:=gen_random_uuid();
  result jsonb; sid uuid; before_deadline timestamptz;
begin
  insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
  values(a,'idle-admin-'||a||'@example.invalid',now(),'{}'),(t,'idle-target-'||t||'@example.invalid',now(),'{}');
  insert into auth.sessions(id,user_id) values(actor_session,a),(target_session,t);
  insert into public.super_admins(user_id) values(a);
  insert into support_session_private.operators(user_id) values(a);
  result:=public.manage_support_session('start',a,actor_session,p_target=>t);
  sid:=(result->>'id')::uuid;
  perform public.manage_support_session('activate',a,actor_session,p_session=>sid,p_sealed=>'sealed-old',p_target_session=>target_session);
  update support_session_private.sessions set expires_at=now()+interval '90 seconds' where id=sid returning expires_at into before_deadline;
  perform public.manage_support_session('request',a,actor_session,p_session=>sid,p_method=>'GET',p_resource=>'table/shows');
  if (select expires_at from support_session_private.sessions where id=sid)<>before_deadline then raise exception 'Polling renewed the deadline'; end if;
  result:=public.manage_support_session('refresh',a,actor_session,p_session=>sid,p_sealed=>'sealed-new',p_target_session=>target_session,p_expected_sealed=>'sealed-old');
  if result->>'sealed'<>'sealed-new' or (result->>'expires_at')::timestamptz<>before_deadline then raise exception 'Credential rotation changed inactivity deadline'; end if;
  result:=public.manage_support_session('refresh',a,actor_session,p_session=>sid,p_sealed=>'stale-write',p_target_session=>target_session,p_expected_sealed=>'sealed-old');
  if result->>'sealed'<>'sealed-new' then raise exception 'Stale rotation overwrote current credentials'; end if;
  result:=public.manage_support_session('continue',a,actor_session,p_session=>sid);
  if (result->>'expires_at')::timestamptz < clock_timestamp()+interval '29 minutes' then raise exception 'Continue did not extend deadline'; end if;
  if result->>'sealed' is not null then raise exception 'Continue exposed sealed credentials'; end if;
  begin
    perform public.manage_support_session('continue',a,outsider,p_session=>sid);
    raise exception 'Wrong administrator session accepted';
  exception when insufficient_privilege then null; end;
  delete from support_session_private.operators where user_id=a;
  begin
    perform public.manage_support_session('continue',a,actor_session,p_session=>sid);
    raise exception 'Revoked operator accepted';
  exception when insufficient_privilege then null; end;
  insert into support_session_private.operators(user_id) values(a);
  update support_session_private.sessions set expires_at=now()-interval '1 second' where id=sid;
  begin
    perform public.manage_support_session('continue',a,actor_session,p_session=>sid);
    raise exception 'Expired session revived';
  exception when insufficient_privilege then null; end;
  update support_session_private.sessions set expires_at=now()+interval '1 minute' where id=sid;
  perform public.manage_support_session('end',a,actor_session,p_session=>sid);
  begin
    perform public.manage_support_session('continue',a,actor_session,p_session=>sid);
    raise exception 'Ended session revived';
  exception when insufficient_privilege then null; end;
  if has_function_privilege('authenticated','public.manage_support_session(text,uuid,uuid,uuid,uuid,text,text,text,uuid,text)','EXECUTE')
    or has_function_privilege('anon','public.manage_support_session(text,uuid,uuid,uuid,uuid,text,text,text,uuid,text)','EXECUTE') then
    raise exception 'Support management exposed to browser roles';
  end if;
  raise notice 'PASS: polling, continuation, rotation CAS, revocation, expiration, Exit and privilege boundaries';
end $$;
rollback;
