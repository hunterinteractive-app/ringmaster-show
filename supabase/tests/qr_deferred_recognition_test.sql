-- Included inside the QR runner's rollback-only synthetic transaction.
create temp table qr_recognition_fixture(k text primary key,id uuid default gen_random_uuid());
insert into qr_recognition_fixture(k) values ('show'),('section'),('entry');
grant select on qr_recognition_fixture to anon,authenticated;
insert into catalog_recognition_history(species,breed_name,status,effective_date,source_note) values
 ('rabbit','QR Recognition Fixture','cod','2026-01-01','local regression'),
 ('rabbit','QR Recognition Fixture','recognized','2026-12-01','local regression'),
 ('rabbit','QR Recognition Fixture','retired','2028-01-01','local regression');
insert into shows(id,name,start_date,end_date,is_published,is_locked,owner_user_id,created_by)
select id,'QR recognition regression','2026-11-14','2028-01-01',true,false,
 (select owner_user_id from shows where owner_user_id is not null limit 1),
 (select owner_user_id from shows where owner_user_id is not null limit 1)
from qr_recognition_fixture where k='show';
insert into show_sections(id,show_id,kind,letter,judging_date,is_enabled)
select id,(select id from qr_recognition_fixture where k='show'),'open','A','2026-12-01',true
from qr_recognition_fixture where k='section';
insert into entries(id,show_id,section_id,species,breed,variety,sex,class_name,status)
select id,(select id from qr_recognition_fixture where k='show'),(select id from qr_recognition_fixture where k='section'),
 'rabbit','QR Recognition Fixture','Black','Doe','Senior','submitted'
from qr_recognition_fixture where k='entry';
set constraints all immediate;
set constraints all deferred;
create function pg_temp.qr_recognition_save(awards text[]) returns text language plpgsql security invoker as $$
begin
 perform public.save_results_entry((select id from qr_recognition_fixture where k='show'),
   (select id from qr_recognition_fixture where k='entry'),'1','Shown',null,true,false,null,
   'QR Regression','3175550100',awards,true);
 set constraints all immediate;
 set constraints all deferred;
 return 'saved';
exception when others then return sqlerrm;
end $$;
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
select pg_temp.check_qr(pg_temp.qr_recognition_save(array['BOV'])='saved','anonymous recognized BOV passes deferred checks');
select pg_temp.check_qr(pg_temp.qr_recognition_save(array['BOV','BOB'])='saved','anonymous recognized BOB passes deferred checks');
reset role;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}',true);
set local role authenticated;
select pg_temp.check_qr(pg_temp.qr_recognition_save(array['BOV'])='saved','nonstaff signed-in BOV passes deferred checks');
reset role;
update show_sections set judging_date='2026-11-14' where id=(select id from qr_recognition_fixture where k='section');
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
select pg_temp.check_qr(pg_temp.qr_recognition_save(array['BOV'])='saved','COD BOV remains permitted');
select pg_temp.check_qr(pg_temp.qr_recognition_save(array['BOV','BOB'])='saved','COD BOB passes anonymous deferred check');
select pg_temp.check_qr(pg_temp.qr_recognition_save(array['BOSV','BOSB'])='saved','COD BOSB passes anonymous deferred check');
select pg_temp.check_qr(position('COD entries may receive' in pg_temp.qr_recognition_save(array['BOV','BOB','BIS']))>0,'COD BIS still rejected by deferred check');
reset role;
update show_sections set judging_date='2028-01-01' where id=(select id from qr_recognition_fixture where k='section');
set local role anon;
select pg_temp.check_qr(position('Retired or undated' in pg_temp.qr_recognition_save(array['BOV']))>0,'retired BOV still rejected by deferred check');
reset role;
