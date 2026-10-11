create table public.breeder_connections (
 id uuid primary key,
 owner_user_id uuid not null references auth.users(id) on delete cascade,
 version timestamptz not null
);
create table public.breeder_animal_links (
 connection_id uuid not null references public.breeder_connections(id) on delete cascade,
 breeder_animal_id uuid not null,
 animal_id uuid not null unique references public.animals(id) on delete cascade,
 managed boolean not null,
 primary key(connection_id,breeder_animal_id)
);
alter table public.breeder_connections enable row level security;
alter table public.breeder_animal_links enable row level security;
revoke all on public.breeder_connections,public.breeder_animal_links from anon,authenticated;
grant all on public.breeder_connections,public.breeder_animal_links to service_role;
create function public.breeder_verified_account(p_email text) returns uuid language sql security invoker set search_path='' as $$
 select id from auth.users where lower(trim(email))=lower(trim(p_email)) and email_confirmed_at is not null and deleted_at is null and (banned_until is null or banned_until<now()) limit 1;
$$;
revoke all on function public.breeder_verified_account(text) from public,anon,authenticated;
grant execute on function public.breeder_verified_account(text) to service_role;
create function public.apply_breeder_animals(p_connection uuid,p_owner uuid,p_version timestamptz,p_animals jsonb) returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare row jsonb; aid uuid; mode text; v text; n integer=0; current_version timestamptz; original uuid;
begin
 if jsonb_typeof(p_animals)<>'array' or jsonb_array_length(p_animals)>10000 then raise exception 'Invalid herd snapshot'; end if;
 insert into public.breeder_connections values(p_connection,p_owner,p_version) on conflict(id) do nothing;
 select version into current_version from public.breeder_connections where id=p_connection and owner_user_id=p_owner for update;
 if not found then raise exception 'Connection owner mismatch'; end if;
 if current_version>p_version then return 0; end if;
 update public.breeder_connections set version=p_version where id=p_connection;
 -- Only hide rows created by this bridge. Original Show animals are retained.
 update public.animals a set deleted_at=now() from public.breeder_animal_links l where l.connection_id=p_connection and l.managed and a.id=l.animal_id and not exists(select 1 from jsonb_array_elements(p_animals) j where (j->>'id')::uuid=l.breeder_animal_id);
 for row in select value from jsonb_array_elements(p_animals) loop
  aid=null;
  select animal_id into aid from public.breeder_animal_links where connection_id=p_connection and breeder_animal_id=(row->>'id')::uuid;
  if aid is null then
   original=nullif(row->>'show_id','')::uuid;
   if original is not null then
    select id into aid from public.animals where id=original and owner_user_id=p_owner and not exists(select 1 from public.breeder_animal_links where animal_id=original);
   end if;
   if aid is not null then
    insert into public.breeder_animal_links values(p_connection,(row->>'id')::uuid,aid,false);
   end if;
  end if;
  v=nullif(trim(row->>'variety'),'');
  select variety_mode into mode from public.breeds where lower(name)=lower(row->>'breed') limit 1;
  if mode='lop_grouped' and v is not null then
   v=case when lower(v) like '%broken%' or lower(v) like '%tri-color%' or lower(v) like '%tricolor%' or lower(coalesce(row->>'pattern','')) like '%broken%' then 'Broken' else 'Solid' end;
  end if;
  if aid is null then
   insert into public.animals(owner_user_id,species,name,tattoo,breed,variety,sex,birth_date,is_dob_unknown)
   values(p_owner,(row->>'species')::public.species,nullif(row->>'name',''),row->>'tattoo',row->>'breed',v,row->>'sex',nullif(row->>'dob','')::date,nullif(row->>'dob','') is null) returning id into aid;
   insert into public.breeder_animal_links values(p_connection,(row->>'id')::uuid,aid,true);
  else
   update public.animals set name=nullif(row->>'name',''),tattoo=row->>'tattoo',breed=row->>'breed',variety=v,sex=row->>'sex',birth_date=nullif(row->>'dob','')::date,is_dob_unknown=nullif(row->>'dob','') is null,updated_at=now(),deleted_at=null where id=aid and owner_user_id=p_owner;
  end if;
  n=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.apply_breeder_animals(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.apply_breeder_animals(uuid,uuid,timestamptz,jsonb) to service_role;
