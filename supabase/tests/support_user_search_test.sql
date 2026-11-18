-- Run after the migration inside a transaction against the local fixture.
create function pg_temp.assert_ok(ok boolean, label text) returns void
language plpgsql as $$ begin
  if not coalesce(ok, false) then raise exception 'FAIL: %', label; end if;
  raise notice 'PASS: %', label;
end $$;

insert into auth.users(id,email,raw_user_meta_data) values
 ('a0000000-0000-4000-8000-000000000001','search-admin@example.invalid','{}'),
 ('a0000000-0000-4000-8000-000000000002','fixture-kim@example.invalid','{}'),
 ('a0000000-0000-4000-8000-000000000003','fixture-metadata@example.invalid','{"full_name":"Fixture Metadata Person"}'),
 ('a0000000-0000-4000-8000-000000000004','fixture-deleted@example.invalid','{}');
insert into public.super_admins(user_id) values('a0000000-0000-4000-8000-000000000001');
insert into public.profiles(user_id,email,display_name) values
 ('a0000000-0000-4000-8000-000000000002',null,'')
 on conflict(user_id) do update set email=null,display_name='';
delete from public.profiles where user_id='a0000000-0000-4000-8000-000000000003';
update auth.users set deleted_at=now() where id='a0000000-0000-4000-8000-000000000004';
insert into public.exhibitors(owner_user_id,display_name,showing_name,email) values
 ('a0000000-0000-4000-8000-000000000002','Fixture Joseph Wyatt, Cody Kapacziewski','Fixture alternate name','fixture-contact@example.invalid'),
 ('a0000000-0000-4000-8000-000000000002','Fixture Second Child',null,'fixture-child@example.invalid');

select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('fixture-kim@example.invalid')), 'login email with blank profile');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('Joseph Wyatt, Cody Kapacziewski')), 'comma-separated exhibitor name');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('KAPACZIEWSKI joseph')), 'case-insensitive out-of-order partial names');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('Fixture Second Child')), 'non-primary exhibitor');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('fixture-contact@example.invalid')), 'exhibitor email');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('Fixture alternate')), 'showing name');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('Fixture Metadata Person')), 'metadata name without profile');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('fixture-kim')), 'one result per login despite multiple exhibitors');
select pg_temp.assert_ok((select email='fixture-kim@example.invalid' and exhibitor_name like '%Second Child%' from public.search_support_users('fixture-kim')), 'login email and linked names returned');
select pg_temp.assert_ok((select count(*)=0 from public.search_support_users('fixture-deleted')), 'deleted account excluded');
select pg_temp.assert_ok((select count(*)=0 from public.search_support_users('%_*')), 'wildcards treated literally');
select pg_temp.assert_ok((select count(*)=0 from public.search_support_users(',,,,')), 'punctuation-only search does not return directory');
select pg_temp.assert_ok((select count(*)=1 from public.search_support_users('',1)), 'initial list limit');
select pg_temp.assert_ok((select count(*)=0 from public.search_support_users('x')), 'minimum query length');
reset role;
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$ begin
  perform * from public.search_support_users('fixture');
  raise exception 'FAIL: non-admin searched users';
exception when insufficient_privilege then raise notice 'PASS: non-admin denied'; end $$;
do $$ begin
  perform * from support_search_private.search_users('fixture');
  raise exception 'FAIL: non-admin bypassed wrapper';
exception when insufficient_privilege then raise notice 'PASS: private function denies non-admin'; end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  perform * from public.search_support_users('fixture');
  raise exception 'FAIL: anonymous search';
exception when insufficient_privilege then raise notice 'PASS: anonymous denied'; end $$;
reset role;
select pg_temp.assert_ok(not has_function_privilege('anon','public.search_support_users(text,integer)','EXECUTE'), 'anonymous execute revoked');
select pg_temp.assert_ok(not has_schema_privilege('anon','support_search_private','USAGE'), 'private schema hidden from anonymous users');
select pg_temp.assert_ok((select not prosecdef from pg_proc where oid='public.search_support_users(text,integer)'::regprocedure), 'public wrapper is security invoker');
