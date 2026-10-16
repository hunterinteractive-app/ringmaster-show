-- Account-scoped partner credentials never grant direct table access.
create table public.herdmaster_connections (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  external_account_id text not null check (length(external_account_id) between 1 and 200),
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (owner_user_id, external_account_id)
);
create table public.herdmaster_animal_links (
  connection_id uuid not null references public.herdmaster_connections(id) on delete cascade,
  external_animal_id text not null check (length(external_animal_id) between 1 and 200),
  animal_id uuid unique references public.animals(id) on delete set null,
  source_updated_at timestamptz not null,
  source_payload jsonb not null,
  managed boolean not null default true,
  primary key (connection_id, external_animal_id)
);
alter table public.herdmaster_connections enable row level security;
alter table public.herdmaster_animal_links enable row level security;
revoke all on public.herdmaster_connections, public.herdmaster_animal_links from public, anon, authenticated;
grant all on public.herdmaster_connections, public.herdmaster_animal_links to service_role;

create function public.herdmaster_authorize(p_hash text)
returns public.herdmaster_connections language plpgsql security invoker set search_path = '' as $$
declare c public.herdmaster_connections;
begin
  select hc.* into c from public.herdmaster_connections hc
  join auth.users u on u.id=hc.owner_user_id
  where hc.token_hash=p_hash and hc.revoked_at is null and hc.expires_at>now()
    and u.email_confirmed_at is not null and u.deleted_at is null
    and (u.banned_until is null or u.banned_until<now()) for share of hc;
  if c.id is null then raise exception using errcode='28000', message='Invalid connection token'; end if;
  return c;
end $$;

create function public.herdmaster_apply_animals(p_hash text, p_animals jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare c public.herdmaster_connections; item jsonb; link public.herdmaster_animal_links;
  a public.animals; aid uuid; mapped_variety text; mode text; breed_name text;
  applied integer=0; ignored integer=0; incoming_time timestamptz;
begin
  -- Serialize account writes, including revocation/rotation, before authorizing.
  perform 1 from public.herdmaster_connections where token_hash=p_hash for update;
  c=public.herdmaster_authorize(p_hash);
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
    update public.herdmaster_animal_links set source_updated_at=incoming_time,source_payload=item
      where connection_id=c.id and external_animal_id=item->>'id';
    applied=applied+1;
  end loop;
  return jsonb_build_object('applied',applied,'ignored',ignored);
end $$;

create function public.herdmaster_export(p_hash text, p_kind text, p_after uuid default null)
returns table(id uuid, payload jsonb) language plpgsql security invoker set search_path = '' as $$
declare c public.herdmaster_connections;
begin
  c=public.herdmaster_authorize(p_hash);
  if p_kind='catalog' then
    return query select b.id,jsonb_build_object('breed_id',b.id,'breed',b.name,'species',b.species,
      'variety_mode',to_jsonb(b)->'variety_mode') from public.breeds b
    where coalesce(b.is_active,true) and (to_jsonb(b)->>'local_show_id') is null
      and (p_after is null or b.id>p_after) order by b.id limit 500;
  elsif p_kind='results' then
    return query select e.id, jsonb_build_object(
      'entry_id',e.id,'herdmaster_animal_id',l.external_animal_id,'ringmaster_animal_id',e.animal_id,
      'show_id',e.show_id,'show_name',s.name,'show_date',s.start_date,'location',s.location_name,
      'exhibitor_id',e.exhibitor_id,'species',e.species,'tattoo',e.tattoo,'animal_name',e.animal_name,
      'breed',e.breed,'variety',e.variety,'sex',e.sex,'class_name',e.class_name,
      'placement',e.placement,'special_awards',e.special_awards,'result_status',e.result_status,
      'is_shown',e.is_shown,'is_disqualified',e.is_disqualified,'disqualified_reason',e.disqualified_reason,
      'scratched_at',e.scratched_at,'is_fur',e.is_fur,'fur_placement',e.fur_placement,'fur_award',to_jsonb(e)->'fur_award',
      'result_details',(select coalesce(jsonb_agg(jsonb_build_object('placing_label',r.placing_label,
        'award',r.award,'legs_awarded',to_jsonb(r)->'legs_awarded') order by r.created_at desc,r.id),'[]'::jsonb)
        from public.results r where r.entry_id=e.id and r.show_id=e.show_id),
      'entry_awards',(select coalesce(jsonb_agg(jsonb_build_object('award_code',w.award_code) order by w.award_code),'[]'::jsonb)
        from public.entry_awards w where w.entry_id=e.id))
    from public.entries e join public.shows s on s.id=e.show_id
    join public.herdmaster_animal_links l on l.animal_id=e.animal_id and l.connection_id=c.id
    left join public.exhibitors ex on ex.id=e.exhibitor_id
    where not coalesce(e.is_test,false) and not coalesce(s.is_test,false) and not coalesce(s.is_demo,false)
      and (p_after is null or e.id>p_after)
      and (e.exhibitor_user_id=c.owner_user_id or ex.owner_user_id=c.owner_user_id or ex.claimed_by_user_id=c.owner_user_id)
      and exists(select 1 from public.show_report_artifacts a where a.show_id=e.show_id
        and a.metadata->>'exhibitor_id'=e.exhibitor_id::text and a.report_name::text='exhibitor_report'
        and a.artifact_status::text='generated' and a.is_current and a.storage_path is not null and a.storage_bucket is not null)
    order by e.id limit 500;
  elsif p_kind='reports' then
    return query select a.id,jsonb_build_object('report_id',a.id,'show_id',s.id,'show_name',s.name,
      'show_date',s.start_date,'report_name',a.report_name,'exhibitor_id',a.metadata->>'exhibitor_id',
      'file_name',a.file_name,'generated_at',a.generated_at,'storage_bucket',a.storage_bucket,'storage_path',a.storage_path)
    from public.show_report_artifacts a join public.shows s on s.id=a.show_id
    left join public.exhibitors ex on ex.id::text=a.metadata->>'exhibitor_id'
    where a.report_name::text in ('exhibitor_report','legs') and a.artifact_status::text='generated'
      and a.is_current and a.storage_bucket is not null and a.storage_path is not null
      and not coalesce(s.is_test,false) and not coalesce(s.is_demo,false) and (p_after is null or a.id>p_after)
      and (ex.owner_user_id=c.owner_user_id or ex.claimed_by_user_id=c.owner_user_id or exists(
        select 1 from public.entries e where e.show_id=a.show_id and e.exhibitor_id::text=a.metadata->>'exhibitor_id'
          and e.exhibitor_user_id=c.owner_user_id and not coalesce(e.is_test,false)))
    order by a.id limit 500;
  else raise exception using errcode='22023',message='Unknown export';
  end if;
end $$;

revoke all on function public.herdmaster_authorize(text),public.herdmaster_apply_animals(text,jsonb),public.herdmaster_export(text,text,uuid) from public,anon,authenticated;
grant execute on function public.herdmaster_authorize(text),public.herdmaster_apply_animals(text,jsonb),public.herdmaster_export(text,text,uuid) to service_role;
