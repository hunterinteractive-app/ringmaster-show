-- Prerequisites: the deployed HerdMaster partner API and refresh rotation schema.
create table public.animal_sync_requests (
 id uuid primary key default gen_random_uuid(),
 owner_user_id uuid not null references auth.users(id) on delete cascade,
 provider text not null,
 connection_id uuid not null,
 status text not null default 'pending' check (status in ('pending','completed','failed')),
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
create index animal_sync_requests_connection on public.animal_sync_requests(provider,connection_id,created_at desc);
create table public.animal_sync_state (
 owner_user_id uuid not null references auth.users(id) on delete cascade,
 provider text not null,
 connection_id uuid not null,
 last_refreshed_at timestamptz not null,
 primary key(provider,connection_id)
);
alter table public.animal_sync_requests enable row level security;
alter table public.animal_sync_state enable row level security;
revoke all on public.animal_sync_requests, public.animal_sync_state from public,anon,authenticated;
grant all on public.animal_sync_requests, public.animal_sync_state to service_role;

create function public.animal_sync_begin(p_owner uuid,p_provider text,p_connection uuid)
returns uuid language plpgsql security invoker set search_path='' as $$
declare rid uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_provider||p_connection::text,0));
 if exists(select 1 from public.animal_sync_requests where provider=p_provider and connection_id=p_connection and status='pending' and created_at>now()-interval '2 minutes') then
  raise exception using errcode='55P03',message='Refresh already in progress';
 end if;
 update public.animal_sync_requests set status='failed' where provider=p_provider and connection_id=p_connection and status='pending';
 insert into public.animal_sync_requests(owner_user_id,provider,connection_id) values(p_owner,p_provider,p_connection) returning id into rid;
 return rid;
end $$;

create function public.animal_sync_apply_herdmaster(p_hash text,p_animals jsonb,p_request uuid,p_complete boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.herdmaster_connections; r public.animal_sync_requests; result jsonb;
begin
 perform 1 from public.herdmaster_connections where token_hash=p_hash for update;
 c=public.herdmaster_authorize(p_hash);
 select * into r from public.animal_sync_requests where id=p_request for update;
 if r.id is null or r.provider<>'herdmaster' or r.connection_id<>c.id or r.owner_user_id<>c.owner_user_id or r.status<>'pending' or r.created_at<=now()-interval '2 minutes' then
  raise exception using errcode='22023',message='Refresh request is invalid, expired, or completed';
 end if;
 result=public.herdmaster_apply_animals(p_hash,p_animals);
 if p_complete then
  update public.animal_sync_requests set status='completed',completed_at=now() where id=r.id;
  insert into public.animal_sync_state values(c.owner_user_id,'herdmaster',c.id,now())
  on conflict(provider,connection_id) do update set last_refreshed_at=excluded.last_refreshed_at;
 end if;
 return result;
end $$;
revoke all on function public.animal_sync_begin(uuid,text,uuid),public.animal_sync_apply_herdmaster(text,jsonb,uuid,boolean) from public,anon,authenticated;
grant execute on function public.animal_sync_begin(uuid,text,uuid),public.animal_sync_apply_herdmaster(text,jsonb,uuid,boolean) to service_role;
