-- Focused trigger integration suite. Run in an isolated database with the
-- production eligibility function/trigger and minimal cart/catalog tables.
begin;
set local search_path=public,extensions;
select no_plan();
create temporary table fx(k text primary key,id uuid default gen_random_uuid());
insert into fx(k) values('show'),('other_show'),('section'),('regular_section'),('other_section'),('disabled_section'),('cart');
create function pg_temp.id(text) returns uuid language sql as $$select id from fx where k=$1$$;
insert into shows(id) values(pg_temp.id('show')),(pg_temp.id('other_show'));
insert into breeds(name,species,class_system,is_active,local_show_id) values
('Californian','rabbit','six',true,null),('New Zealand','rabbit','six',true,null),
('Dutch','rabbit','four',true,null),('Retired Six','rabbit','six',false,null),
('Local Six','rabbit','six',true,pg_temp.id('show')),('Cavy Six','cavy','six',true,null);
insert into show_breeds select pg_temp.id('show'),id,false from breeds;
insert into show_sections values
(pg_temp.id('section'),pg_temp.id('show'),true,'meat_only',false),
(pg_temp.id('regular_section'),pg_temp.id('show'),true,'all',false),
(pg_temp.id('disabled_section'),pg_temp.id('show'),false,'meat_only',true),
(pg_temp.id('other_section'),pg_temp.id('other_show'),true,'meat_only',true);
insert into show_commercial_classes values(pg_temp.id('show'),'meat_pen',true);
insert into entry_carts values(pg_temp.id('cart'),pg_temp.id('show'));
create function pg_temp.add_pen(breed text default 'Californian',section_key text default 'section',species text default 'rabbit',fur boolean default false)
returns void language sql as $$insert into entry_cart_items(cart_id,section_id,breed,species,class_name,is_fur) values(pg_temp.id('cart'),pg_temp.id(section_key),breed,species,'Meat Pen',fur)$$;
select lives_ok($$select pg_temp.add_pen()$$,'Californian meat pen enters cart with all regular breeds disabled');
select lives_ok($$select pg_temp.add_pen('New Zealand')$$,'another master six-class breed is eligible');
select lives_ok($$insert into entries(show_id,section_id,breed,species,class_name) select pg_temp.id('show'),section_id,breed,species,class_name from entry_cart_items$$,'cart-to-entry conversion revalidates and accepts meat pens');
select is((select count(*)::int from entries),2,'both meat pens convert to entries');
select throws_ok($$select pg_temp.add_pen('Dutch')$$,'23514','Meat pens require an active six-class rabbit breed from the master catalog.','four-class breed blocked');
select throws_ok($$select pg_temp.add_pen('Retired Six')$$,'23514','Meat pens require an active six-class rabbit breed from the master catalog.','inactive master breed blocked');
select throws_ok($$select pg_temp.add_pen('Local Six')$$,'23514','Meat pens require an active six-class rabbit breed from the master catalog.','show-local six-class breed blocked');
select throws_ok($$select pg_temp.add_pen('Made Up')$$,'23514','Meat pens require an active six-class rabbit breed from the master catalog.','unknown breed blocked');
select throws_ok($$select pg_temp.add_pen('Cavy Six','section','cavy')$$,'23514','Meat pens must be rabbit entries, not fur entries.','cavy blocked');
select throws_ok($$select pg_temp.add_pen('Californian','section','rabbit',true)$$,'23514','Meat pens must be rabbit entries, not fur entries.','fur cannot use meat-pen bypass');
select throws_ok($$select pg_temp.add_pen('Californian','regular_section')$$,'23514','Meat Pens are not enabled for the selected show section.','section without meat classes blocked');
select throws_ok($$select pg_temp.add_pen('Californian','disabled_section')$$,'23514','Meat Pens are not enabled for the selected show section.','disabled section blocked');
select throws_ok($$select pg_temp.add_pen('Californian','other_section')$$,'23514','Meat Pens are not enabled for the selected show section.','cross-show section blocked');
select throws_ok($$select pg_temp.add_pen('Californian','missing_section')$$,'23514','Meat Pens are not enabled for the selected show section.','missing section blocked');
update show_sections set allow_meat_classes=true where id=pg_temp.id('regular_section');
select lives_ok($$select pg_temp.add_pen('Californian','regular_section')$$,'ordinary section with commercial classes enabled accepts meat pens');
update show_commercial_classes set is_enabled=false;
select throws_ok($$select pg_temp.add_pen()$$,'23514','Meat Pens are not enabled for the selected show section.','disabled commercial class blocked');
select throws_ok($$insert into entries(show_id,section_id,breed,species,class_name) values(pg_temp.id('show'),pg_temp.id('section'),'Californian','rabbit','Meat Pen')$$,'23514','Meat Pens are not enabled for the selected show section.','checkout rechecks commercial class availability');
update show_commercial_classes set is_enabled=true;
select throws_ok($$insert into entries(show_id,section_id,breed,species,class_name) values(pg_temp.id('show'),pg_temp.id('section'),'Dutch','rabbit','Meat Pen')$$,'23514','Meat pens require an active six-class rabbit breed from the master catalog.','direct entry rejects four-class meat pen');
select throws_ok($$update entry_cart_items set class_name='Senior'$$,'23514','The breed Californian (rabbit) is not enabled for this show.','changing meat pen to regular entry rechecks breed restriction');
select throws_ok($$update entries set class_name='Senior' where breed='Californian'$$,'23514','The breed Californian (rabbit) is not enabled for this show.','changing submitted meat pen to regular entry rechecks restriction');
select throws_ok($$update entry_cart_items set section_id=pg_temp.id('other_section')$$,'23514','Meat Pens are not enabled for the selected show section.','moving cart pen to another show rechecks section');
select throws_ok($$update entries set is_fur=true$$,'23514','Meat pens must be rabbit entries, not fur entries.','converting submitted pen to fur rejected');
select throws_ok($$insert into entry_cart_items(cart_id,section_id,breed,species,class_name) values(pg_temp.id('cart'),pg_temp.id('section'),'Californian','rabbit','Senior')$$,'23514','The breed Californian (rabbit) is not enabled for this show.','regular entries still honor show breed restrictions');
update show_breeds set is_enabled=true where breed_id=(select id from breeds where name='Californian');
select lives_ok($$insert into entry_cart_items(cart_id,section_id,breed,species,class_name) values(pg_temp.id('cart'),pg_temp.id('regular_section'),'Californian','rabbit','Senior')$$,'enabled regular breed remains accepted');
select lives_ok($$insert into entry_cart_items(cart_id,is_checkin_fee_carrier) values(pg_temp.id('cart'),true)$$,'non-animal fee carriers remain exempt');
grant select on fx to authenticated;
set local role authenticated;
select lives_ok($$select pg_temp.add_pen()$$,'ordinary exhibitor can read published commercial settings and add pen');
reset role;
update shows set is_published=false where id=pg_temp.id('show');
set local role authenticated;
select is((select count(*)::int from show_commercial_classes),0,'unpublished commercial settings remain private');
reset role;
select * from finish();
rollback;
