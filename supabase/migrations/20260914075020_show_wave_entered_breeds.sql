-- Show entered breeds across the full show, preserving stored assignments
-- even when their last entry is removed. Catalog-only and cart-only breeds
-- are not entries and should not appear in Breed Assignments.
create or replace function show_waves_private.schedule(p_show_id uuid)
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
 select coalesce(jsonb_agg(jsonb_build_object(
   'species',b.species,'breed_name',b.name,'wave_id',a.wave_id,
   'has_entries',b.has_entries) order by lower(b.name),b.species),'[]') into breeds
 from (
   select species,min(name) name,bool_or(has_entries) has_entries from (
     select lower(species::text) species,btrim(breed) name,true has_entries
     from public.entries where show_id=p_show_id and nullif(btrim(breed),'') is not null
     union all
     select species,breed_name,false from public.show_wave_breeds where show_id=p_show_id
   ) entered_or_assigned group by species,lower(name)
 ) b left join public.show_wave_breeds a on a.show_id=p_show_id and a.species=b.species and a.breed_key=lower(b.name)
 where b.species in ('rabbit','cavy');
 return jsonb_build_object('enabled',show_waves_private.enabled(p_show_id),'timezone',zone,'waves',waves,'breeds',breeds,
   'active_wave_id',show_waves_private.active_wave(p_show_id),'can_configure',public.can_configure_best_opposite_final_award(p_show_id));
end $$;

-- Saved carts have not been entered yet and do not appear in the dialog.
create or replace function show_waves_private.save_schedule(p_show_id uuid,p_enabled boolean,p_waves jsonb,p_breeds jsonb)
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
      and show_waves_private.breed_wave(p_show_id,e.species::text,e.breed) is null) then
     raise exception 'Assign every entered breed to a wave before enabling the schedule.';
   end if;
 end if;
 insert into public.show_wave_settings(show_id,enabled) values(p_show_id,p_enabled)
 on conflict(show_id) do update set enabled=excluded.enabled,updated_at=now();
 if p_enabled and not old_enabled then
   update public.shows set auto_email_checkin_sheets=true where id=p_show_id;
   update public.show_checkin_sessions set revoked_at=now() where show_id=p_show_id and revoked_at is null;
 end if;
end $$;

-- A new breed must be entered before it can appear in Breed Assignments.
-- Keep entry writes serialized with schedule edits; wave portal APIs continue
-- to require assignment to the active wave before allowing check-in.
create or replace function show_waves_private.require_assigned_breed()
returns trigger language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
 if tg_table_name='entry_cart_items' then
   if new.is_checkin_fee_carrier then return new; end if;
   select show_id into sid from public.entry_carts where id=new.cart_id;
 else
   sid := new.show_id;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('wave-schedule:'||sid::text,0));
 return new;
end $$;
