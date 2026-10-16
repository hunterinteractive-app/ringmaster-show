-- Account isolation plus a shared, owner-confirmed review queue.
alter table public.herdmaster_connections add column provider text not null default 'herdmaster' check(provider in ('herdmaster','pedigreehq'));
alter table public.herdmaster_connections drop constraint herdmaster_connections_owner_user_id_external_account_id_key;
alter table public.herdmaster_connections add unique(provider,owner_user_id,external_account_id);
alter table public.herdmaster_connections add column existing_animals_consent boolean not null default false;
create schema if not exists partner_private;
revoke all on schema partner_private from public,anon,authenticated;
create table public.animal_import_reviews (
 id uuid primary key default gen_random_uuid(),
 owner_user_id uuid not null references auth.users(id) on delete cascade,
 provider text not null check(provider in ('ringmaster_breeder','herdmaster','pedigreehq')),
 connection_id uuid not null, external_animal_id text not null,
 payload jsonb not null, source_version timestamptz not null,
 decision text not null default 'pending' check(decision in ('pending','link','separate','withdrawn')),
 target_id uuid references public.animals(id) on delete set null,
 resolved_at timestamptz,
 updated_at timestamptz not null default clock_timestamp(),
 unique(provider,connection_id,external_animal_id)
);
alter table public.animal_import_reviews enable row level security;
revoke all on public.animal_import_reviews from public,anon,authenticated;
grant all on public.animal_import_reviews to service_role;
create index animal_import_reviews_owner on public.animal_import_reviews(owner_user_id,decision);

create function partner_private.candidates(p_owner uuid,p_animal jsonb,p_after uuid default null,p_all boolean default false)
returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.payload order by x.id),'[]') from (
 select a.id,jsonb_build_object('ringmaster_animal_id',a.id,'name',a.name,'tattoo',a.tattoo,'species',a.species,
 'breed',a.breed,'variety',a.variety,'sex',a.sex,'dob',a.birth_date,
 'can_link',not exists(select 1 from public.breeder_animal_links b where b.animal_id=a.id)
 and not exists(select 1 from public.herdmaster_animal_links h where h.animal_id=a.id)) payload
 from public.animals a where a.owner_user_id=p_owner and a.deleted_at is null and (p_after is null or a.id>p_after)
 and (p_all or (a.species::text=p_animal->>'species' and (
 (nullif(btrim(p_animal->>'tattoo'),'') is not null and lower(btrim(a.tattoo))=lower(btrim(p_animal->>'tattoo')))
 or a.id::text=coalesce(p_animal->>'show_id',p_animal->>'ringmaster_animal_id')
 or (nullif(btrim(p_animal->>'name'),'') is not null and lower(btrim(a.name))=lower(btrim(p_animal->>'name'))))))
 order by a.id limit 500) x;
$$;
create function partner_private.prepare(p_owner uuid,p_provider text,p_connection uuid,p_source text,p_payload jsonb,p_version timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.animal_import_reviews; matches jsonb;
begin
 matches=partner_private.candidates(p_owner,p_payload);
 select * into q from public.animal_import_reviews where provider=p_provider and connection_id=p_connection and external_animal_id=p_source for update;
 if q.id is not null and q.source_version>p_version then return null; end if;
 if q.id is not null and q.source_version=p_version and q.payload is distinct from p_payload then raise exception using errcode='23505',message='Animal version conflict'; end if;
 if q.id is not null and q.decision='pending' and q.source_version=p_version and q.payload=p_payload then return null; end if;
 if q.id is not null and q.decision in ('link','separate') then
  if q.decision='link' then
   if q.target_id is null or not exists(select 1 from public.animals a where a.id=q.target_id and a.owner_user_id=p_owner and a.deleted_at is null)
    or exists(select 1 from public.breeder_animal_links where animal_id=q.target_id)
    or exists(select 1 from public.herdmaster_animal_links where animal_id=q.target_id) then raise exception 'Selected animal is no longer available'; end if;
   return p_payload||jsonb_build_object('show_id',q.target_id,'ringmaster_animal_id',q.target_id);
  end if;
  if q.resolved_at is not null then raise exception 'Saved separate animal link is missing; review required'; end if;
  return (p_payload-'show_id'-'ringmaster_animal_id');
 end if;
 -- A provided ID is still a suggestion until the owner confirms it in Show.
 if jsonb_array_length(matches)=0 and nullif(coalesce(p_payload->>'show_id',p_payload->>'ringmaster_animal_id'),'') is null and q.id is null then return p_payload; end if;
 insert into public.animal_import_reviews(owner_user_id,provider,connection_id,external_animal_id,payload,source_version)
 values(p_owner,p_provider,p_connection,p_source,p_payload,p_version)
 on conflict(provider,connection_id,external_animal_id) do update set payload=excluded.payload,source_version=excluded.source_version,decision='pending',updated_at=clock_timestamp();
 return null;
end $$;
create or replace function public.apply_breeder_animals(p_connection uuid,p_owner uuid,p_version timestamptz,p_animals jsonb) returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare row jsonb; aid uuid; mode text; v text; n integer=0; current_version timestamptz; original uuid;
begin
 if jsonb_typeof(p_animals)<>'array' or jsonb_array_length(p_animals)>10000 then raise exception 'Invalid herd snapshot'; end if;
 insert into public.breeder_connections values(p_connection,p_owner,p_version) on conflict(id) do nothing;
 select version into current_version from public.breeder_connections where id=p_connection and owner_user_id=p_owner for update;
 if not found then raise exception 'Connection owner mismatch'; end if;
 if current_version>p_version then return 0; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner::text,912));
 update public.breeder_connections set version=p_version where id=p_connection;
 -- Only hide rows created by this bridge. Original Show animals are retained.
 if coalesce(current_setting('ringmaster.resolve_single',true),'')<>'true' then
 update public.animal_import_reviews set decision='withdrawn' where provider='ringmaster_breeder' and connection_id=p_connection and decision='pending' and not exists(select 1 from jsonb_array_elements(p_animals) j where j->>'id'=external_animal_id);
 update public.animals a set deleted_at=now() from public.breeder_animal_links l where l.connection_id=p_connection and l.managed and a.id=l.animal_id and not exists(select 1 from jsonb_array_elements(p_animals) j where (j->>'id')::uuid=l.breeder_animal_id);
 end if;
 for row in select value from jsonb_array_elements(p_animals) loop
  aid=null;
  select animal_id into aid from public.breeder_animal_links where connection_id=p_connection and breeder_animal_id=(row->>'id')::uuid;
  if aid is not null and not exists(select 1 from public.animals where id=aid and owner_user_id=p_owner) then raise exception 'Mapped animal needs ownership review'; end if;
  if aid is null then
   row=partner_private.prepare(p_owner,'ringmaster_breeder',p_connection,row->>'id',row,clock_timestamp());
   if row is null then continue; end if;
   original=nullif(row->>'show_id','')::uuid;
   if original is not null then
    select id into aid from public.animals where id=original and owner_user_id=p_owner and deleted_at is null and not exists(select 1 from public.breeder_animal_links where animal_id=original) and not exists(select 1 from public.herdmaster_animal_links where animal_id=original);
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
create or replace function public.herdmaster_apply_animals(p_hash text, p_animals jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare c public.herdmaster_connections; item jsonb; link public.herdmaster_animal_links;
  a public.animals; aid uuid; mapped_variety text; mode text; breed_name text;
  applied integer=0; ignored integer=0; incoming_time timestamptz;
begin
  -- Serialize account writes, including revocation/rotation, before authorizing.
  perform 1 from public.herdmaster_connections where token_hash=p_hash for update;
  c=public.herdmaster_authorize(p_hash);
  perform pg_advisory_xact_lock(hashtextextended(c.owner_user_id::text,912));
  if p_animals is null or jsonb_typeof(p_animals)<>'array' or jsonb_array_length(p_animals)>500 then
    raise exception using errcode='22023', message='Expected up to 500 animals';
  end if;
  if exists(select 1 from jsonb_array_elements(p_animals) j group by j->>'id' having count(*)>1) then
    raise exception using errcode='22023', message='Duplicate animal IDs';
  end if;
  for item in select value from jsonb_array_elements(p_animals) loop
    if jsonb_typeof(item)<>'object' or coalesce(length(item->>'id'),0) not between 1 and 200
      or jsonb_typeof(item->'id')<>'string' or jsonb_typeof(item->'active') is distinct from 'boolean'
      or coalesce(item->>'updated_at','')='' then
      raise exception using errcode='22023', message='Animal requires id, active, and updated_at';
    end if;
    incoming_time=(item->>'updated_at')::timestamptz;
    select * into link from public.herdmaster_animal_links
      where connection_id=c.id and external_animal_id=item->>'id';
    if link.external_animal_id is not null and incoming_time<link.source_updated_at then
      ignored=ignored+1; continue;
    end if;
    if link.external_animal_id is not null and incoming_time=link.source_updated_at then
      if item<>link.source_payload then
        raise exception using errcode='23505', message='Animal timestamp conflicts with saved payload';
      end if;
      ignored=ignored+1; continue;
    end if;
    aid=link.animal_id;
    if not (item->>'active')::boolean then
     update public.animal_import_reviews set decision='withdrawn',updated_at=clock_timestamp() where connection_id=c.id and external_animal_id=item->>'id' and decision='pending' and source_version<=incoming_time;
    end if;
    if (item->>'active')::boolean then
      select b.name, to_jsonb(b)->>'variety_mode' into breed_name, mode
        from public.breeds b where lower(b.name)=lower(item->>'breed')
        and b.species::text=item->>'species' and coalesce(b.is_active,true)
        and (to_jsonb(b)->>'local_show_id') is null limit 1;
      if breed_name is null or item->>'species' not in ('rabbit','cavy')
        or item->>'sex' not in ('Buck','Doe','Boar','Sow')
        or (item->>'species'='rabbit' and item->>'sex' not in ('Buck','Doe'))
        or (item->>'species'='cavy' and item->>'sex' not in ('Boar','Sow'))
        or coalesce(trim(item->>'tattoo'),'')='' then
        raise exception using errcode='22023', message='Unknown breed or invalid species, sex, or tattoo';
      end if;
      mapped_variety=nullif(trim(item->>'variety'),'');
      if mode='lop_grouped' and mapped_variety is not null then
        mapped_variety=case when lower(mapped_variety) like '%broken%' or lower(mapped_variety) like '%tri-color%'
          or lower(mapped_variety) like '%tricolor%' or lower(coalesce(item->>'pattern','')) like '%broken%'
          then 'Broken' else 'Solid' end;
      end if;
      -- Populate the table's own type so enum and text historical schemas agree.
      select * into a from jsonb_populate_record(null::public.animals,
        jsonb_build_object('species',item->>'species','birth_date',item->'dob'));
      if aid is null then
        if link.external_animal_id is not null and coalesce((link.source_payload->>'active')::boolean,true) then raise exception 'Mapped animal needs review'; end if;
        item=partner_private.prepare(c.owner_user_id,c.provider,c.id,item->>'id',item,incoming_time);
        if item is null then continue; end if;
        if nullif(item->>'ringmaster_animal_id','') is not null then
          select id into aid from public.animals where id=(item->>'ringmaster_animal_id')::uuid
            and owner_user_id=c.owner_user_id and deleted_at is null
            and not exists(select 1 from public.herdmaster_animal_links where animal_id=public.animals.id)
            and not exists(select 1 from public.breeder_animal_links where animal_id=public.animals.id);
          if aid is null then raise exception using errcode='22023', message='Animal cannot be linked'; end if;
        else
          insert into public.animals(owner_user_id,species,name,tattoo,breed,variety,sex,birth_date,is_dob_unknown)
          values(c.owner_user_id,a.species,nullif(item->>'name',''),item->>'tattoo',breed_name,mapped_variety,
            item->>'sex',a.birth_date,a.birth_date is null) returning id into aid;
        end if;
        insert into public.herdmaster_animal_links(connection_id,external_animal_id,animal_id,source_updated_at,source_payload,managed)
          values(c.id,item->>'id',aid,incoming_time,item,nullif(item->>'ringmaster_animal_id','') is null)
          on conflict(connection_id,external_animal_id) do update set animal_id=excluded.animal_id,managed=excluded.managed;
      else
        if not exists(select 1 from public.animals where id=aid and owner_user_id=c.owner_user_id) then
          raise exception using errcode='22023', message='Animal ownership changed';
        end if;
      end if;
      update public.animals set name=nullif(item->>'name',''),tattoo=item->>'tattoo',breed=breed_name,
        species=a.species,variety=mapped_variety,sex=item->>'sex',birth_date=a.birth_date,
        is_dob_unknown=a.birth_date is null,deleted_at=null,updated_at=now() where id=aid and owner_user_id=c.owner_user_id;
    else
      if aid is null then
        -- Store a tombstone to prevent a stale active update creating an animal.
        insert into public.herdmaster_animal_links(connection_id,external_animal_id,source_updated_at,source_payload)
          values(c.id,item->>'id',incoming_time,item)
          on conflict(connection_id,external_animal_id) do nothing;
      else
        update public.animals set deleted_at=now(),updated_at=now()
          where id=aid and owner_user_id=c.owner_user_id and link.managed;
      end if;
    end if;
    update public.herdmaster_animal_links set source_updated_at=incoming_time,source_payload=(select value from jsonb_array_elements(p_animals) where value->>'id'=item->>'id')
      where connection_id=c.id and external_animal_id=item->>'id';
    applied=applied+1;
  end loop;
  return jsonb_build_object('applied',applied,'ignored',ignored,'pending_reviews',(select count(*) from public.animal_import_reviews where connection_id=c.id and decision='pending'));
end $$;


create function public.animal_import_review(p_action text,p_id uuid default null,p_target uuid default null,p_version timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.animal_import_reviews; c public.herdmaster_connections; bc public.breeder_connections; result jsonb; who uuid=auth.uid();
begin
 if who is null or not exists(select 1 from auth.users where id=who and email_confirmed_at is not null and deleted_at is null and (banned_until is null or banned_until<now())) then raise exception 'Verified account required'; end if;
 if p_action='list' then
  return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('candidates',partner_private.candidates(who,r.payload)) order by r.updated_at) from public.animal_import_reviews r
   where r.owner_user_id=who and r.decision='pending'
   and ((r.provider='ringmaster_breeder' and exists(select 1 from public.breeder_connections where id=r.connection_id and owner_user_id=who))
    or (r.provider<>'ringmaster_breeder' and exists(select 1 from public.herdmaster_connections where id=r.connection_id and owner_user_id=who and revoked_at is null)))
  ),'[]');
 end if;
 if p_action not in ('link','separate') then raise exception 'Invalid review action'; end if;
 select * into q from public.animal_import_reviews where id=p_id and owner_user_id=who;
 if q.id is null then raise exception 'Review not found'; end if;
 -- Match the import lock order: connection, owner, then review row.
 if q.provider='ringmaster_breeder' then
  select * into bc from public.breeder_connections where id=q.connection_id and owner_user_id=who for update;
  if bc.id is null then raise exception 'Connection unavailable'; end if;
 else
  select * into c from public.herdmaster_connections where id=q.connection_id and owner_user_id=who and revoked_at is null and expires_at>now() for update;
  if c.id is null then raise exception 'Reconnect the partner account'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(who::text,912));
 select * into q from public.animal_import_reviews where id=p_id and owner_user_id=who for update;
 if q.decision in ('link','separate') then
  if q.decision<>p_action or (p_action='link' and q.target_id is distinct from p_target) then raise exception 'Review was already resolved differently'; end if;
  return jsonb_build_object('resolved',true);
 end if;
 if q.decision<>'pending' or p_version is null or q.updated_at<>p_version then raise exception 'Review changed; reload before confirming'; end if;
 if p_action='link' and (p_target is null or not exists(select 1 from public.animals where id=p_target and owner_user_id=who and deleted_at is null and species::text=q.payload->>'species')) then raise exception 'Selected animal is unavailable'; end if;
 if p_action='separate' and p_target is not null then raise exception 'Separate record must not select a target'; end if;
 if p_action='link' then perform 1 from public.animals where id=p_target and owner_user_id=who for update; end if;
 update public.animal_import_reviews set decision=p_action,target_id=p_target where id=q.id;
 if q.provider='ringmaster_breeder' then
  perform set_config('ringmaster.resolve_single','true',true);
  perform public.apply_breeder_animals(q.connection_id,who,bc.version,jsonb_build_array(q.payload));
  perform set_config('ringmaster.resolve_single','false',true);
 else
  result=public.herdmaster_apply_animals(c.token_hash,jsonb_build_array(q.payload));
 end if;
 update public.animal_import_reviews set resolved_at=clock_timestamp(),target_id=case when q.provider='ringmaster_breeder' then (select animal_id from public.breeder_animal_links where connection_id=q.connection_id and breeder_animal_id=q.external_animal_id::uuid) else (select animal_id from public.herdmaster_animal_links where connection_id=q.connection_id and external_animal_id=q.external_animal_id) end where id=q.id;
 return jsonb_build_object('resolved',true);
end $$;
revoke all on function public.animal_import_review(text,uuid,uuid,timestamptz) from public,anon;
grant execute on function public.animal_import_review(text,uuid,uuid,timestamptz) to authenticated;
revoke all on all functions in schema partner_private from public,anon,authenticated;
grant usage on schema partner_private to service_role;
grant execute on all functions in schema partner_private to service_role;

create function public.partner_existing_animals(p_hash text,p_after uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.herdmaster_connections; rows jsonb;
begin
 c=public.herdmaster_authorize(p_hash);
 if not c.existing_animals_consent then raise exception using errcode='42501',message='Reconnect with existing animal matching consent'; end if;
 rows=partner_private.candidates(c.owner_user_id,'{}',p_after,true);
 return jsonb_build_object('data',rows,'next_after',case when jsonb_array_length(rows)=500 then rows->499->>'ringmaster_animal_id' else null end);
end $$;
revoke all on function public.partner_existing_animals(text,uuid) from public,anon,authenticated;
grant execute on function public.partner_existing_animals(text,uuid) to service_role;
-- The legacy animal trigger must also work under the review RPC's empty search path.
create or replace function public.enforce_lop_varieties() returns trigger
language plpgsql set search_path='' as $$
declare v_mode text;
begin
 select variety_mode into v_mode from public.breeds where lower(name)=lower(new.breed) limit 1;
 if v_mode='lop_grouped' and lower(new.variety) not in ('broken','solid') then raise exception 'Lop breeds must be Broken or Solid.';end if;
 return new;
end $$;
