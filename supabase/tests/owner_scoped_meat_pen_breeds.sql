-- Run after meat_pen_master_six_class_fixture.sql and both breed migrations.
begin;
set local search_path=public,extensions;
select no_plan();
create temporary table fx(k text primary key,id uuid default gen_random_uuid());
insert into fx(k) values('kyle'),('future'),('other'),('section'),('other_section'),('cart'),('other_cart');
create function pg_temp.id(text) returns uuid language sql as $$select id from fx where k=$1$$;
insert into shows(id,owner_user_id) values
(pg_temp.id('kyle'),'bca983ed-59ac-4615-a9a7-a2ce56d3d8e8'),
(pg_temp.id('future'),'bca983ed-59ac-4615-a9a7-a2ce56d3d8e8'),
(pg_temp.id('other'),gen_random_uuid());
insert into breeds(name,species,class_system,is_active) select n,'rabbit',case when n='Rex' then 'four' else 'six' end,true
from unnest(array['American','American Chinchilla','Argente Brun','Californian','Champagne d''Argent','Cinnamon','Creme d''Argente','New Zealand','Palomino','Satin','Rex','Beveren','Blanc de Hotot','Checkered Giant','English Lop','Flemish Giant','French Lop','Giant Angora','Giant Chinchilla','Silver Fox','Argenté St. Hubert (COD)']) n;
insert into breeds(name,species,class_system,is_active,local_show_id) values
('American','cavy','six',true,null),('Local Six','rabbit','six',true,pg_temp.id('kyle')),
('Retired Six','rabbit','six',false,null);
select results_eq($$select name from meat_pen_breeds(pg_temp.id('kyle')) order by name$$,
 $$select unnest(array['American','American Chinchilla','Argente Brun','Californian','Champagne d''Argent','Cinnamon','Creme d''Argente','New Zealand','Palomino','Rex','Satin']) order by 1$$,
 'Kyle list exactly matches all eleven handbook breeds');
select is((select count(*)::int from meat_pen_breeds(pg_temp.id('other'))),20,'other owner keeps twenty master six-class breeds');
select results_eq($$select name from meat_pen_breeds(pg_temp.id('future'))$$,$$select name from meat_pen_breeds(pg_temp.id('kyle'))$$,'future show owned by Kyle gets same list');
select is((select count(*)::int from meat_pen_breeds(gen_random_uuid())),0,'unknown show gets no breeds');
select is((select count(*)::int from meat_pen_breeds(null)),0,'missing show gets no breeds');
select is((select class_system from breeds where name='Rex'),'four','Rex master classification remains four');
select is((select count(*)::int from meat_pen_breeds(pg_temp.id('other')) where name='Rex'),0,'Rex not added for other owners');
update breeds set is_active=false where name='Rex';
select is((select count(*)::int from meat_pen_breeds(pg_temp.id('kyle')) where name='Rex'),0,'inactive allowed breed stays hidden');
update breeds set is_active=true where name='Rex';
insert into show_sections values
(pg_temp.id('section'),pg_temp.id('kyle'),true,'meat_only',true),
(pg_temp.id('other_section'),pg_temp.id('other'),true,'meat_only',true);
insert into show_commercial_classes values(pg_temp.id('kyle'),'meat_pen',true),(pg_temp.id('other'),'meat_pen',true);
insert into entry_carts values(pg_temp.id('cart'),pg_temp.id('kyle')),(pg_temp.id('other_cart'),pg_temp.id('other'));
insert into show_breeds select pg_temp.id('kyle'),id,false from breeds;
select lives_ok($$insert into entry_cart_items(cart_id,section_id,breed,species,class_name)
values(pg_temp.id('cart'),pg_temp.id('section'),'Rex','rabbit','Meat Pen')$$,'Kyle cart accepts four-class Rex even with ordinary breed entries disabled');
select lives_ok($$insert into entries(show_id,section_id,breed,species,class_name)
select pg_temp.id('kyle'),section_id,breed,species,class_name from entry_cart_items$$,'checkout conversion accepts Rex');
select throws_ok($$insert into entries(show_id,section_id,breed,species,class_name)
values(pg_temp.id('kyle'),pg_temp.id('section'),'Beveren','rabbit','Meat Pen')$$,'23514','This breed is not eligible for meat pens at this show.','secretary/direct entry cannot bypass list');
select throws_ok($$update entry_cart_items set breed='Beveren'$$,'23514','This breed is not eligible for meat pens at this show.','cart breed edits cannot bypass list');
select throws_ok($$update entries set breed='Beveren'$$,'23514','This breed is not eligible for meat pens at this show.','submitted entry breed edits cannot bypass list');
select throws_ok($$insert into entry_cart_items(cart_id,section_id,breed,species,class_name)
values(pg_temp.id('other_cart'),pg_temp.id('other_section'),'Rex','rabbit','Meat Pen')$$,'23514','This breed is not eligible for meat pens at this show.','other owner cannot submit Rex');
select lives_ok($$insert into entry_cart_items(cart_id,section_id,breed,species,class_name)
values(pg_temp.id('other_cart'),pg_temp.id('other_section'),'Beveren','rabbit','Meat Pen')$$,'other owner can still submit Beveren');
select throws_ok($$update entry_cart_items set cart_id=pg_temp.id('other_cart'),section_id=pg_temp.id('other_section') where breed='Rex'$$,'23514','This breed is not eligible for meat pens at this show.','moving a Rex cart item to another owner revalidates');
select throws_ok($$update entries set show_id=pg_temp.id('other'),section_id=pg_temp.id('other_section')$$,'23514','This breed is not eligible for meat pens at this show.','moving a submitted Rex to another owner revalidates');
select throws_ok($$update entries set class_name='Senior'$$,'23514','The breed Rex (rabbit) is not enabled for this show.','regular breed restrictions remain unchanged');
update shows set owner_user_id=gen_random_uuid() where id=pg_temp.id('future');
select is((select count(*)::int from meat_pen_breeds(pg_temp.id('future')) where name='Rex'),0,'scope follows owner after transfer');
select ok(not has_function_privilege('anon','public.meat_pen_breeds(uuid)','execute'),'anonymous calls not granted');
select ok(not (select prosecdef from pg_proc where oid='public.meat_pen_breeds(uuid)'::regprocedure),'RPC preserves caller RLS');
alter table public.shows enable row level security;
create policy test_published_shows on public.shows for select to authenticated using (is_published);
update shows set is_published=false where id=pg_temp.id('future');
grant select on fx to authenticated;
set local role authenticated;
select is((select count(*)::int from meat_pen_breeds(pg_temp.id('future'))),0,'lookup honors show visibility RLS');
select is((select count(*)::int from meat_pen_breeds(pg_temp.id('kyle'))),11,'authenticated exhibitor receives handbook list');
select lives_ok($$insert into entry_cart_items(cart_id,section_id,breed,species,class_name)
values(pg_temp.id('cart'),pg_temp.id('section'),' rex ','rabbit','Meat Pen')$$,'authenticated exhibitor can add Rex with existing normalization');
reset role;
select * from finish();
rollback;
