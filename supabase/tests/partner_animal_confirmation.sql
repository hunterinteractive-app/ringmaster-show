-- Run within a transaction. Synthetic users, animals and credentials only.
do $$
declare u uuid=gen_random_uuid(); other uuid=gen_random_uuid(); cid uuid; aid uuid; rid uuid; stamp timestamptz;
 src uuid; row jsonb; answer jsonb; provider text; before_count integer; first_id uuid;
begin
 insert into auth.users(id,email,email_confirmed_at) values(u,u||'@example.invalid',now()),(other,other||'@example.invalid',now());
 insert into public.breeds(name,species,is_active) values('Confirmation Test Breed','rabbit',true);
 foreach provider in array array['ringmaster_breeder','herdmaster','pedigreehq'] loop
  cid=gen_random_uuid();src=gen_random_uuid();
  insert into public.animals(owner_user_id,species,name,tattoo,breed,sex) values(u,'rabbit','Match '||provider,provider,'Confirmation Test Breed','Doe') returning id into aid;
  row=jsonb_build_object('id',src,'name','Match '||provider,'tattoo',provider,'breed','Confirmation Test Breed','species','rabbit','sex','Doe','active',true,'updated_at',now(),'dob',null);
  select count(*) into before_count from public.animals where owner_user_id=u;
  if provider='ringmaster_breeder' then
   perform public.apply_breeder_animals(cid,u,now(),jsonb_build_array(row));
  else
   insert into public.herdmaster_connections(id,owner_user_id,external_account_id,token_hash,expires_at,provider) values(cid,u,'same-account',provider,now()+interval '1 day',provider);
   answer=public.herdmaster_apply_animals(provider,jsonb_build_array(row));
   if (answer->>'pending_reviews')::integer<>1 then raise exception 'Missing pending count'; end if;
  end if;
  if (select count(*) from public.animals where owner_user_id=u)<>before_count then raise exception 'Duplicate created before confirmation for %',provider; end if;
  select id,updated_at into rid,stamp from public.animal_import_reviews where connection_id=cid and decision='pending';
  if rid is null then raise exception 'Review not queued for %',provider; end if;
  perform set_config('request.jwt.claim.sub',other::text,true);
  if jsonb_array_length(public.animal_import_review('list'))<>0 then raise exception 'Cross-owner review leak'; end if;
  begin perform public.animal_import_review('link',rid,aid,stamp);raise exception 'Unauthorized resolution';exception when others then if sqlerrm='Unauthorized resolution' then raise; end if;end;
  perform set_config('request.jwt.claim.sub',u::text,true);
  begin perform public.animal_import_review('link',rid,aid,stamp-interval '1 second');raise exception 'Stale review accepted';exception when others then if sqlerrm='Stale review accepted' then raise;end if;end;
  perform public.animal_import_review('link',rid,aid,stamp);
  perform public.animal_import_review('link',rid,aid,stamp); -- uncertain response retry
  if (select count(*) from public.animals where owner_user_id=u)<>before_count then raise exception 'Confirmed match created a duplicate'; end if;
  if provider='ringmaster_breeder' then
   if not exists(select 1 from public.breeder_animal_links where connection_id=cid and animal_id=aid) then raise exception 'Breeder link not saved';end if;
   perform public.apply_breeder_animals(cid,u,now(),jsonb_build_array(row||jsonb_build_object('name','Changed name')));
  else
   if not exists(select 1 from public.herdmaster_animal_links where connection_id=cid and animal_id=aid) then raise exception 'Partner link not saved';end if;
   perform public.herdmaster_apply_animals(provider,jsonb_build_array(row));
   perform public.herdmaster_apply_animals(provider,jsonb_build_array(row||jsonb_build_object('name','Changed name','updated_at',now()+interval '1 second')));
  end if;
  if exists(select 1 from public.animal_import_reviews where id=rid and decision='pending') then raise exception 'Asked again after confirmed link';end if;
  -- A second source record with the same tattoo is reviewed, then explicitly kept separate.
  src=gen_random_uuid();row=row||jsonb_build_object('id',src,'updated_at',now());
  if provider='ringmaster_breeder' then perform public.apply_breeder_animals(cid,u,now(),jsonb_build_array(row));
  else perform public.herdmaster_apply_animals(provider,jsonb_build_array(row));end if;
  select id,updated_at into rid,stamp from public.animal_import_reviews where connection_id=cid and external_animal_id=src::text;
  begin perform public.animal_import_review('link',rid,aid,stamp);raise exception 'Already-linked target reused';exception when others then if sqlerrm='Already-linked target reused' then raise;end if;end;
  perform public.animal_import_review('separate',rid,null,stamp);
  select count(*) into before_count from public.animals where owner_user_id=u;
  if provider='ringmaster_breeder' then perform public.apply_breeder_animals(cid,u,now(),jsonb_build_array(row));
  else perform public.herdmaster_apply_animals(provider,jsonb_build_array(row));end if;
  if (select count(*) from public.animals where owner_user_id=u)<>before_count then raise exception 'Separate choice duplicated on retry';end if;
  select target_id into first_id from public.animal_import_reviews where id=rid;
  delete from public.animals where id=first_id;
  begin
   if provider='ringmaster_breeder' then perform public.apply_breeder_animals(cid,u,now(),jsonb_build_array(row));
   else perform public.herdmaster_apply_animals(provider,jsonb_build_array(row||jsonb_build_object('updated_at',now()+interval '3 seconds')));end if;
   raise exception 'Missing saved mapping silently recreated';
  exception when others then if sqlerrm='Missing saved mapping silently recreated' then raise;end if;end;
  if provider<>'ringmaster_breeder' then
   begin perform public.partner_existing_animals(provider);raise exception 'Legacy read consent bypassed';exception when insufficient_privilege then null;end;
   update public.herdmaster_connections set existing_animals_consent=true where id=cid;
   answer=public.partner_existing_animals(provider);
   if exists(select 1 from jsonb_array_elements(answer->'data') a where not exists(select 1 from public.animals where id=(a->>'ringmaster_animal_id')::uuid and owner_user_id=u)) then raise exception 'Existing animal listing leaked ownership';end if;
  end if;
 end loop;
 if has_table_privilege('authenticated','public.animal_import_reviews','SELECT') then raise exception 'Raw queue exposed';end if;
end $$;
