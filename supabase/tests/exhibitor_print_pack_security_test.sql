-- Run after the isolated fixture and restricted_exhibitor_print_packs migration.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $$ begin
  if public.can_access_exhibitor_print_pack('22222222-2222-4222-8222-222222222222') then
    raise exception 'Unlisted show manager was allowed'; end if;
  begin
    perform public.queue_exhibitor_print_pack('22222222-2222-4222-8222-222222222222');
    raise exception 'Unlisted account queued pack';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.exhibitor_print_pack_accounts values(auth.uid(),now());
    raise exception 'Account self-granted access';
  exception when insufficient_privilege then null; end;
  begin
    perform public.claim_exhibitor_print_pack();
    raise exception 'Account claimed internal job';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','3e8dddf9-3a17-4ebb-aeab-9b51d31e7871',false);
do $$ declare v_id uuid; v_sources jsonb; begin
  v_id := public.queue_exhibitor_print_pack('22222222-2222-4222-8222-222222222222');
  if v_id <> public.queue_exhibitor_print_pack('22222222-2222-4222-8222-222222222222') then
    raise exception 'Duplicate busy pack'; end if;
  select sources into v_sources from public.exhibitor_print_packs where id=v_id;
  if jsonb_array_length(v_sources)<>4 or v_sources->0->>'label' <> 'Zoe Adams - Exhibitor Report'
     or v_sources->1->>'label' <> 'Zoe Adams - Legs'
     or v_sources->2->>'label' <> 'Aaron Brown - Exhibitor Report' then
    raise exception 'Incorrect completeness or ordering: %',v_sources; end if;
  begin
    insert into storage.objects(bucket_id,name) values('exhibitor-print-packs','fake.pdf');
    raise exception 'Client uploaded restricted PDF';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.exhibitor_print_packs set artifact_status='generated';
insert into storage.objects(bucket_id,name) select storage_bucket,storage_path from public.exhibitor_print_packs;
insert into storage.objects(bucket_id,name) values('show-files','ordinary.pdf');
set role authenticated;
select set_config('request.jwt.claim.sub','cad4eb5f-239a-4990-b372-e8a43e3faee8',false);
do $$ begin
  if (select count(*) from storage.objects) <> 2 then raise exception 'Second allowed account cannot download'; end if;
end $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $$ begin
  if exists(select 1 from public.exhibitor_print_packs) then raise exception 'Private rows leaked'; end if;
  if (select count(*) from storage.objects) <> 1 then raise exception 'Storage protection or ordinary download broken'; end if;
end $$;
reset role;
update public.show_report_artifacts set artifact_status='queued';
set role authenticated;
select set_config('request.jwt.claim.sub','3e8dddf9-3a17-4ebb-aeab-9b51d31e7871',false);
do $$ begin
  begin
    perform public.queue_exhibitor_print_pack('22222222-2222-4222-8222-222222222222');
    raise exception 'Incomplete sources accepted';
  exception when raise_exception then
    if sqlerrm not like 'Finish generating%' then raise; end if;
  end;
end $$;
reset role;
delete from public.exhibitor_print_pack_accounts where user_id='3e8dddf9-3a17-4ebb-aeab-9b51d31e7871';
set role authenticated;
do $$ begin
  if exists(select 1 from public.exhibitor_print_packs) then raise exception 'Revoked access still works'; end if;
  if (select count(*) from storage.objects) <> 1 then raise exception 'Revoked download still works'; end if;
end $$;
reset role;
set role anon;
do $$ begin
  if exists(select 1 from storage.objects) then raise exception 'Anonymous download works'; end if;
end $$;
reset role;
select 'Print pack security tests passed' as result;
