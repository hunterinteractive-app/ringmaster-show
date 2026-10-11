begin;
do $$ declare owner uuid; conn uuid=gen_random_uuid(); source uuid=gen_random_uuid(); source2 uuid=gen_random_uuid(); original uuid; aid uuid; payload jsonb; begin
 select id into owner from auth.users where email_confirmed_at is not null limit 1;
 if owner is null then raise exception 'Test requires a verified account'; end if;
 insert into public.animals(owner_user_id,species,name,breed,variety) values(owner,'rabbit','BRIDGE TEST','Tan','Black') returning id into original;
 payload=jsonb_build_array(jsonb_build_object('id',source,'species','rabbit','name','Bridge test','tattoo','BRIDGE-TEST','breed','Tan','variety','Black','sex','Buck'),jsonb_build_object('id',source2,'show_id',original,'species','rabbit','name','Original test','breed','Tan','variety','Black','sex','Doe'));
 perform public.apply_breeder_animals(conn,owner,'2026-10-11T00:00:00Z',payload);
 select animal_id into aid from public.breeder_animal_links where connection_id=conn and breeder_animal_id=source;
 if (select animal_id from public.breeder_animal_links where connection_id=conn and breeder_animal_id=source2)<>original then raise exception 'Failed original mapping'; end if;
 perform public.apply_breeder_animals(conn,owner,'2026-10-11T00:00:00Z',payload);
 if (select count(*) from public.breeder_animal_links where connection_id=conn)<>2 then raise exception 'Duplicate mapping'; end if;
 perform public.apply_breeder_animals(conn,owner,'2026-10-11T00:01:00Z','[]');
 if (select deleted_at from public.animals where id=aid) is null then raise exception 'Disconnect did not hide mirror'; end if;
 if (select deleted_at from public.animals where id=original) is not null then raise exception 'Original Show animal hidden'; end if;
 perform public.apply_breeder_animals(conn,owner,'2026-10-11T00:00:00Z',payload);
 if (select deleted_at from public.animals where id=aid) is null then raise exception 'Stale sync resurrected mirror'; end if;
 if has_function_privilege('authenticated','public.apply_breeder_animals(uuid,uuid,timestamptz,jsonb)','execute') or has_function_privilege('anon','public.breeder_verified_account(text)','execute') then raise exception 'Bridge exposed to client'; end if;
end $$;
rollback;
