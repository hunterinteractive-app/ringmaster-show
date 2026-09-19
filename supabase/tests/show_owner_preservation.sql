begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
create temporary table owner_fixture(key text primary key, id uuid default gen_random_uuid());
insert into owner_fixture(key) values ('creator'),('owner'),('staff'),('show'),('explicit');
insert into auth.users(id) select id from owner_fixture where key in ('creator','owner','staff');
insert into public.shows(id,name,created_by,start_date,end_date)
select id,'Ownership regression',(select id from owner_fixture where key='creator'),'2026-10-01','2026-10-01'
from owner_fixture where key='show';
select is((select owner_user_id from public.shows where id=(select id from owner_fixture where key='show')),
 (select id from owner_fixture where key='creator'),'creator becomes owner when omitted');
insert into public.role_assignments(show_id,user_id,role)
select (select id from owner_fixture where key='show'),id,'superintendent' from owner_fixture where key in ('creator','staff');
select ok(public.user_can_manage_show_settings((select id from owner_fixture where key='show'),(select id from owner_fixture where key='creator')),
 'creator retains settings access even with only superintendent staff role');
select ok(public.user_can_enter_results((select id from owner_fixture where key='show'),(select id from owner_fixture where key='creator')),
 'owner can enter results');
select ok(public.user_can_finalize_show((select id from owner_fixture where key='show'),(select id from owner_fixture where key='creator')),
 'owner can close out show');
select ok(not public.user_can_manage_show_settings((select id from owner_fixture where key='show'),(select id from owner_fixture where key='staff')),
 'unrelated superintendent does not gain settings access');
insert into public.shows(id,name,created_by,owner_user_id,start_date,end_date)
select id,'Explicit owner regression',(select id from owner_fixture where key='creator'),(select id from owner_fixture where key='owner'),'2026-10-01','2026-10-01'
from owner_fixture where key='explicit';
update public.shows set owner_user_id=null where id=(select id from owner_fixture where key='explicit');
select is((select owner_user_id from public.shows where id=(select id from owner_fixture where key='explicit')),
 (select id from owner_fixture where key='owner'),'clearing an explicit owner preserves it instead of restoring creator');
select ok(not public.user_can_manage_show_settings((select id from owner_fixture where key='explicit'),(select id from owner_fixture where key='creator')),
 'creator does not gain settings access when another owner is assigned');
update public.shows set owner_user_id=(select id from owner_fixture where key='staff') where id=(select id from owner_fixture where key='explicit');
select is((select owner_user_id from public.shows where id=(select id from owner_fixture where key='explicit')),
 (select id from owner_fixture where key='staff'),'explicit ownership transfers remain possible');
select * from finish();
rollback;
