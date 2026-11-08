-- Include this show's enabled catalog alongside entered and previously assigned
-- breeds. Keep shared BBOS access and all save/check-in/email guards unchanged.
create or replace function show_waves_private.schedule(p_show_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare zone text; waves jsonb; breeds jsonb; show_config jsonb; has_breed_settings boolean;
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' and ((select auth.uid()) is null or not (public.user_can_manage_show_settings(p_show_id) or public.user_can_manage_entries(p_show_id))) then
   raise exception 'You do not have permission to view this show schedule.' using errcode='42501';
 end if;
 select to_jsonb(s) into show_config from public.shows s where s.id=p_show_id;
 select exists(select 1 from public.show_breeds where show_id=p_show_id) into has_breed_settings;
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
     -- Plan against enabled catalog breeds before anyone submits an entry.
     select lower(c.species::text) species,btrim(c.name) name,false has_entries
     from public.breeds c
     left join public.show_breeds sb on sb.show_id=p_show_id and sb.breed_id=c.id
     where coalesce(c.is_active,true)
       and (c.local_show_id is null or c.local_show_id=p_show_id)
       and nullif(btrim(c.name),'') is not null
       and (
         (coalesce((show_config->>'is_single_breed_show')::boolean,false)
           and c.id::text=show_config->>'single_breed_id')
         or (not coalesce((show_config->>'is_single_breed_show')::boolean,false)
           and (not has_breed_settings or sb.is_enabled=true))
       )
       and (
         not exists(select 1 from public.show_sections ss where ss.show_id=p_show_id)
         or exists(select 1 from public.show_sections ss
           where ss.show_id=p_show_id and ss.is_enabled=true
             and public.section_allows_breed(ss.id,c.name,c.species::text))
       )
     union all
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
