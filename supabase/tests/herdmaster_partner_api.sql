-- Run after the migration in a transaction; fixtures and checks are rolled back.
do $$
declare owner uuid=gen_random_uuid(); other_owner uuid=gen_random_uuid();
  connection uuid; other_connection uuid; aid uuid; original uuid; result jsonb;
  show_id uuid=gen_random_uuid(); exhibitor uuid=gen_random_uuid(); entry uuid=gen_random_uuid();
  original_entry uuid=gen_random_uuid(); artifact uuid=gen_random_uuid(); count_rows integer;
  source jsonb=jsonb_build_object('id','HM-string-ID','active',true,'updated_at','2026-10-12T14:00:00Z',
    'species','rabbit','tattoo','H1','breed','HerdMaster Test Breed','variety','Black','sex','Buck','dob',null);
begin
  insert into auth.users(id,email,email_confirmed_at) values(owner,owner::text||'@example.invalid',now()),
    (other_owner,other_owner::text||'@example.invalid',now());
  insert into public.breeds(name,species,is_active) values('HerdMaster Test Breed','rabbit',true);
  insert into public.herdmaster_connections(owner_user_id,external_account_id,token_hash,expires_at)
    values(owner,'HM-owner','test-hash',now()+interval '1 day') returning id into connection;
  insert into public.herdmaster_connections(owner_user_id,external_account_id,token_hash,expires_at)
    values(other_owner,'HM-other','other-hash',now()+interval '1 day') returning id into other_connection;
  result=public.herdmaster_apply_animals('test-hash',jsonb_build_array(source));
  if result->>'applied'<>'1' then raise exception 'Import failed'; end if;
  select animal_id into aid from public.herdmaster_animal_links where connection_id=connection and external_animal_id='HM-string-ID';
  if not exists(select 1 from public.animals where id=aid and owner_user_id=owner and is_dob_unknown) then raise exception 'Wrong animal owner or unknown DOB'; end if;
  result=public.herdmaster_apply_animals('test-hash',jsonb_build_array(source));
  if result->>'ignored'<>'1' then raise exception 'Replay not ignored'; end if;
  begin
    perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(source||'{"tattoo":"DIFFERENT"}'::jsonb));
    raise exception 'Conflicting replay accepted';
  exception when unique_violation then null; end;
  result=public.herdmaster_apply_animals('test-hash',jsonb_build_array(source||'{"updated_at":"2026-10-12T13:00:00Z"}'::jsonb));
  if result->>'ignored'<>'1' then raise exception 'Stale update accepted'; end if;
  begin
    perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(source,source));
    raise exception 'Duplicate batch accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(
      source||'{"id":"VALID-BUT-ROLLBACK"}'::jsonb,
      source||'{"id":"BAD-BREED","breed":"NO SUCH BREED"}'::jsonb));
    raise exception 'Bad breed accepted';
  exception when invalid_parameter_value then null; end;
  if exists(select 1 from public.herdmaster_animal_links where external_animal_id='VALID-BUT-ROLLBACK') then raise exception 'Batch was not atomic'; end if;
  insert into public.animals(owner_user_id,species,name,breed) values(other_owner,'rabbit','Other owner','HerdMaster Test Breed') returning id into original;
  begin
    perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(source||jsonb_build_object('id','HIJACK','ringmaster_animal_id',original)));
    raise exception 'Cross-owner linking accepted';
  exception when invalid_parameter_value then null; end;
  insert into public.animals(owner_user_id,species,name,breed) values(owner,'rabbit','Original animal','HerdMaster Test Breed') returning id into original;
  perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(source||jsonb_build_object('id','ORIGINAL','ringmaster_animal_id',original)));
  perform public.herdmaster_apply_animals('test-hash','[{"id":"ORIGINAL","active":false,"updated_at":"2026-10-12T15:00:00Z"}]');
  if (select deleted_at from public.animals where id=original) is not null then raise exception 'Original animal hidden'; end if;
  perform public.herdmaster_apply_animals('test-hash','[{"id":"HM-string-ID","active":false,"updated_at":"2026-10-12T15:00:00Z"}]');
  if (select deleted_at from public.animals where id=aid) is null then raise exception 'Managed animal not hidden'; end if;
  perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(source));
  if (select deleted_at from public.animals where id=aid) is null then raise exception 'Stale update resurrected animal'; end if;
  perform public.herdmaster_apply_animals('test-hash','[{"id":"TOMBSTONE","active":false,"updated_at":"2026-10-12T15:00:00Z"}]');
  perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(source||'{"id":"TOMBSTONE"}'::jsonb));
  if (select animal_id from public.herdmaster_animal_links where connection_id=connection and external_animal_id='TOMBSTONE') is not null then raise exception 'Stale update bypassed tombstone'; end if;
  perform public.herdmaster_apply_animals('test-hash',jsonb_build_array(source||'{"id":"TOMBSTONE","updated_at":"2026-10-12T16:00:00Z"}'::jsonb));
  if (select animal_id from public.herdmaster_animal_links where connection_id=connection and external_animal_id='TOMBSTONE') is null then raise exception 'New active update did not create animal'; end if;
  insert into public.shows(id,name,start_date,is_test,is_demo) values(show_id,'HerdMaster API Test',current_date,false,false);
  insert into public.show_breeds(show_id,breed_id,is_enabled)
    select show_id,b.id,true from public.breeds b where b.name='HerdMaster Test Breed';
  insert into public.exhibitors(id,owner_user_id,email) values(exhibitor,owner,owner::text||'@example.invalid');
  insert into public.entries(id,show_id,exhibitor_id,exhibitor_user_id,animal_id,species,breed,placement,is_test)
    values(entry,show_id,exhibitor,owner,aid,'rabbit','HerdMaster Test Breed',1,false),
      (original_entry,show_id,exhibitor,owner,null,'rabbit','HerdMaster Test Breed',2,false);
  select count(*) into count_rows from public.herdmaster_export('test-hash','results');
  if count_rows<>0 then raise exception 'Unpublished results exposed'; end if;
  insert into public.show_report_artifacts(id,show_id,report_name,artifact_status,is_current,storage_bucket,storage_path,metadata)
    values(artifact,show_id,'exhibitor_report','generated',true,'reports','test.pdf',jsonb_build_object('exhibitor_id',exhibitor));
  select count(*) into count_rows from public.herdmaster_export('test-hash','results');
  if count_rows<>1 then raise exception 'Unlinked entry exported or linked entry missing'; end if;
  select payload into result from public.herdmaster_export('test-hash','results');
  if result->>'herdmaster_animal_id'<>'HM-string-ID' or result->>'placement'<>'1' then raise exception 'Result identity incorrect'; end if;
  update public.entries set placement=3 where id=entry;
  select payload into result from public.herdmaster_export('test-hash','results');
  if result->>'placement'<>'3' then raise exception 'Correction missing on rescan'; end if;
  select count(*) into count_rows from public.herdmaster_export('other-hash','results');
  if count_rows<>0 then raise exception 'Cross-account results exposed'; end if;
  select count(*) into count_rows from public.herdmaster_export('other-hash','reports');
  if count_rows<>0 then raise exception 'Cross-account reports exposed'; end if;
  update public.show_report_artifacts set is_current=false where id=artifact;
  select count(*) into count_rows from public.herdmaster_export('test-hash','results');
  if count_rows<>0 then raise exception 'Superseded report did not gate results'; end if;
  update public.show_report_artifacts set is_current=true where id=artifact;
  update public.shows set is_demo=true where id=show_id;
  select count(*) into count_rows from public.herdmaster_export('test-hash','results');
  if count_rows<>0 then raise exception 'Demo results exposed'; end if;
  update public.herdmaster_connections set revoked_at=now() where id=connection;
  begin
    perform public.herdmaster_export('test-hash','results');
    raise exception 'Revoked token accepted';
  exception when invalid_authorization_specification then null; end;
  update public.herdmaster_connections set revoked_at=null,expires_at=now()-interval '1 second' where id=connection;
  begin
    perform public.herdmaster_apply_animals('test-hash','[]');
    raise exception 'Expired token accepted';
  exception when invalid_authorization_specification then null; end;
  if has_function_privilege('authenticated','public.herdmaster_apply_animals(text,jsonb)','execute')
    or has_function_privilege('anon','public.herdmaster_export(text,text,uuid)','execute')
    or has_table_privilege('authenticated','public.herdmaster_connections','select') then raise exception 'Partner tables exposed to client'; end if;
  raise notice 'HerdMaster database assertions passed';
end $$;
