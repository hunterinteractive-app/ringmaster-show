-- Run after prerequisite and manual-refresh migrations in a disposable transaction.
do $$
declare owner uuid=gen_random_uuid(); other_owner uuid=gen_random_uuid();
 c uuid; other_c uuid; req uuid; old_time timestamptz; result jsonb;
begin
 insert into auth.users(id,email,email_confirmed_at) values
 (owner,owner::text||'@example.invalid',now()),(other_owner,other_owner::text||'@example.invalid',now());
 insert into public.herdmaster_connections(owner_user_id,external_account_id,token_hash,expires_at)
 values(owner,'fixture','fixture-hash',now()+interval '1 day') returning id into c;
 insert into public.herdmaster_connections(owner_user_id,external_account_id,token_hash,expires_at)
 values(other_owner,'other-fixture','other-hash',now()+interval '1 day') returning id into other_c;
 perform set_config('role','service_role',true);
 req=public.animal_sync_begin(owner,'herdmaster',c);
 begin
  perform public.animal_sync_begin(owner,'herdmaster',c);
  raise exception 'Concurrent refresh was not blocked';
 exception when lock_not_available then null; end;
 begin
  perform public.animal_sync_apply_herdmaster('other-hash','[]',req,true);
  raise exception 'Another account completed a refresh';
 exception when invalid_parameter_value then null; end;
 perform public.animal_sync_apply_herdmaster('fixture-hash','[{"id":"inactive-test","active":false,"updated_at":"2026-10-15T12:00:00Z"}]',req,false);
 if exists(select 1 from public.animal_sync_state where connection_id=c) then raise exception 'Partial batch advanced last refresh'; end if;
 if (select status from public.animal_sync_requests where id=req)<>'pending' then raise exception 'Partial batch completed request'; end if;
 perform public.animal_sync_apply_herdmaster('fixture-hash','[]',req,true);
 if (select status from public.animal_sync_requests where id=req)<>'completed' then raise exception 'Final batch did not complete request'; end if;
 select last_refreshed_at into old_time from public.animal_sync_state where connection_id=c;
 if old_time is null then raise exception 'Final batch did not persist refresh time'; end if;
 begin
  perform public.animal_sync_apply_herdmaster('fixture-hash','[]',req,true);
  raise exception 'Completed request replay accepted';
 exception when invalid_parameter_value then null; end;
 req=public.animal_sync_begin(owner,'herdmaster',c);
 update public.animal_sync_requests set status='failed' where id=req;
 begin
  perform public.animal_sync_apply_herdmaster('fixture-hash','[]',req,true);
  raise exception 'Failed request accepted late delivery';
 exception when invalid_parameter_value then null; end;
 if (select last_refreshed_at from public.animal_sync_state where connection_id=c) is distinct from old_time then raise exception 'Failure changed success time'; end if;
 req=public.animal_sync_begin(owner,'herdmaster',c);
 update public.animal_sync_requests set created_at=now()-interval '3 minutes' where id=req;
 begin
  perform public.animal_sync_apply_herdmaster('fixture-hash','[]',req,true);
  raise exception 'Expired request accepted';
 exception when invalid_parameter_value then null; end;
 req=public.animal_sync_begin(owner,'herdmaster',c);
 update public.herdmaster_connections set revoked_at=now() where id=c;
 begin
  perform public.animal_sync_apply_herdmaster('fixture-hash','[]',req,true);
  raise exception 'Disconnected account completed refresh';
 exception when invalid_authorization_specification then null; end;
 if has_function_privilege('authenticated','public.animal_sync_begin(uuid,text,uuid)','execute')
 or has_function_privilege('anon','public.animal_sync_apply_herdmaster(text,jsonb,uuid,boolean)','execute')
 or has_table_privilege('authenticated','public.animal_sync_state','update') then raise exception 'Client permissions too broad'; end if;
 raise notice 'Manual refresh SQL checks passed';
end $$;
