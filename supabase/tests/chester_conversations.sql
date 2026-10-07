-- Run after the migration; transaction leaves no fixtures behind.
begin;
insert into auth.users(id,email) values('91000000-0000-0000-0000-000000000001','chester-test-a@example.invalid'),('91000000-0000-0000-0000-000000000002','chester-test-b@example.invalid'),('91000000-0000-0000-0000-000000000003','chester-test-admin@example.invalid');
insert into public.super_admins(user_id) values('91000000-0000-0000-0000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
select public.chester_append('92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',0,'user','My question','My Entries','entries','chat');
select public.chester_append('92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',0,'user','My question','My Entries','entries','chat');
select public.chester_append('92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000002',1,'assistant','Prepared answer','My Entries','entries','prepared');
do $$ begin
 begin perform public.chester_review(); raise exception 'FAIL user read'; exception when others then if sqlerrm='FAIL user read' then raise; end if; end;
 begin perform * from assistant_private.messages; raise exception 'FAIL direct read'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin perform public.chester_append('92000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000003',2,'user','Intrusion','Home','help','chat'); raise exception 'FAIL cross-user append'; exception when others then if sqlerrm='FAIL cross-user append' then raise; end if; end;
 begin perform public.chester_review('92000000-0000-0000-0000-000000000001'); raise exception 'FAIL cross-user read'; exception when others then if sqlerrm='FAIL cross-user read' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000003',true);
do $$ declare v jsonb; begin
 v:=public.chester_review('92000000-0000-0000-0000-000000000001');
 if jsonb_array_length(v)<>2 or v->0->>'content'<>'My question' or v->1->>'content'<>'Prepared answer' then raise exception 'FAIL transcript ordering/idempotency'; end if;
end $$;
set local role anon;
do $$ begin
 begin perform public.chester_review(); raise exception 'FAIL anonymous read'; exception when insufficient_privilege then null; end;
end $$;
rollback;
