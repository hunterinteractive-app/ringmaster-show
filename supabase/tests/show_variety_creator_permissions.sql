begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(7);
create temp table variety_fixture(k text primary key,id uuid default gen_random_uuid());
insert into variety_fixture(k) values ('owner'),('outsider'),('show'),('other'),('row');
grant select on variety_fixture to authenticated;
insert into auth.users(id) select id from variety_fixture where k in ('owner','outsider');
insert into public.shows(id,name,start_date,end_date,created_by)
select id,'Variety permission fixture',current_date,current_date,(select id from variety_fixture where k=case when s.k='show' then 'owner' else 'outsider' end)
from variety_fixture s where k in ('show','other');
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from variety_fixture where k='owner'))::text,true);
select lives_ok($$insert into public.show_varieties(id,show_id,breed_id,variety_id,custom_name,is_enabled) select (select id from variety_fixture where k='row'),(select id from variety_fixture where k='show'),breed_id,id,null,true from public.varieties limit 1$$,'creator can initialize variety overrides');
select is((select count(*)::int from public.show_varieties where id=(select id from variety_fixture where k='row')),1,'creator can read saved override');
select lives_ok($$update public.show_varieties set is_enabled=false where id=(select id from variety_fixture where k='row')$$,'creator can update override');
select throws_ok($$update public.show_varieties set show_id=(select id from variety_fixture where k='other') where id=(select id from variety_fixture where k='row')$$,'42501',null,'creator cannot move override into another show');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from variety_fixture where k='outsider'))::text,true);
select throws_ok($$insert into public.show_varieties(show_id,breed_id,variety_id,is_enabled) select (select id from variety_fixture where k='show'),breed_id,id,true from public.varieties limit 1$$,'42501',null,'unrelated user cannot add override');
with changed as (update public.show_varieties set is_enabled=true where id=(select id from variety_fixture where k='row') returning id) select is((select count(*)::int from changed),0,'unrelated user cannot update override');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from variety_fixture where k='owner'))::text,true);
with removed as (delete from public.show_varieties where id=(select id from variety_fixture where k='row') returning id) select is((select count(*)::int from removed),1,'creator can remove override');
select * from finish();
rollback;
