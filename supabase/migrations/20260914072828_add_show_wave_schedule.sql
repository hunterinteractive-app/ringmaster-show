-- Wave schedules reuse the BBOS secretary allowlist and normal show permissions.
create schema if not exists show_waves_private;
revoke all on schema show_waves_private from public, anon;
grant usage on schema show_waves_private to authenticated, service_role;

create table public.show_wave_settings (
  show_id uuid primary key references public.shows(id) on delete cascade,
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
create table public.show_waves (
  id uuid primary key default gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  wave_number integer not null check (wave_number between 1 and 50),
  checkin_starts_at timestamptz,
  checkin_ends_at timestamptz,
  show_date date,
  checkout_date date,
  email_lead_hours integer not null default 24 check (email_lead_hours in (1,2,5,10,15,20,24,48,72)),
  sheets_emailed_at timestamptz,
  sheets_started_at timestamptz,
  email_error text,
  unique (show_id,id),
  unique (show_id,wave_number) deferrable initially deferred,
  check (checkin_starts_at < checkin_ends_at),
  check (checkout_date >= show_date)
);
create table public.show_wave_breeds (
  show_id uuid not null references public.shows(id) on delete cascade,
  species text not null check (species in ('rabbit','cavy')),
  breed_name text not null check (btrim(breed_name) <> ''),
  breed_key text generated always as (lower(btrim(breed_name))) stored,
  wave_id uuid not null,
  primary key (show_id,species,breed_key),
  foreign key (show_id,wave_id) references public.show_waves(show_id,id) on delete cascade
);
create index show_wave_breeds_wave_idx on public.show_wave_breeds(show_id,wave_id);
create index show_waves_due_idx on public.show_waves(checkin_starts_at,checkin_ends_at);

alter table public.show_wave_settings enable row level security;
alter table public.show_waves enable row level security;
alter table public.show_wave_breeds enable row level security;
revoke all on public.show_wave_settings, public.show_waves, public.show_wave_breeds from public,anon,authenticated;
grant select on public.show_wave_settings, public.show_waves, public.show_wave_breeds to authenticated;
grant all on public.show_wave_settings, public.show_waves, public.show_wave_breeds to service_role;
create policy wave_settings_read on public.show_wave_settings for select to authenticated
 using ((select auth.uid()) is not null and (public.user_can_manage_show_settings(show_id) or public.user_can_manage_entries(show_id)));
create policy waves_read on public.show_waves for select to authenticated
 using ((select auth.uid()) is not null and (public.user_can_manage_show_settings(show_id) or public.user_can_manage_entries(show_id)));
create policy wave_breeds_read on public.show_wave_breeds for select to authenticated
 using ((select auth.uid()) is not null and (public.user_can_manage_show_settings(show_id) or public.user_can_manage_entries(show_id)));

create function show_waves_private.enabled(p_show_id uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select coalesce((select enabled from public.show_wave_settings where show_id=p_show_id),false);
$$;
create function show_waves_private.active_wave(p_show_id uuid)
returns uuid language sql stable security invoker set search_path='' as $$
 select w.id from public.show_waves w
 where w.show_id=p_show_id and show_waves_private.enabled(p_show_id)
   and now() >= w.checkin_starts_at and now() < w.checkin_ends_at
 order by w.wave_number limit 1;
$$;
create function show_waves_private.breed_wave(p_show_id uuid,p_species text,p_breed text)
returns uuid language sql stable security invoker set search_path='' as $$
 select wave_id from public.show_wave_breeds
 where show_id=p_show_id and species=lower(btrim(p_species)) and breed_key=lower(btrim(p_breed));
$$;
create function show_waves_private.entry_allowed(p_show_id uuid,p_species text,p_breed text)
returns boolean language sql stable security invoker set search_path='' as $$
 select not show_waves_private.enabled(p_show_id) or coalesce(
   show_waves_private.breed_wave(p_show_id,p_species,p_breed)=show_waves_private.active_wave(p_show_id),false);
$$;
create function show_waves_private.record_current(p_show_id uuid,p_wave_id uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select case when show_waves_private.enabled(p_show_id)
   then p_wave_id=show_waves_private.active_wave(p_show_id) else p_wave_id is null end;
$$;

-- Existing check-in records and receipt IDs remain intact. NULL is the legacy
-- whole-show scope; scheduled shows get a separate record per wave.
alter table public.show_checkin_records add column wave_id uuid;
alter table public.show_checkin_sessions add column wave_id uuid;
alter table public.show_checkin_change_requests add column wave_id uuid;
alter table public.auto_checkin_email_deliveries add column wave_id uuid;
do $$ declare t text; begin
 foreach t in array array['show_checkin_records','show_checkin_sessions','show_checkin_change_requests','auto_checkin_email_deliveries'] loop
   execute format('alter table public.%I add constraint %I foreign key(show_id,wave_id) references public.show_waves(show_id,id)',t,t||'_wave_fkey');
   execute format('create index %I on public.%I(show_id,wave_id)',t||'_wave_idx',t);
 end loop;
end $$;
alter table public.show_checkin_records drop constraint show_checkin_records_show_id_exhibitor_id_key;
alter table public.show_checkin_records add constraint show_checkin_records_scope_key unique nulls not distinct (show_id,exhibitor_id,wave_id);
alter table public.auto_checkin_email_deliveries drop constraint auto_checkin_email_deliveries_pkey;
alter table public.auto_checkin_email_deliveries add column delivery_id uuid primary key default gen_random_uuid();
create index auto_checkin_email_deliveries_exhibitor_idx on public.auto_checkin_email_deliveries(exhibitor_id);
alter table public.auto_checkin_email_deliveries add constraint auto_checkin_email_delivery_scope_key unique nulls not distinct (show_id,exhibitor_id,wave_id);

create function show_waves_private.assign_checkin_wave()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if show_waves_private.enabled(new.show_id) and new.wave_id is null then
   new.wave_id := show_waves_private.active_wave(new.show_id);
   if new.wave_id is null then raise exception 'No wave is currently open for check-in.'; end if;
 end if;
 return new;
end $$;
create trigger assign_checkin_record_wave before insert on public.show_checkin_records for each row execute function show_waves_private.assign_checkin_wave();
create trigger assign_checkin_session_wave before insert on public.show_checkin_sessions for each row execute function show_waves_private.assign_checkin_wave();
create trigger assign_checkin_request_wave before insert on public.show_checkin_change_requests for each row execute function show_waves_private.assign_checkin_wave();

create function show_waves_private.require_session(p_token text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare s public.show_checkin_sessions%rowtype; cfg public.show_checkin_settings%rowtype;
begin
 select * into s from public.show_checkin_sessions
 where session_token_hash=encode(extensions.digest(btrim(coalesce(p_token,'')),'sha256'),'hex')
   and revoked_at is null and expires_at>now();
 if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
 if show_waves_private.enabled(s.show_id) then
   select * into cfg from public.show_checkin_settings where show_id=s.show_id;
   if not coalesce(cfg.is_enabled,false) or s.wave_id is null
      or s.wave_id is distinct from show_waves_private.active_wave(s.show_id) then
     raise exception 'This wave is not currently open for check-in.' using errcode='42501';
   end if;
   if not exists(select 1 from public.entries e where e.show_id=s.show_id and e.exhibitor_id=s.exhibitor_id
      and e.scratched_at is null and show_waves_private.entry_allowed(e.show_id,e.species::text,e.breed)) then
     raise exception 'You have no animals in the active check-in wave. View all your entries in the Entries tab of your account.';
   end if;
 end if;
 return s.wave_id;
end $$;
create function show_waves_private.guard_entry_request(p_token text,p_entry_id uuid,p_changes jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare s public.show_checkin_sessions%rowtype; e public.entries%rowtype; b public.breeds%rowtype; species text; breed text;
begin
 perform show_waves_private.require_session(p_token);
 select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_token,'')),'sha256'),'hex');
 if not show_waves_private.enabled(s.show_id) then return; end if;
 if p_entry_id is not null then
   select * into e from public.entries where id=p_entry_id and show_id=s.show_id and exhibitor_id=s.exhibitor_id;
   if not found or not show_waves_private.entry_allowed(s.show_id,e.species::text,e.breed) then
     raise exception 'This animal is not in the active check-in wave.' using errcode='42501';
   end if;
 end if;
 species := coalesce(nullif(p_changes->>'species',''),e.species::text,'rabbit');
 breed := coalesce(nullif(p_changes->>'breed',''),e.breed);
 if nullif(p_changes->>'breed_id','') is not null then
   select * into b from public.breeds where id=(p_changes->>'breed_id')::uuid;
   breed := b.name; species := b.species;
 end if;
 if not show_waves_private.entry_allowed(s.show_id,species,breed) then
   raise exception 'Choose a breed assigned to the active check-in wave.' using errcode='42501';
 end if;
end $$;

create function show_waves_private.schedule(p_show_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare zone text; waves jsonb; breeds jsonb;
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' and ((select auth.uid()) is null or not (public.user_can_manage_show_settings(p_show_id) or public.user_can_manage_entries(p_show_id))) then
   raise exception 'You do not have permission to view this show schedule.' using errcode='42501';
 end if;
 select coalesce(nullif(timezone,''),'America/Indiana/Indianapolis') into zone from public.shows where id=p_show_id;
 select coalesce(jsonb_agg(to_jsonb(w) || jsonb_build_object(
   'checkin_start_local',to_char(w.checkin_starts_at at time zone zone,'YYYY-MM-DD"T"HH24:MI:SS'),
   'checkin_end_local',to_char(w.checkin_ends_at at time zone zone,'YYYY-MM-DD"T"HH24:MI:SS')) order by w.wave_number),'[]') into waves
 from public.show_waves w where w.show_id=p_show_id;
 select coalesce(jsonb_agg(jsonb_build_object('species',b.species,'breed_name',b.name,'wave_id',a.wave_id) order by lower(b.name),b.species),'[]') into breeds
 from (
   select species,min(name) name from (
     select lower(species::text) species,btrim(name) name from public.breeds
     where coalesce(is_active,true) and (local_show_id is null or local_show_id=p_show_id)
     union all select lower(species::text),btrim(breed) from public.entries where show_id=p_show_id and nullif(btrim(breed),'') is not null
     union all select species,breed_name from public.show_wave_breeds where show_id=p_show_id
     union all select lower(i.species::text),btrim(i.breed) from public.entry_cart_items i join public.entry_carts c on c.id=i.cart_id where c.show_id=p_show_id and not i.is_checkin_fee_carrier and nullif(btrim(i.breed),'') is not null
   ) catalog group by species,lower(name)
 ) b left join public.show_wave_breeds a on a.show_id=p_show_id and a.species=b.species and a.breed_key=lower(b.name)
 where b.species in ('rabbit','cavy');
 return jsonb_build_object('enabled',show_waves_private.enabled(p_show_id),'timezone',zone,'waves',waves,'breeds',breeds,
   'active_wave_id',show_waves_private.active_wave(p_show_id),'can_configure',public.can_configure_best_opposite_final_award(p_show_id));
end $$;
create function public.get_show_wave_schedule(p_show_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$ select show_waves_private.schedule(p_show_id); $$;

create function show_waves_private.save_schedule(p_show_id uuid,p_enabled boolean,p_waves jsonb,p_breeds jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare zone text; item jsonb; wid uuid; old_enabled boolean; old_assignments jsonb; local_time timestamp; field text;
begin
 if (select auth.uid()) is null or not public.can_configure_best_opposite_final_award(p_show_id) then
   raise exception 'Wave Schedule is only available for selected secretaries’ shows.' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('wave-schedule:'||p_show_id::text,0));
 select coalesce(nullif(timezone,''),'America/Indiana/Indianapolis') into zone from public.shows
 where id=p_show_id and not coalesce(is_locked,false) and finalized_at is null for update;
 if not found then raise exception 'This show is locked or finalized.'; end if;
 if jsonb_typeof(p_waves) <> 'array' or jsonb_typeof(p_breeds) <> 'array' or jsonb_array_length(p_waves)>50 then
   raise exception 'A valid wave schedule is required.';
 end if;
 old_enabled := show_waves_private.enabled(p_show_id);
 select coalesce(jsonb_agg(jsonb_build_object('species',species,'breed_key',breed_key,'wave_id',wave_id) order by species,breed_key),'[]')
 into old_assignments from public.show_wave_breeds where show_id=p_show_id;
 for item in select value from jsonb_array_elements(p_waves) loop
   wid := (item->>'id')::uuid;
   foreach field in array array['checkin_start_local','checkin_end_local'] loop
     local_time := nullif(item->>field,'')::timestamp;
     if (local_time at time zone zone) at time zone zone is distinct from local_time then
       raise exception 'That check-in time does not exist in the show timezone because of daylight saving time. Choose another time.';
     end if;
   end loop;
   if exists(select 1 from public.show_waves where id=wid and show_id<>p_show_id) then raise exception 'Invalid wave.'; end if;
   insert into public.show_waves(id,show_id,wave_number,checkin_starts_at,checkin_ends_at,show_date,checkout_date,email_lead_hours)
   values(wid,p_show_id,(item->>'wave_number')::integer,
     nullif(item->>'checkin_start_local','')::timestamp at time zone zone,
     nullif(item->>'checkin_end_local','')::timestamp at time zone zone,
     nullif(item->>'show_date','')::date,nullif(item->>'checkout_date','')::date,
     coalesce((item->>'email_lead_hours')::integer,24))
   on conflict(id) do update set wave_number=excluded.wave_number,checkin_starts_at=excluded.checkin_starts_at,
     checkin_ends_at=excluded.checkin_ends_at,show_date=excluded.show_date,checkout_date=excluded.checkout_date,email_lead_hours=excluded.email_lead_hours;
 end loop;
 delete from public.show_wave_breeds where show_id=p_show_id;
 insert into public.show_wave_breeds(show_id,species,breed_name,wave_id)
 select p_show_id,lower(btrim(value->>'species')),btrim(value->>'breed_name'),(value->>'wave_id')::uuid
 from jsonb_array_elements(p_breeds) where nullif(value->>'wave_id','') is not null;
 delete from public.show_waves where show_id=p_show_id and id not in (select (value->>'id')::uuid from jsonb_array_elements(p_waves));
 if exists(select 1 from public.show_waves where show_id=p_show_id and sheets_started_at is not null)
    or exists(select 1 from public.auto_checkin_email_deliveries where show_id=p_show_id and wave_id is not null)
    or exists(select 1 from public.show_checkin_records where show_id=p_show_id and wave_id is not null) then
   if not p_enabled or exists (select 1 from jsonb_array_elements(old_assignments) old where not exists (select 1 from public.show_wave_breeds b where b.show_id=p_show_id and b.species=old->>'species' and b.breed_key=old->>'breed_key' and b.wave_id=(old->>'wave_id')::uuid)) then
     raise exception 'Breed assignments cannot change after wave sheets have been prepared or check-in has begun.';
   end if;
 end if;
 if p_enabled then
   if not exists(select 1 from public.show_waves where show_id=p_show_id) then raise exception 'Add at least one wave.'; end if;
   if exists(select 1 from public.show_waves where show_id=p_show_id and (checkin_starts_at is null or checkin_ends_at is null or show_date is null or checkout_date is null)) then
     raise exception 'Complete the check-in start, check-in end, show date, and check-out date for every wave.';
   end if;
   if exists(select 1 from public.show_waves where show_id=p_show_id and (checkin_starts_at at time zone zone)::date > show_date) then
     raise exception 'A wave must check in on or before its show date.';
   end if;
   if exists(select 1 from public.show_waves a join public.show_waves b on a.show_id=b.show_id and a.id<b.id
     where a.show_id=p_show_id and tstzrange(a.checkin_starts_at,a.checkin_ends_at,'[)') && tstzrange(b.checkin_starts_at,b.checkin_ends_at,'[)')) then
     raise exception 'Wave check-in windows cannot overlap.';
   end if;
   if exists(select 1 from public.entries e where e.show_id=p_show_id and e.scratched_at is null
      and show_waves_private.breed_wave(p_show_id,e.species::text,e.breed) is null)
     or exists(select 1 from public.entry_cart_items i join public.entry_carts c on c.id=i.cart_id
       where c.show_id=p_show_id and not i.is_checkin_fee_carrier
         and show_waves_private.breed_wave(p_show_id,i.species::text,i.breed) is null) then
     raise exception 'Assign every breed with entries or saved carts to a wave before enabling the schedule.';
   end if;
 end if;
 insert into public.show_wave_settings(show_id,enabled) values(p_show_id,p_enabled)
 on conflict(show_id) do update set enabled=excluded.enabled,updated_at=now();
 if p_enabled and not old_enabled then
   update public.shows set auto_email_checkin_sheets=true where id=p_show_id;
   update public.show_checkin_sessions set revoked_at=now() where show_id=p_show_id and revoked_at is null;
 end if;
end $$;
create function public.save_show_wave_schedule(p_show_id uuid,p_enabled boolean,p_waves jsonb,p_breeds jsonb)
returns void language sql security invoker set search_path='' as $$ select show_waves_private.save_schedule(p_show_id,p_enabled,p_waves,p_breeds); $$;

create function public.due_checkin_email_waves()
returns setof public.show_waves language sql stable security invoker set search_path='' as $$
 select w.* from public.show_waves w join public.show_wave_settings cfg on cfg.show_id=w.show_id and cfg.enabled
 join public.shows s on s.id=w.show_id
 where s.auto_email_checkin_sheets and not coalesce(s.email_sending_disabled,false)
   and now() >= w.checkin_starts_at-make_interval(hours=>w.email_lead_hours) and now()<w.checkin_ends_at
 order by w.sheets_emailed_at nulls first,w.checkin_starts_at,w.id limit 20;
$$;

-- Freeze the assigned breeds before the worker reads entries. This uses the
-- same transaction lock as schedule edits, so prepared payloads cannot race a
-- reassignment. Only the trusted mail worker can begin preparation.
create function public.begin_wave_checkin_email(p_wave_id uuid)
returns setof public.show_waves language plpgsql security invoker set search_path='' as $$
declare sid uuid;
begin
 select show_id into sid from public.show_waves where id=p_wave_id;
 if sid is null then return; end if;
 perform pg_advisory_xact_lock(hashtextextended('wave-schedule:'||sid::text,0));
 return query update public.show_waves w set sheets_started_at=coalesce(w.sheets_started_at,now())
 from public.show_wave_settings cfg,public.shows s
 where w.id=p_wave_id and cfg.show_id=w.show_id and cfg.enabled and s.id=w.show_id
   and s.auto_email_checkin_sheets and not coalesce(s.email_sending_disabled,false)
   and now()>=w.checkin_starts_at-make_interval(hours=>w.email_lead_hours) and now()<w.checkin_ends_at
 returning w.*;
end $$;
revoke all on function public.begin_wave_checkin_email(uuid) from public,anon,authenticated;
grant execute on function public.begin_wave_checkin_email(uuid) to service_role;

-- Prevent later entries from silently disappearing from every wave. This
-- internal trigger also covers cart finalization and secretary entry edits.
create function show_waves_private.require_assigned_breed()
returns trigger language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
 if tg_table_name='entry_cart_items' then
   if new.is_checkin_fee_carrier then return new; end if;
   select show_id into sid from public.entry_carts where id=new.cart_id;
 else
   if new.scratched_at is not null or lower(coalesce(new.status,''))='scratched' then return new; end if;
   sid := new.show_id;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('wave-schedule:'||sid::text,0));
 if show_waves_private.enabled(sid)
    and show_waves_private.breed_wave(sid,new.species::text,new.breed) is null then
   raise exception 'This breed has not been assigned to a wave. Ask the show secretary to assign it in Wave Schedule before entering.';
 end if;
 return new;
end $$;
create trigger entries_require_wave_breed before insert or update of show_id,species,breed,scratched_at,status
on public.entries for each row execute function show_waves_private.require_assigned_breed();
create trigger cart_items_require_wave_breed before insert or update of cart_id,species,breed,is_checkin_fee_carrier
on public.entry_cart_items for each row execute function show_waves_private.require_assigned_breed();

-- Private routines are available only through permission-checked wrappers or
-- existing token-authenticated check-in RPCs running as their owner.
revoke all on all functions in schema show_waves_private from public,anon,authenticated;
grant execute on function show_waves_private.schedule(uuid) to authenticated,service_role;
grant execute on function show_waves_private.save_schedule(uuid,boolean,jsonb,jsonb) to authenticated;
revoke all on function public.get_show_wave_schedule(uuid), public.save_show_wave_schedule(uuid,boolean,jsonb,jsonb), public.due_checkin_email_waves() from public,anon,authenticated;
grant execute on function public.get_show_wave_schedule(uuid) to authenticated,service_role;
grant execute on function public.save_show_wave_schedule(uuid,boolean,jsonb,jsonb) to authenticated;
grant execute on function public.due_checkin_email_waves() to service_role;

-- Updated check-in RPCs retain existing authorization and payment handling.
CREATE OR REPLACE FUNCTION public.authenticate_exhibitor_checkin(p_portal_token text, p_exhibitor_number text, p_last_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_settings public.show_checkin_settings%rowtype;
  v_exhibitor_id uuid;
  v_session_id uuid;
  v_session_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires_at timestamptz := now() + interval '30 minutes';
begin
  select * into v_settings
  from public.show_checkin_settings
  where portal_token_hash = encode(
    extensions.digest(btrim(coalesce(p_portal_token, '')), 'sha256'),
    'hex'
  )
  for update;

  if not found
     or not v_settings.is_enabled
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.opens_at is not null and now() < v_settings.opens_at)
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.closes_at is not null and now() > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;

  select e.id into v_exhibitor_id
  from public.exhibitors e
  where btrim(e.exhibitor_number::text)
      = btrim(coalesce(p_exhibitor_number, ''))
    and lower(btrim(coalesce(e.last_name, '')))
      = lower(btrim(coalesce(p_last_name, '')))
    and exists (
      select 1 from public.entries en
      where en.show_id = v_settings.show_id and en.exhibitor_id = e.id and show_waves_private.entry_allowed(en.show_id,en.species::text,en.breed)
    )
  order by e.created_at
  limit 1;

  if v_exhibitor_id is null then
    raise exception 'We could not verify those check-in details';
  end if;

  update public.show_checkin_sessions
  set revoked_at = now()
  where show_id = v_settings.show_id
    and exhibitor_id = v_exhibitor_id
    and revoked_at is null;

  insert into public.show_checkin_sessions(
    show_id, exhibitor_id, session_token_hash, expires_at
  ) values (
    v_settings.show_id,
    v_exhibitor_id,
    encode(extensions.digest(v_session_token, 'sha256'), 'hex'),
    v_expires_at
  ) returning id into v_session_id;

  insert into public.show_checkin_audit_events(
    show_id, exhibitor_id, event_type, actor_type, session_id, details
  ) values (
    v_settings.show_id, v_exhibitor_id, 'identity_verified',
    'exhibitor_portal', v_session_id,
    jsonb_build_object('expires_at', v_expires_at)
  );

  return jsonb_build_object(
    'session_token', v_session_token,
    'expires_at', v_expires_at,
    'show_id', v_settings.show_id,
    'exhibitor_id', v_exhibitor_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_exhibitor_checkin_change_request(p_session_token text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_request public.show_checkin_change_requests%rowtype;
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now()
  for update;
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  select * into v_request from public.show_checkin_change_requests
  where wave_id is not distinct from v_session.wave_id and id = p_request_id and show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id
  for update;
  if not found then raise exception 'Change request not found.' using errcode = '22023'; end if;
  if v_request.status not in ('submitted', 'pending_payment', 'pending_review') then
    raise exception 'This request can no longer be cancelled.' using errcode = '22023';
  end if;

  update public.show_checkin_change_requests
  set status = 'cancelled', updated_at = now()
  where id = v_request.id;
  insert into public.show_checkin_audit_events (
    show_id, exhibitor_id, event_type, actor_type, session_id, details
  ) values (
    v_session.show_id, v_session.exhibitor_id, 'change_request_cancelled', 'exhibitor_portal', v_session.id,
    jsonb_build_object('change_request_id', v_request.id)
  );
  return jsonb_build_object('id', v_request.id, 'status', 'cancelled');
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_checkin_receipt_delivery(p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_record public.show_checkin_records%rowtype;
  v_delivery public.show_checkin_receipt_deliveries%rowtype;
  v_exhibitor public.exhibitors%rowtype;
  v_show public.shows%rowtype;
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now();
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  select * into v_record
  from public.show_checkin_records
  where show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id and show_waves_private.record_current(show_id,wave_id)
  for update;
  if not found or v_record.status <> 'completed' or v_record.receipt_preference <> 'email_receipt' then
    raise exception 'Receipt email is not available.' using errcode = '22023';
  end if;

  select * into v_exhibitor from public.exhibitors where id = v_session.exhibitor_id;
  if nullif(btrim(coalesce(v_exhibitor.email, '')), '') is null then
    raise exception 'No email address is available for this exhibitor.' using errcode = '22023';
  end if;

  insert into public.show_checkin_receipt_deliveries (checkin_record_id)
  values (v_record.id)
  on conflict (checkin_record_id) do nothing;

  select * into v_delivery
  from public.show_checkin_receipt_deliveries
  where checkin_record_id = v_record.id
  for update;

  if v_delivery.status = 'sent' or v_record.receipt_sent_at is not null then
    return jsonb_build_object('already_sent', true);
  end if;
  if v_delivery.status = 'sending' and v_delivery.claimed_at > now() - interval '5 minutes' then
    return jsonb_build_object('in_progress', true);
  end if;

  update public.show_checkin_receipt_deliveries
  set status = 'sending', attempt_count = attempt_count + 1, claimed_at = now(),
      failure_message = null, updated_at = now()
  where id = v_delivery.id;

  select * into v_show from public.shows where id = v_session.show_id;
  return jsonb_build_object(
    'delivery_id', v_delivery.id,
    'email', v_exhibitor.email,
    'show_name', v_show.name,
    'exhibitor_name', coalesce(nullif(v_exhibitor.display_name, ''), trim(coalesce(v_exhibitor.first_name, '') || ' ' || coalesce(v_exhibitor.last_name, ''))),
    'checked_in_at', v_record.completed_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_exhibitor_checkin(p_session_token text, p_entries_confirmed boolean, p_initials text DEFAULT NULL::text, p_signature_data text DEFAULT NULL::text, p_receipt_preference text DEFAULT 'no_receipt'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_record public.show_checkin_records%rowtype;
  v_initials text := nullif(btrim(coalesce(p_initials, '')), '');
  v_signature text := nullif(btrim(coalesce(p_signature_data, '')), '');
  v_receipt text := lower(btrim(coalesce(p_receipt_preference, 'no_receipt')));
  v_now timestamptz := now();
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > v_now
  for update;
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;
  if not found or not v_settings.is_enabled
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.opens_at is not null and v_now < v_settings.opens_at)
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.closes_at is not null and v_now > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;
  if not p_entries_confirmed then
    raise exception 'You must confirm your entries before completing check-in';
  end if;
  if v_settings.require_initials and v_initials is null then
    raise exception 'Initials are required';
  end if;
  if v_settings.require_signature and v_signature is null then
    raise exception 'A signature is required';
  end if;
  if v_receipt not in ('email_receipt', 'no_receipt') then
    raise exception 'Invalid receipt preference';
  end if;

  insert into public.show_checkin_records(show_id, exhibitor_id, status)
  values (v_session.show_id, v_session.exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id, wave_id) do nothing;
  select * into v_record from public.show_checkin_records
  where show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id and show_waves_private.record_current(show_id,wave_id)
  for update;
  if v_record.status = 'locked' then
    raise exception 'This check-in has been locked by the show secretary';
  end if;

  update public.show_checkin_records
  set status = 'completed', confirmed_at = v_now,
      confirmed_by_type = 'exhibitor', confirmation_initials = v_initials,
      signature_data = v_signature, receipt_preference = v_receipt,
      completed_at = v_now, updated_at = v_now
  where id = v_record.id;

  insert into public.show_checkin_audit_events(
    show_id, exhibitor_id, checkin_record_id, event_type, actor_type, session_id, details
  ) values (
    v_session.show_id, v_session.exhibitor_id, v_record.id,
    'checkin_completed', 'exhibitor_portal', v_session.id,
    jsonb_build_object('receipt_preference', v_receipt, 'has_initials', v_initials is not null, 'has_signature', v_signature is not null)
  );

  return jsonb_build_object('status', 'completed', 'completed_at', v_now);
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_exhibitor_checkin_by_secretary(p_show_id uuid, p_exhibitor_id uuid, p_entries_confirmed boolean, p_initials text DEFAULT NULL::text, p_signature_data text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_record public.show_checkin_records%rowtype;
  v_now timestamptz := now();
  v_initials text := nullif(btrim(coalesce(p_initials, '')), '');
  v_signature text := nullif(btrim(coalesce(p_signature_data, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s check-in.' using errcode = '42501';
  end if;
  if not p_entries_confirmed then
    raise exception 'Confirm the exhibitor''s entries before completing check-in.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.entries
    where show_id = p_show_id and exhibitor_id = p_exhibitor_id and show_waves_private.entry_allowed(show_id,species::text,breed)
  ) then
    raise exception 'This exhibitor does not have entries in this show.' using errcode = '22023';
  end if;

  insert into public.show_checkin_records (show_id, exhibitor_id, status)
  values (p_show_id, p_exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id, wave_id) do nothing;

  select * into v_record from public.show_checkin_records
  where show_id = p_show_id and exhibitor_id = p_exhibitor_id and show_waves_private.record_current(show_id,wave_id)
  for update;
  if v_record.status = 'locked' then
    raise exception 'This check-in has been locked.' using errcode = '22023';
  end if;

  update public.show_checkin_records
  set status = 'completed', confirmed_at = v_now,
      confirmed_by_type = 'secretary', confirmed_by_user_id = auth.uid(),
      confirmation_initials = v_initials, signature_data = v_signature,
      receipt_preference = 'no_receipt', completed_at = v_now, updated_at = v_now
  where id = v_record.id;

  insert into public.show_checkin_audit_events (
    show_id, exhibitor_id, checkin_record_id, event_type, actor_type, actor_user_id, details
  ) values (
    p_show_id, p_exhibitor_id, v_record.id, 'checkin_completed_by_secretary', 'secretary', auth.uid(),
    jsonb_build_object('note', v_note, 'has_initials', v_initials is not null, 'has_signature', v_signature is not null)
  );

  return jsonb_build_object('status', 'completed', 'completed_at', v_now, 'completed_by', 'secretary');
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_exhibitor_checkin_by_secretary_with_receipt(p_show_id uuid, p_exhibitor_id uuid, p_entries_confirmed boolean, p_initials text DEFAULT NULL::text, p_signature_data text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_receipt_preference text DEFAULT 'no_receipt'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_record public.show_checkin_records%rowtype;
  v_now timestamptz := now();
  v_receipt text := lower(btrim(coalesce(p_receipt_preference, 'no_receipt')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s check-in.' using errcode = '42501';
  end if;
  if not p_entries_confirmed then raise exception 'Confirm the exhibitor''s entries before completing check-in.'; end if;
  if v_receipt not in ('email_receipt', 'no_receipt') then raise exception 'Invalid receipt preference.'; end if;
  if not exists (select 1 from public.entries where show_id = p_show_id and exhibitor_id = p_exhibitor_id and show_waves_private.entry_allowed(show_id,species::text,breed)) then
    raise exception 'This exhibitor does not have entries in this show.';
  end if;
  insert into public.show_checkin_records (show_id, exhibitor_id, status)
  values (p_show_id, p_exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id, wave_id) do nothing;
  select * into v_record from public.show_checkin_records
  where show_id = p_show_id and exhibitor_id = p_exhibitor_id and show_waves_private.record_current(show_id,wave_id) for update;
  if v_record.status = 'locked' then raise exception 'This check-in has been locked.'; end if;

  update public.show_checkin_records
  set status = 'completed', confirmed_at = v_now, confirmed_by_type = 'secretary', confirmed_by_user_id = auth.uid(),
      confirmation_initials = nullif(btrim(coalesce(p_initials, '')), ''),
      signature_data = nullif(btrim(coalesce(p_signature_data, '')), ''),
      receipt_preference = v_receipt, completed_at = v_now, updated_at = v_now,
      receipt_sent_at = null, receipt_provider_message_id = null
  where id = v_record.id;
  insert into public.show_checkin_audit_events (show_id, exhibitor_id, checkin_record_id, event_type, actor_type, actor_user_id, details)
  values (p_show_id, p_exhibitor_id, v_record.id, 'checkin_completed_by_secretary', 'secretary', auth.uid(),
    jsonb_build_object('note', nullif(btrim(coalesce(p_note, '')), ''), 'receipt_preference', v_receipt));
  return jsonb_build_object('id', v_record.id, 'status', 'completed', 'completed_at', v_now, 'completed_by', 'secretary');
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_checkin_receipt_context(p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.show_checkin_sessions%rowtype; r public.show_checkin_records%rowtype; e public.exhibitors%rowtype; sh public.shows%rowtype;
begin
  perform show_waves_private.require_session(p_session_token);
 select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_session_token,'')),'sha256'),'hex') and revoked_at is null and expires_at>now();
 if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
 select * into r from public.show_checkin_records where show_id=s.show_id and exhibitor_id=s.exhibitor_id and show_waves_private.record_current(show_id,wave_id);
 if not found or r.status <> 'completed' or r.receipt_preference <> 'email_receipt' or r.receipt_sent_at is not null then raise exception 'Receipt email is not available'; end if;
 select * into e from public.exhibitors where id=s.exhibitor_id; select * into sh from public.shows where id=s.show_id;
 return jsonb_build_object('record_id',r.id,'email',e.email,'show_name',sh.name,'exhibitor_name',coalesce(nullif(e.display_name,''),trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,''))),'checked_in_at',r.completed_at);
end; $function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_add_entry_options(p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now();
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501'; end if;

  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;
  if not found or not v_settings.is_enabled
     or coalesce(v_settings.entry_edit_permissions ->> 'add_entry', 'disabled') not in ('automatic', 'approval') then
    raise exception 'Adding entries is not available through this portal';
  end if;

  return jsonb_build_object(
    'permission', v_settings.entry_edit_permissions ->> 'add_entry',
    'sections', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', coalesce(nullif(s.display_name, ''), upper(s.letter))) order by s.sort_order)
      from public.show_sections s where s.show_id = v_session.show_id
    ), '[]'::jsonb),
    'defaults', coalesce((
      select jsonb_build_object('species', e.species, 'breed', e.breed, 'variety', e.variety, 'class', e.class_name, 'sex', e.sex)
      from public.entries e where e.show_id = v_session.show_id and e.exhibitor_id = v_session.exhibitor_id and show_waves_private.entry_allowed(e.show_id,e.species::text,e.breed)
      order by e.updated_at desc limit 1
    ), '{}'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_breed_class_metadata(p_session_token text, p_breed_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_class_system text;
  v_has_prejunior boolean;
begin
  perform show_waves_private.require_session(p_session_token);
  select *
  into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now();

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  select coalesce(
           nullif(btrim(sb.class_system_override::text), ''),
           b.class_system::text,
           'four'
         ),
         coalesce(b.has_prejunior, false)
  into v_class_system, v_has_prejunior
  from public.breeds b
  left join public.show_breeds sb
    on sb.show_id = v_session.show_id
   and sb.breed_id = b.id
  where b.id = p_breed_id
    and b.is_active = true and show_waves_private.entry_allowed(v_session.show_id,b.species::text,b.name)
    and (b.local_show_id is null or b.local_show_id = v_session.show_id)
    and coalesce(sb.is_enabled, true) = true
  limit 1;

  if not found then
    raise exception 'Breed is not available for this show.'
      using errcode = '22023';
  end if;

  return jsonb_build_object(
    'class_system', coalesce(v_class_system, 'four'),
    'has_prejunior', v_has_prejunior
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_change_requests(p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex'
  ) and revoked_at is null and expires_at > now();

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'entry_id', r.entry_id,
      'request_type', r.request_type,
      'status', r.status,
      'requested_changes', r.requested_changes,
      'original_values', r.original_values,
      'applied_changes', r.applied_changes,
      'exhibitor_note', r.exhibitor_note,
      'review_note', r.review_note,
      'fee_cents', r.fee_cents,
      'created_at', r.created_at,
      'entry_tattoo', e.tattoo
    ) order by r.created_at desc)
    from public.show_checkin_change_requests r
    left join public.entries e on e.id = r.entry_id
    where r.show_id = v_session.show_id
      and r.exhibitor_id = v_session.exhibitor_id and r.wave_id is not distinct from v_session.wave_id
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_checkout_context(p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_balance public.show_exhibitor_balances%rowtype;
  v_cart public.entry_carts%rowtype;
  v_show public.shows%rowtype;
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now();

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  select * into v_show from public.shows where id = v_session.show_id;
  if not found or v_show.payment_timing_mode not in ('online_only', 'online_or_at_show') then
    raise exception 'Online payment is not available for this show';
  end if;

  select b.* into v_balance
  from public.show_exhibitor_balances b
  join public.entry_carts c on c.id = b.entry_cart_id
  where b.show_id = v_session.show_id
    and b.exhibitor_id = v_session.exhibitor_id
    and b.source = 'cart'
    and b.balance_due_cents > 0
    and c.status = 'active'
    and c.payment_status <> 'paid'
  order by b.updated_at desc
  limit 1;

  if not found then
    raise exception 'There is no online payment balance available for this check-in';
  end if;

  select * into v_cart from public.entry_carts where id = v_balance.entry_cart_id;
  if not found or v_cart.user_id is null then
    raise exception 'This payment cart is unavailable';
  end if;

  return jsonb_build_object(
    'cart_id', v_cart.id,
    'user_id', v_cart.user_id,
    'show_id', v_session.show_id,
    'provider', 'stripe'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_entry_selection_options(p_session_token text, p_entry_id uuid DEFAULT NULL::uuid, p_breed_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_entry public.entries%rowtype;
  v_species text := 'rabbit';
  v_selected_breed_id uuid;
  v_selected_breed_name text;
  v_breeds jsonb := '[]'::jsonb;
  v_varieties jsonb := '[]'::jsonb;
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now();
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  select * into v_settings
  from public.show_checkin_settings
  where show_id = v_session.show_id;
  if not found
     or not v_settings.is_enabled
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.opens_at is not null and now() < v_settings.opens_at)
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.closes_at is not null and now() > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;

  if p_entry_id is not null then
    select * into v_entry
    from public.entries
    where id = p_entry_id
      and show_id = v_session.show_id
      and exhibitor_id = v_session.exhibitor_id and show_waves_private.entry_allowed(show_id,species::text,breed);
    if not found then
      raise exception 'Entry is not available for this check-in session';
    end if;
    v_species := case when lower(coalesce(v_entry.species::text, 'rabbit')) = 'cavy'
      then 'cavy' else 'rabbit' end;
  else
    select * into v_entry
    from public.entries
    where show_id = v_session.show_id
      and exhibitor_id = v_session.exhibitor_id and show_waves_private.entry_allowed(show_id,species::text,breed)
    order by updated_at desc nulls last
    limit 1;
    if found then
      v_species := case when lower(coalesce(v_entry.species::text, 'rabbit')) = 'cavy'
        then 'cavy' else 'rabbit' end;
    end if;
  end if;

  select coalesce(
    jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name) order by lower(b.name)),
    '[]'::jsonb
  ) into v_breeds
  from public.breeds b
  left join public.show_breeds sb
    on sb.show_id = v_session.show_id
   and sb.breed_id = b.id
  where b.species::text = v_species
    and b.is_active = true and show_waves_private.entry_allowed(v_session.show_id,b.species::text,b.name)
    and coalesce(sb.is_enabled, true) = true;

  if p_breed_id is not null and exists (
    select 1
    from public.breeds b
    left join public.show_breeds sb
      on sb.show_id = v_session.show_id
     and sb.breed_id = b.id
    where b.id = p_breed_id
      and b.species::text = v_species
      and b.is_active = true and show_waves_private.entry_allowed(v_session.show_id,b.species::text,b.name)
      and coalesce(sb.is_enabled, true) = true
  ) then
    v_selected_breed_id := p_breed_id;
  elsif v_entry.id is not null then
    select b.id into v_selected_breed_id
    from public.breeds b
    left join public.show_breeds sb
      on sb.show_id = v_session.show_id
     and sb.breed_id = b.id
    where b.species::text = v_species
      and b.is_active = true and show_waves_private.entry_allowed(v_session.show_id,b.species::text,b.name)
      and coalesce(sb.is_enabled, true) = true
      and lower(btrim(b.name)) = lower(btrim(coalesce(v_entry.breed, '')))
    limit 1;
  end if;

  if v_selected_breed_id is not null then
    select b.name into v_selected_breed_name
    from public.breeds b
    where b.id = v_selected_breed_id;

    if v_species = 'cavy' then
      select coalesce(
        jsonb_agg(jsonb_build_object('id', 'cavy_' || lower(c.variety_name), 'name', c.variety_name)
          order by c.variety_sort_order, c.variety_name),
        '[]'::jsonb
      ) into v_varieties
      from public.cavy_sop_variety_order c
      where lower(btrim(c.breed_name)) = lower(btrim(v_selected_breed_name));
    elsif lower(v_selected_breed_name) like '%lop' then
      v_varieties := '[{"id":"lop_broken","name":"Broken"},{"id":"lop_solid","name":"Solid"}]'::jsonb;
    else
      select coalesce(
        jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name) order by lower(x.name)),
        '[]'::jsonb
      ) into v_varieties
      from (
        select v.id::text as id, v.name
        from public.varieties v
        left join public.show_varieties sv
          on sv.show_id = v_session.show_id
         and sv.breed_id = v_selected_breed_id
         and sv.variety_id = v.id
        where v.breed_id = v_selected_breed_id
          and v.is_active = true
          and coalesce(sv.is_enabled, true) = true
        union all
        select 'custom_' || sv.custom_name as id, sv.custom_name as name
        from public.show_varieties sv
        where sv.show_id = v_session.show_id
          and sv.breed_id = v_selected_breed_id
          and sv.variety_id is null
          and sv.is_enabled = true
          and nullif(btrim(sv.custom_name), '') is not null
      ) x;
    end if;
  end if;

  return jsonb_build_object(
    'species', v_species,
    'selected_breed_id', v_selected_breed_id,
    'breeds', v_breeds,
    'varieties', v_varieties
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_payment_status(p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.show_checkin_sessions%rowtype; v_due integer; v_currency text; v_status text; v_online boolean;
begin
  perform show_waves_private.require_session(p_session_token);
 select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_session_token,'')),'sha256'),'hex') and revoked_at is null and expires_at>now();
 if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
 select coalesce(sum(b.balance_due_cents),0)::integer, min(lower(b.currency)), case when coalesce(sum(b.balance_due_cents),0)<=0 then 'paid' else 'unpaid' end
 into v_due,v_currency,v_status
 from public.show_exhibitor_balances b join public.entry_carts c on c.id=b.entry_cart_id
 where b.show_id=s.show_id and b.exhibitor_id=s.exhibitor_id and b.source='cart' and c.status='active';
 if v_currency is null then
   select coalesce(sum(b.balance_due_cents),0)::integer,min(lower(b.currency)),case when coalesce(sum(b.balance_due_cents),0)<=0 then 'paid' else 'unpaid' end into v_due,v_currency,v_status
   from public.show_exhibitor_balances b where b.show_id=s.show_id and b.exhibitor_id=s.exhibitor_id and b.source='entries';
 end if;
 select exists(select 1 from public.shows sh join public.show_payment_settings ps on ps.show_id=sh.id join public.show_payment_account_links l on l.show_id=sh.id and l.provider='stripe' where sh.id=s.show_id and sh.payment_timing_mode in ('online_only','online_or_at_show') and coalesce(ps.stripe_enabled,false) and coalesce(l.charges_enabled,false) and coalesce(l.account_status,'')='ready') into v_online;
 return jsonb_build_object('balance_due_cents',coalesce(v_due,0),'currency',coalesce(v_currency,'usd'),'payment_status',coalesce(v_status,'paid'),'online_payment_available',v_online);
end; $function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_portal_data(p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_show public.shows%rowtype;
  v_exhibitor public.exhibitors%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_record public.show_checkin_records%rowtype;
  v_entries jsonb;
  v_payment jsonb;
begin
  perform show_waves_private.require_session(p_session_token);
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now()
  for update;

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  select * into v_show from public.shows where id = v_session.show_id;
  select * into v_exhibitor from public.exhibitors where id = v_session.exhibitor_id;
  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;

  if not found or not v_settings.is_enabled
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.opens_at is not null and now() < v_settings.opens_at)
     or (not show_waves_private.enabled(v_settings.show_id) and v_settings.closes_at is not null and now() > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;

  insert into public.show_checkin_records(show_id, exhibitor_id, status)
  values (v_session.show_id, v_session.exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id, wave_id) do nothing;

  select * into v_record
  from public.show_checkin_records
  where show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id and show_waves_private.record_current(show_id,wave_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'section_id', e.section_id,
    'show_letter', upper(sec.letter),
    'show_label', coalesce(
      nullif(sec.display_name, ''),
      initcap(coalesce(sec.kind::text, 'Show')) || ' ' || upper(coalesce(sec.letter, ''))
    ),
    'species', e.species,
    'tattoo', e.tattoo,
    'animal_name', e.animal_name,
    'breed', e.breed,
    'variety', e.variety,
    'fur_variety', e.fur_variety,
    'class_name', e.class_name,
    'sex', e.sex,
    'is_fur', e.is_fur,
    'status', e.status,
    'scratched_at', e.scratched_at
  ) order by sec.sort_order, e.breed, e.variety, e.class_name, e.sex, e.tattoo), '[]'::jsonb)
  into v_entries
  from public.entries e
  left join public.show_sections sec on sec.id = e.section_id
  where e.show_id = v_session.show_id
    and e.exhibitor_id = v_session.exhibitor_id and show_waves_private.entry_allowed(e.show_id,e.species::text,e.breed);

  select jsonb_build_object(
    'balance_due_cents', greatest(coalesce(b.balance_due_cents, 0), 0),
    'currency', coalesce(nullif(lower(b.currency), ''), 'usd'),
    'payment_status', coalesce(nullif(b.payment_status, ''), 'unpaid'),
    'online_payment_available', coalesce(
      v_show.payment_timing_mode in ('online_only', 'online_or_at_show')
      and exists (
        select 1
        from public.show_payment_settings ps
        where ps.show_id = v_show.id
          and (
            (coalesce(ps.stripe_enabled, false) and exists (
              select 1 from public.show_payment_account_links l
              where l.show_id = v_show.id and l.provider = 'stripe'
                and coalesce(l.charges_enabled, false)
                and coalesce(l.account_status, '') = 'ready'
            ))
            or (coalesce(ps.square_enabled, false) and exists (
              select 1 from public.show_payment_account_links l
              where l.show_id = v_show.id and l.provider = 'square'
                and l.provider_account_id is not null and l.provider_location_id is not null
                and coalesce(l.status, '') in ('ready', 'connected', 'active')
            ))
            or (coalesce(ps.paypal_enabled, false) and exists (
              select 1 from public.show_payment_account_links l
              where l.show_id = v_show.id and l.provider = 'paypal'
                and l.provider_account_id is not null
                and coalesce(l.status, '') in ('ready', 'connected', 'active')
            ))
          )
      ), false)
  ) into v_payment
  from public.show_exhibitor_balances b
  where b.show_id = v_session.show_id
    and b.exhibitor_id = v_session.exhibitor_id
    and (
      b.source = 'entries'
      or not exists (
        select 1 from public.show_exhibitor_balances authoritative
        where authoritative.show_id = b.show_id
          and authoritative.exhibitor_id = b.exhibitor_id
          and authoritative.source = 'entries'
      )
    )
  order by case when b.source = 'entries' then 0 else 1 end, b.updated_at desc
  limit 1;

  v_payment := coalesce(v_payment, jsonb_build_object(
    'balance_due_cents', 0,
    'currency', 'usd',
    'payment_status', 'paid',
    'online_payment_available', false
  ));

  update public.show_checkin_sessions
  set last_seen_at = now()
  where id = v_session.id;

  return jsonb_build_object(
    'show', jsonb_build_object('id', v_show.id, 'name', v_show.name),
    'exhibitor', jsonb_build_object(
      'id', v_exhibitor.id,
      'number', v_exhibitor.exhibitor_number,
      'name', coalesce(nullif(v_exhibitor.display_name, ''), nullif(v_exhibitor.showing_name, ''), trim(coalesce(v_exhibitor.first_name, '') || ' ' || coalesce(v_exhibitor.last_name, '')))
    ),
    'checkin', jsonb_build_object(
      'status', v_record.status,
      'require_initials', v_settings.require_initials,
      'require_signature', v_settings.require_signature,
      'entry_edit_permissions', v_settings.entry_edit_permissions
    ),
    'payment', v_payment,
    'entries', v_entries,
    'wave', (select jsonb_build_object('id',w.id,'name','Wave '||w.wave_number,'checkin_starts_at',w.checkin_starts_at,'checkin_ends_at',w.checkin_ends_at,'timezone',v_show.timezone) from public.show_waves w where w.id=v_session.wave_id),
    'expires_at', v_session.expires_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_exhibitor_checkin_portal_show(p_portal_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_show public.shows%rowtype;
begin
  select s.* into v_show
  from public.show_checkin_settings settings
  join public.shows s on s.id = settings.show_id
  where settings.portal_token_hash = encode(
    extensions.digest(btrim(coalesce(p_portal_token, '')), 'sha256'),
    'hex'
  )
    and settings.is_enabled
    and (show_waves_private.enabled(settings.show_id) or settings.opens_at is null or now() >= settings.opens_at)
    and (show_waves_private.enabled(settings.show_id) or settings.closes_at is null or now() <= settings.closes_at)
    and (not show_waves_private.enabled(settings.show_id) or show_waves_private.active_wave(settings.show_id) is not null);

  if not found then
    raise exception 'Check-in is not available';
  end if;

  return jsonb_build_object('show_name', v_show.name);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_show_checkin_dashboard(p_show_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_records jsonb;
  v_recent jsonb;
  v_pending_changes integer;
  v_unpaid_exhibitors integer;
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to view this show''s check-in dashboard.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'not_started', count(*) filter (where status = 'not_started'),
    'in_progress', count(*) filter (where status = 'in_progress'),
    'completed', count(*) filter (where status = 'completed'),
    'reviewed', count(*) filter (where status = 'reviewed_by_secretary'),
    'locked', count(*) filter (where status = 'locked')
  ) into v_records
  from public.show_checkin_records
  where show_id = p_show_id and show_waves_private.record_current(show_id,wave_id);

  select count(*) into v_pending_changes
  from public.show_checkin_change_requests
  where show_id = p_show_id and status in ('submitted', 'pending_payment', 'pending_review');

  select count(distinct exhibitor_id) into v_unpaid_exhibitors
  from public.show_exhibitor_balances
  where show_id = p_show_id and coalesce(balance_due_cents, 0) > 0;

  select coalesce(jsonb_agg(item order by completed_at desc), '[]'::jsonb) into v_recent
  from (
    select jsonb_build_object(
      'id', r.id,
      'status', r.status,
      'completed_at', r.completed_at,
      'receipt_sent_at', r.receipt_sent_at,
      'receipt_preference', r.receipt_preference,
      'exhibitor_name', coalesce(nullif(e.display_name, ''), trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, ''))),
      'exhibitor_number', e.exhibitor_number
    ) as item, r.completed_at
    from public.show_checkin_records r
    join public.exhibitors e on e.id = r.exhibitor_id
    where r.show_id = p_show_id and show_waves_private.record_current(r.show_id,r.wave_id) and r.status in ('completed', 'reviewed_by_secretary', 'locked')
    order by r.completed_at desc nulls last
    limit 20
  ) recent;

  return jsonb_build_object(
    'waves_enabled', show_waves_private.enabled(p_show_id),
    'wave_name', (select 'Wave '||wave_number from public.show_waves where id=show_waves_private.active_wave(p_show_id)),
    'records', coalesce(v_records, '{}'::jsonb),
    'pending_change_requests', coalesce(v_pending_changes, 0),
    'unpaid_exhibitors', coalesce(v_unpaid_exhibitors, 0),
    'recent_checkins', v_recent
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_show_checkin_roster(p_show_id uuid, p_search text DEFAULT ''::text, p_status text DEFAULT 'all'::text)
 RETURNS TABLE(exhibitor_id uuid, exhibitor_name text, exhibitor_number text, checkin_status text, completed_at timestamp with time zone, balance_due_cents integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_status text := lower(btrim(coalesce(p_status, 'all')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to view this show''s check-in roster.' using errcode = '42501';
  end if;
  if v_status not in ('all', 'balance_due', 'not_started', 'in_progress', 'completed', 'reviewed_by_secretary', 'locked') then
    raise exception 'Invalid check-in status.' using errcode = '22023';
  end if;

  return query
  select
    e.exhibitor_id,
    coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))),
    x.exhibitor_number::text,
    coalesce(r.status, 'not_started'),
    r.completed_at,
    coalesce(balance_summary.total_due_cents, 0)::integer
  from (select distinct entry.exhibitor_id from public.entries entry
        where entry.show_id = p_show_id and show_waves_private.entry_allowed(entry.show_id,entry.species::text,entry.breed)) e
  join public.exhibitors x on x.id = e.exhibitor_id
  left join public.show_checkin_records r
    on r.show_id = p_show_id and r.exhibitor_id = e.exhibitor_id and show_waves_private.record_current(r.show_id,r.wave_id)
  left join (
    select b.exhibitor_id, sum(b.balance_due_cents)::integer as total_due_cents
    from public.show_exhibitor_balances b
    where b.show_id = p_show_id
    group by b.exhibitor_id
  ) balance_summary on balance_summary.exhibitor_id = e.exhibitor_id
  where true
    and (v_status = 'all' or v_status = 'balance_due' or coalesce(r.status, 'not_started') = v_status)
    and (v_status <> 'balance_due' or coalesce(balance_summary.total_due_cents, 0) > 0)
    and (
      v_search = ''
      or lower(coalesce(x.display_name, '') || ' ' || coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '') || ' ' || coalesce(x.exhibitor_number::text, '')) like '%' || v_search || '%'
    )
  order by coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))), e.exhibitor_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_show_checkin_roster_page(p_show_id uuid, p_search text DEFAULT ''::text, p_status text DEFAULT 'all'::text, p_after_exhibitor_id uuid DEFAULT NULL::uuid, p_page_size integer DEFAULT 1000)
 RETURNS TABLE(exhibitor_id uuid, exhibitor_name text, exhibitor_number text, checkin_status text, completed_at timestamp with time zone, balance_due_cents integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_status text := lower(btrim(coalesce(p_status, 'all')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to view this show''s check-in roster.' using errcode = '42501';
  end if;
  if v_status not in ('all', 'balance_due', 'not_started', 'in_progress', 'completed', 'reviewed_by_secretary', 'locked') then
    raise exception 'Invalid check-in status.' using errcode = '22023';
  end if;

  return query
  select
    e.exhibitor_id,
    coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))),
    x.exhibitor_number::text,
    coalesce(r.status, 'not_started'),
    r.completed_at,
    coalesce(balance_summary.total_due_cents, 0)::integer
  from (select distinct entry.exhibitor_id from public.entries entry
        where entry.show_id = p_show_id and show_waves_private.entry_allowed(entry.show_id,entry.species::text,entry.breed)) e
  join public.exhibitors x on x.id = e.exhibitor_id
  left join public.show_checkin_records r
    on r.show_id = p_show_id and r.exhibitor_id = e.exhibitor_id and show_waves_private.record_current(r.show_id,r.wave_id)
  left join (
    select b.exhibitor_id, sum(b.balance_due_cents)::integer as total_due_cents
    from public.show_exhibitor_balances b
    where b.show_id = p_show_id
    group by b.exhibitor_id
  ) balance_summary on balance_summary.exhibitor_id = e.exhibitor_id
  where (p_after_exhibitor_id is null or e.exhibitor_id > p_after_exhibitor_id)
    and (v_status = 'all' or v_status = 'balance_due' or coalesce(r.status, 'not_started') = v_status)
    and (v_status <> 'balance_due' or coalesce(balance_summary.total_due_cents, 0) > 0)
    and (
      v_search = ''
      or lower(coalesce(x.display_name, '') || ' ' || coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '') || ' ' || coalesce(x.exhibitor_number::text, '')) like '%' || v_search || '%'
    )
  order by e.exhibitor_id
  limit greatest(1, least(coalesce(p_page_size, 1000), 1000));
end;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_locked_checkin_change_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if exists (
    select 1 from public.show_checkin_records
    where show_id = new.show_id and exhibitor_id = new.exhibitor_id and show_waves_private.record_current(show_id,wave_id) and wave_id is not distinct from new.wave_id and status = 'locked'
  ) then
    raise exception 'This check-in is locked and cannot accept additional changes.' using errcode = '22023';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_show_checkin_exhibitors(p_show_id uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(exhibitor_id uuid, exhibitor_name text, exhibitor_number text, checkin_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s check-in.' using errcode = '42501';
  end if;

  return query
  select
    e.exhibitor_id,
    coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))),
    x.exhibitor_number::text,
    r.status
  from public.entries e
  join public.exhibitors x on x.id = e.exhibitor_id
  left join public.show_checkin_records r
    on r.show_id = p_show_id and r.exhibitor_id = e.exhibitor_id and show_waves_private.record_current(r.show_id,r.wave_id)
  where e.show_id = p_show_id and show_waves_private.entry_allowed(e.show_id,e.species::text,e.breed)
    and (
      v_search = ''
      or lower(coalesce(x.display_name, '') || ' ' || coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '') || ' ' || coalesce(x.exhibitor_number::text, '')) like '%' || v_search || '%'
    )
  group by e.exhibitor_id, x.display_name, x.first_name, x.last_name, x.exhibitor_number, r.status
  order by coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '')))
  limit 40;
end;
$function$;

CREATE OR REPLACE FUNCTION public.submit_exhibitor_checkin_add_entry(p_session_token text, p_changes jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s public.show_checkin_sessions%rowtype; cfg public.show_checkin_settings%rowtype;
  r uuid; mode text; item uuid; v_section uuid := nullif(p_changes ->> 'section_id', '')::uuid;
  v_configured_fee integer; v_normal_fee integer := 0; v_adjustment integer := 0;
  v_breakdown jsonb;
begin
  perform show_waves_private.guard_entry_request(p_session_token,null,p_changes);
  select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_session_token,'')),'sha256'),'hex') and revoked_at is null and expires_at>now() for update;
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
  select * into cfg from public.show_checkin_settings where show_id=s.show_id;
  mode := coalesce(cfg.entry_edit_permissions ->> 'add_entry','disabled');
  if mode not in ('automatic','approval') then raise exception 'Adding entries is not available through this portal'; end if;
  if v_section is null or not exists(select 1 from public.show_sections where id=v_section and show_id=s.show_id) then raise exception 'A valid show section is required'; end if;
  select round(coalesce(fee_per_entry, 0) * 100)::integer into v_normal_fee from public.show_section_fee_settings where section_id=v_section;
  v_normal_fee := coalesce(v_normal_fee, 0);
  v_configured_fee := public.get_checkin_action_fee_cents(s.show_id, 'add_entry');
  if v_configured_fee is not null then v_adjustment := v_configured_fee - v_normal_fee; end if;
  v_breakdown := jsonb_build_object('normal_entry_fee_cents', v_normal_fee, 'configured_entry_fee_cents', v_configured_fee,
    'cart_adjustment_cents', v_adjustment);
  insert into public.show_checkin_change_requests(show_id,exhibitor_id,request_type,requested_changes,exhibitor_note,status,reviewed_at,applied_changes,fee_cents,fee_breakdown)
  values(s.show_id,s.exhibitor_id,'add_entry',p_changes,nullif(btrim(coalesce(p_note,'')),''),case when mode='automatic' then 'approved' else 'pending_review' end,
    case when mode='automatic' then now() else null end,'{}',coalesce(v_configured_fee,v_normal_fee),v_breakdown) returning id into r;
  if mode='automatic' then
    item := public.apply_checkin_add_entry(s.show_id,s.exhibitor_id,p_changes,r);
    if v_adjustment <> 0 then perform report_generation_private.add_checkin_fee_charge(s.show_id, s.exhibitor_id, r, 'add_entry_override', v_adjustment, v_breakdown); end if;
    update public.show_checkin_change_requests set applied_changes=jsonb_build_object('cart_item_id',item) where id=r;
  end if;
  return jsonb_build_object('id',r,'status',case when mode='automatic' then 'approved' else 'pending_review' end,
    'cart_item_id',item,'fee_cents',coalesce(v_configured_fee,v_normal_fee));
end;
$function$;

CREATE OR REPLACE FUNCTION public.submit_exhibitor_checkin_change_request(p_session_token text, p_entry_id uuid, p_request_type text, p_requested_changes jsonb DEFAULT '{}'::jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_entry public.entries%rowtype;
  v_id uuid; v_key text; v_permission text;
  v_changes jsonb := coalesce(p_requested_changes, '{}'::jsonb);
  v_automatic jsonb := '{}'::jsonb; v_approval jsonb := '{}'::jsonb; v_original jsonb := '{}'::jsonb;
  v_auto_fee integer := 0; v_approval_fee integer := 0; v_action_fee integer;
  v_breakdown jsonb := '{}'::jsonb; v_status text;
begin
  perform show_waves_private.guard_entry_request(p_session_token,p_entry_id,p_requested_changes);
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now() for update;
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501'; end if;
  if p_request_type not in ('entry_edit', 'scratch_entry') or jsonb_typeof(v_changes) <> 'object' then
    raise exception 'Invalid change request';
  end if;
  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;
  if not found or not v_settings.is_enabled then raise exception 'Check-in is not available'; end if;
  select * into v_entry from public.entries where id = p_entry_id and show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id;
  if not found then raise exception 'Entry not found'; end if;
  v_original := jsonb_build_object('ear_number', v_entry.tattoo, 'breed', v_entry.breed, 'variety', v_entry.variety,
    'class', v_entry.class_name, 'sex', v_entry.sex, 'fur_variety', v_entry.fur_variety,
    'scratch_entry', v_entry.scratched_at is not null or lower(coalesce(v_entry.status, '')) = 'scratched');
  for v_key in select jsonb_object_keys(v_changes) loop
    if v_key not in ('ear_number', 'breed', 'variety', 'class', 'sex', 'fur_variety', 'scratch_entry') then
      raise exception 'This field cannot be changed through the check-in portal';
    end if;
    if v_key = 'scratch_entry' and coalesce((v_changes ->> v_key)::boolean, false) is not true then
      raise exception 'Only scratching an entry can be requested through the check-in portal';
    end if;
    v_permission := coalesce(v_settings.entry_edit_permissions ->> v_key, 'disabled');
    if v_permission not in ('automatic', 'approval') then raise exception 'This field is not available for exhibitor changes'; end if;
    v_action_fee := coalesce(public.get_checkin_action_fee_cents(v_session.show_id, v_key), 0);
    if v_permission = 'automatic' then
      v_automatic := v_automatic || jsonb_build_object(v_key, v_changes -> v_key);
      v_auto_fee := v_auto_fee + v_action_fee;
    else
      v_approval := v_approval || jsonb_build_object(v_key, v_changes -> v_key);
      v_approval_fee := v_approval_fee + v_action_fee;
    end if;
    v_breakdown := v_breakdown || jsonb_build_object(v_key, v_action_fee);
  end loop;
  v_breakdown := v_breakdown || jsonb_build_object('automatic_fee_cents', v_auto_fee, 'approval_fee_cents', v_approval_fee);
  v_status := case when v_approval <> '{}'::jsonb then 'pending_review' when v_automatic <> '{}'::jsonb then 'approved' else 'submitted' end;
  insert into public.show_checkin_change_requests(show_id, exhibitor_id, entry_id, request_type, requested_changes, original_values,
    applied_changes, exhibitor_note, status, reviewed_at, fee_cents, fee_breakdown)
  values(v_session.show_id, v_session.exhibitor_id, p_entry_id, p_request_type, v_approval, v_original, v_automatic,
    nullif(btrim(coalesce(p_note, '')), ''), v_status, case when v_status = 'approved' then now() else null end,
    v_auto_fee + v_approval_fee, v_breakdown) returning id into v_id;
  if v_automatic <> '{}'::jsonb then
    perform public.apply_checkin_entry_changes(p_entry_id, v_automatic, 'exhibitor_portal', null, v_id);
    if v_auto_fee <> 0 then
      perform report_generation_private.add_checkin_fee_charge(v_session.show_id, v_session.exhibitor_id, v_id, 'entry_edit_automatic', v_auto_fee, v_breakdown);
    end if;
  end if;
  insert into public.show_checkin_audit_events(show_id, exhibitor_id, event_type, actor_type, session_id, details)
  values(v_session.show_id, v_session.exhibitor_id, 'change_request_submitted', 'exhibitor_portal', v_session.id,
    jsonb_build_object('change_request_id', v_id, 'entry_id', p_entry_id, 'automatic_changes', v_automatic,
      'pending_review_changes', v_approval, 'fee_cents', v_auto_fee + v_approval_fee, 'fee_breakdown', v_breakdown));
  return jsonb_build_object('id', v_id, 'status', v_status, 'automatic_changes', v_automatic,
    'pending_review_changes', v_approval, 'fee_cents', v_auto_fee + v_approval_fee);
end;
$function$;

CREATE FUNCTION public.report_wave_checkin_entries(p_show_id uuid,p_wave_id uuid DEFAULT NULL,p_include_scratched boolean DEFAULT false,p_section_id uuid DEFAULT NULL,p_exhibitor_id uuid DEFAULT NULL,p_section_ids uuid[] DEFAULT NULL)
 RETURNS TABLE(entry_id uuid, show_id uuid, section_id uuid, exhibitor_id uuid, exhibitor_label text, exhibitor_showing_name text, exhibitor_display_name text, exhibitor_first_name text, exhibitor_last_name text, exhibitor_arba_number text, exhibitor_address_line1 text, exhibitor_address_line2 text, exhibitor_city text, exhibitor_state text, exhibitor_zip text, exhibitor_phone text, exhibitor_email text, section_letter text, section_display_name text, section_kind text, section_sort_order integer, species text, breed text, group_name text, group_sort_order integer, variety text, variety_sort_order integer, sex text, class_name text, class_age_label text, class_sort_order integer, tattoo text, scratched_at timestamp with time zone, created_at timestamp with time zone, entry_fee_cents numeric, balance_due_all_shows numeric, balance_due_this_show numeric)
 LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
declare wid uuid := p_wave_id; cfg boolean;
begin
 if current_user <> 'service_role' and ((select auth.uid()) is null or not (public.user_can_manage_entries(p_show_id) or public.user_can_manage_show_settings(p_show_id))) then
   raise exception 'You do not have permission to view check-in sheets.' using errcode='42501';
 end if;
 select ws.enabled into cfg from public.show_wave_settings ws where ws.show_id=p_show_id;
 if coalesce(cfg,false) then
   if wid is null then select w.id into wid from public.show_waves w where w.show_id=p_show_id and now()>=w.checkin_starts_at and now()<w.checkin_ends_at; end if;
   if wid is null or not exists(select 1 from public.show_waves w where w.id=wid and w.show_id=p_show_id) then
     raise exception 'Choose a wave to generate check-in sheets.';
   end if;
 elsif wid is not null then raise exception 'Wave scheduling is not enabled for this show.';
 end if;
 if current_user='service_role' and p_exhibitor_id is not null and p_section_ids is not null then
   return query select r.* from public.report_closeout_checkin_entries(p_show_id,p_exhibitor_id,p_section_ids,p_include_scratched) r
   where (p_section_id is null or r.section_id=p_section_id)
     and (wid is null or exists(select 1 from public.show_wave_breeds b where b.show_id=p_show_id and b.wave_id=wid and b.species=lower(r.species) and b.breed_key=lower(btrim(r.breed))));
   return;
 end if;
 return query select r.* from public.report_checkin_entries(p_show_id,p_include_scratched,p_section_id) r
 where (p_exhibitor_id is null or r.exhibitor_id=p_exhibitor_id)
   and (p_section_ids is null or r.section_id=any(p_section_ids))
   and (wid is null or exists(select 1 from public.show_wave_breeds b where b.show_id=p_show_id and b.wave_id=wid and b.species=lower(r.species) and b.breed_key=lower(btrim(r.breed))));
end $$;
revoke all on function public.report_wave_checkin_entries(uuid,uuid,boolean,uuid,uuid,uuid[]) from public,anon;
grant execute on function public.report_wave_checkin_entries(uuid,uuid,boolean,uuid,uuid,uuid[]) to authenticated,service_role;

notify pgrst,'reload schema';
