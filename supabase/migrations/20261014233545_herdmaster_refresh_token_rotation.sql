-- Applied to production via migration herdmaster_refresh_token_rotation; isolated HTTP tests passed.
begin;
set local lock_timeout = '3s';
alter table public.herdmaster_connections
  add column refresh_token_hash text,
  add column refresh_expires_at timestamptz,
  add column refresh_generation uuid;
create unique index herdmaster_refresh_token_hash_unique
 on public.herdmaster_connections(refresh_token_hash)
 where refresh_token_hash is not null;
create table herdmaster_private.refresh_history (
 token_hash text primary key,
 connection_id uuid not null references public.herdmaster_connections(id) on delete cascade,
 generation uuid not null,
 used_at timestamptz not null default now()
);
alter table herdmaster_private.refresh_history enable row level security;
revoke all on herdmaster_private.refresh_history from public, anon, authenticated;
grant select, insert, delete on herdmaster_private.refresh_history to service_role;
grant usage on schema herdmaster_private to service_role;
create function public.herdmaster_rotate_refresh(
 p_old_refresh_hash text, p_new_access_hash text, p_new_refresh_hash text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
 c public.herdmaster_connections;
 h herdmaster_private.refresh_history;
 access_exp timestamptz := now() + interval '1 hour';
 refresh_exp timestamptz := now() + interval '180 days';
begin
 if p_old_refresh_hash is null or p_old_refresh_hash !~ '^[A-Za-z0-9_-]{43}$'
 or p_new_access_hash is null or p_new_access_hash !~ '^[A-Za-z0-9_-]{43}$'
 or p_new_refresh_hash is null or p_new_refresh_hash !~ '^[A-Za-z0-9_-]{43}$'
 then return jsonb_build_object('status','invalid'); end if;
 -- Serialize attempts using the same credential, including concurrent replay.
 perform pg_advisory_xact_lock(hashtextextended(p_old_refresh_hash, 0));
 select * into c from public.herdmaster_connections
 where refresh_token_hash=p_old_refresh_hash for update;
 if c.id is null then
   select * into h from herdmaster_private.refresh_history where token_hash=p_old_refresh_hash;
   if h.connection_id is not null then
     update public.herdmaster_connections set revoked_at=now(),
       refresh_token_hash=null, refresh_expires_at=null
     where id=h.connection_id and refresh_generation=h.generation and revoked_at is null;
     return jsonb_build_object('status','reused');
   end if;
   return jsonb_build_object('status','invalid');
 end if;
 if c.revoked_at is not null or c.refresh_expires_at is null
 or c.refresh_expires_at<=now() or c.refresh_generation is null
 or not herdmaster_private.account_active(c.owner_user_id)
 then return jsonb_build_object('status','invalid'); end if;
 insert into herdmaster_private.refresh_history(token_hash,connection_id,generation)
 values(p_old_refresh_hash,c.id,c.refresh_generation);
 update public.herdmaster_connections set token_hash=p_new_access_hash,
 refresh_token_hash=p_new_refresh_hash, expires_at=access_exp,
 refresh_expires_at=refresh_exp where id=c.id;
 return jsonb_build_object('status','rotated','connection_id',c.id,
 'expires_at',access_exp,'refresh_expires_at',refresh_exp);
end;
$$;
revoke all on function public.herdmaster_rotate_refresh(text,text,text) from public,anon,authenticated;
grant execute on function public.herdmaster_rotate_refresh(text,text,text) to service_role;
commit;
