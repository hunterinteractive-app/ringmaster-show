begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table link_fixture(key text primary key,id uuid default gen_random_uuid(),token text);
insert into link_fixture(key) values('show'),('legacy'),('no_portal'),('outsider');
grant select,update on link_fixture to authenticated,service_role;
insert into auth.users(id) select id from link_fixture where key='outsider';
insert into public.shows(id,name,start_date,end_date)
select id,'Email link fixture',current_date,current_date+1 from link_fixture where key<>'outsider';

select ok(not has_table_privilege('authenticated','checkin_links_private.portal_links','select'),'portal tokens are not exposed to ordinary table readers');
select ok(not has_function_privilege('anon','public.get_show_checkin_email_link(uuid)','execute'),'anonymous callers cannot retrieve email links');
select ok(not has_function_privilege('authenticated','public.get_show_checkin_email_link(uuid)','execute'),'email link retrieval is service-only');
select ok(not has_function_privilege('authenticated','public.remember_show_checkin_portal_token(uuid,text)','execute'),'legacy link import is service-only');
select ok(not (select prosecdef from pg_proc where oid='public.regenerate_show_checkin_portal_token(uuid)'::regprocedure),'public generation wrapper runs with invoker privileges');

select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from link_fixture where key='outsider'),'role','authenticated')::text,true);
set local role authenticated;
select throws_ok($$select public.regenerate_show_checkin_portal_token((select id from link_fixture where key='show'))$$,'42501','You do not have permission to manage this show''s check-in portal','unrelated user cannot generate a portal');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
update link_fixture set token=public.regenerate_show_checkin_portal_token(id) where key='show';
select is(public.get_show_checkin_email_link((select id from link_fixture where key='show')),null::text,'creating a token does not enable the portal');
select is(public.get_show_checkin_email_link((select id from link_fixture where key='no_portal')),null::text,'shows with no portal have no email link');
update public.show_checkin_settings set is_enabled=true,opens_at=now()+interval '1 day',closes_at=now()+interval '2 days'
where show_id=(select id from link_fixture where key='show');
select is(public.get_show_checkin_email_link((select id from link_fixture where key='show')),
  'https://checkin.ringmasterone.com/#/checkin?token='||(select token from link_fixture where key='show'),'newly generated links are automatically saved and available for advance emails');
select throws_ok($$select public.get_exhibitor_checkin_portal_show((select token from link_fixture where key='show'))$$,'P0001','Check-in is not available','email link does not bypass the opening time');

insert into public.show_checkin_settings(show_id,is_enabled,portal_token_hash)
select id,true,encode(extensions.digest(repeat('a',64),'sha256'),'hex') from link_fixture where key='legacy';
select is(public.get_show_checkin_email_link((select id from link_fixture where key='legacy')),null::text,'old hashes do not produce fabricated links');
select throws_ok($$select public.remember_show_checkin_portal_token((select id from link_fixture where key='legacy'),repeat('b',64))$$,'22023','This link does not match the show''s current check-in page.','mismatched links are rejected');
select lives_ok($$select public.remember_show_checkin_portal_token((select id from link_fixture where key='legacy'),repeat('a',64))$$,'the exact existing link can be imported');
select is(public.get_show_checkin_email_link((select id from link_fixture where key='legacy')),
  'https://checkin.ringmasterone.com/#/checkin?token='||repeat('a',64),'import keeps the existing QR token');
select is((select portal_token_hash from public.show_checkin_settings where show_id=(select id from link_fixture where key='legacy')),
  encode(extensions.digest(repeat('a',64),'sha256'),'hex'),'import never rotates the token hash');
select is(public.get_exhibitor_checkin_portal_show(repeat('a',64))->>'show_name','Email link fixture','the existing public QR link still resolves');
update link_fixture set token=public.regenerate_show_checkin_portal_token(id) where key='legacy';
select is(public.get_show_checkin_email_link((select id from link_fixture where key='legacy')),
  'https://checkin.ringmasterone.com/#/checkin?token='||(select token from link_fixture where key='legacy'),'regeneration replaces the saved email link');
select throws_ok($$select public.get_exhibitor_checkin_portal_show(repeat('a',64))$$,'P0001','Check-in is not available','regeneration still invalidates the previous link');
update public.show_checkin_settings set is_enabled=false where show_id=(select id from link_fixture where key='legacy');
select is(public.get_show_checkin_email_link((select id from link_fixture where key='legacy')),null::text,'disabled portals are omitted from emails');
update public.show_checkin_settings set is_enabled=true,portal_token_hash=encode(extensions.digest(repeat('c',64),'sha256'),'hex')
where show_id=(select id from link_fixture where key='legacy');
select is(public.get_show_checkin_email_link((select id from link_fixture where key='legacy')),null::text,'a stale stored token is never emailed');
reset role;
select * from finish();
rollback;
