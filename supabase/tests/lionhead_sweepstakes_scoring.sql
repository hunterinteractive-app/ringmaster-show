begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Independent arithmetic expectations, including fractional RIS and both caps.
select is(public.lionhead_sweepstakes_points('regular','BIS',null,0,20,1800,false),1500::numeric,'standard BIS cap');
select is(public.lionhead_sweepstakes_points('regular','BIS',null,0,20,80,false),80::numeric,'standard BIS below cap');
select is(public.lionhead_sweepstakes_points('regular','BIS',null,0,20,80,true),0::numeric,'no specialty BIS');
select is(public.lionhead_sweepstakes_points('convention','BIS',null,0,20,5000,false),3000::numeric,'Convention BIS cap');
select is(public.lionhead_sweepstakes_points('convention','BIS',null,0,20,1800,false),1800::numeric,'Convention uses higher cap');
select is(public.lionhead_sweepstakes_points('national','BIS',null,0,20,5000,true),0::numeric,'no national BIS');
select is(public.lionhead_sweepstakes_points('convention','BIS',null,0,20,5000,true),0::numeric,'specialty BIS stays zero even with Convention settings');
select is((select array_agg(public.lionhead_sweepstakes_points('regular','CLASS',n,8,20,80,false) order by n) from generate_series(1,6) n),array[48,32,24,16,8,0]::numeric[],'all standard class placements');
select is((select array_agg(public.lionhead_sweepstakes_points('national','CLASS',n,8,20,80,true) order by n) from generate_series(1,11) n),array[80,72,64,56,48,40,32,24,16,8,0]::numeric[],'all national class placements');
select is(public.lionhead_sweepstakes_points('regular','RIS',null,0,20,21,false),10.5::numeric,'RIS retains halves');
select is(public.lionhead_sweepstakes_points('regular','B4C',null,0,20,80,false),40::numeric,'B4C uses breed population');
select is(public.lionhead_sweepstakes_points('national','RIS',null,0,20,80,true),0::numeric,'national RIS is zero');
select is(public.lionhead_sweepstakes_points('convention','B4C',null,0,20,80,false),0::numeric,'Convention B4C is zero');

create temporary table lion_fixture(key text primary key, id uuid default gen_random_uuid());
insert into lion_fixture(key) values ('owner'),('show'),('exhibitor'),('open_a'),('open_b'),('youth_a'),('specialty'),('disabled');
insert into auth.users(id) select id from lion_fixture where key='owner';
insert into public.shows(id,name,created_by,owner_user_id,timezone,start_date,end_date)
select (select id from lion_fixture where key='show'),'Lionhead scoring fixture',id,id,'America/Los_Angeles',current_date,current_date
from lion_fixture where key='owner';
insert into public.exhibitors(id,first_name,last_name,exhibitor_number,email)
select id,'Lionhead','Fixture',998877,'lionhead-fixture@example.invalid' from lion_fixture where key='exhibitor';
insert into public.breeds(name,species)
select 'Lionhead','rabbit' where not exists (select 1 from public.breeds where name='Lionhead' and species::text='rabbit');
insert into public.show_sections(id,show_id,kind,letter,breed_scope,is_enabled)
select id,(select id from lion_fixture where key='show'),
  case when key='youth_a' then 'youth' else 'open' end,
  case key when 'open_b' then 'B' when 'specialty' then 'C' when 'disabled' then 'D' else 'A' end,
  case when key='specialty' then 'single' else 'all' end,key<>'disabled'
from lion_fixture where key in ('open_a','open_b','youth_a','specialty','disabled');
update public.show_sections set allowed_breed_ids=array(select id from public.breeds where name='Lionhead' and species::text='rabbit')
where id=(select id from lion_fixture where key='specialty');

insert into public.entries(show_id,section_id,exhibitor_id,species,breed,variety,sex,class_name,tattoo,placement)
select (select id from lion_fixture where key='show'),(select id from lion_fixture where key='open_a'),
  (select id from lion_fixture where key='exhibitor'),'rabbit','Lionhead','Tortoise','Buck','Senior','L'||n,n::text
from generate_series(1,12) n;
insert into public.entries(show_id,section_id,exhibitor_id,species,breed,variety,sex,class_name,tattoo,placement)
select (select id from lion_fixture where key='show'),(select id from lion_fixture where key='open_a'),
  (select id from lion_fixture where key='exhibitor'),'rabbit','Lionhead',v.variety,v.sex,v.class_name,v.tattoo,'1'
from (values ('Tortoise','Doe','Senior','DOE'),('Tortoise','Buck','Junior','JUNIOR'),('Ruby Eyed White','Buck','Senior','REW')) v(variety,sex,class_name,tattoo);
insert into public.entries(show_id,section_id,exhibitor_id,species,breed,sex,class_name,tattoo)
select (select id from lion_fixture where key='show'),(select id from lion_fixture where key='open_a'),
  (select id from lion_fixture where key='exhibitor'),'rabbit','Mini Rex','Buck','Senior','OTHER'||n
from generate_series(1,5) n;
insert into public.entries(show_id,section_id,exhibitor_id,species,breed,variety,sex,class_name,tattoo,placement,is_shown,is_disqualified,is_fur,scratched_at,result_status)
select (select id from lion_fixture where key='show'),(select id from lion_fixture where key='open_a'),
  (select id from lion_fixture where key='exhibitor'),case when n=6 then 'cavy' else 'rabbit' end,
  case when n=6 then 'American' else 'Lionhead' end,case when n=4 then 'Unrecognized (COD)' else 'Tortoise' end,
  'Buck','Senior','EXCLUDED'||n,case when n=5 then null else '1' end,n<>2,n=3,n=5,case when n=1 then now() end,'Pending'
from generate_series(1,6) n;
insert into public.entries(show_id,section_id,exhibitor_id,species,breed,variety,sex,class_name,tattoo,placement)
select (select id from lion_fixture where key='show'),id,(select id from lion_fixture where key='exhibitor'),
  'rabbit','Lionhead','Tortoise','Buck','Senior',key,'1'
from lion_fixture where key in ('open_b','youth_a','specialty','disabled');

insert into public.entry_awards(entry_id,award_code)
select e.id,a.code from public.entries e cross join (values ('BOB'),('BIS'),('B4C'),('BEST OF BREED')) a(code)
where e.show_id=(select id from lion_fixture where key='show') and e.tattoo in ('L1','specialty');
insert into public.entry_awards(entry_id,award_code)
select e.id,a.code from public.entries e cross join (values ('BOS'),('BOSB'),('RIS')) a(code)
where e.show_id=(select id from lion_fixture where key='show') and e.tattoo='DOE';
update public.entries set special_awards='Best of Breed'
where show_id=(select id from lion_fixture where key='show') and tattoo='L1';
insert into public.results(show_id,entry_id,award)
select show_id,id,'BOB' from public.entries where show_id=(select id from lion_fixture where key='show') and tattoo='L1';

select lives_ok($$select public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','A')$$,'public dispatcher computes Lionhead rules');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L1' and points_source='CLASS'),72::numeric,'first place uses twelve eligible rabbits in exact class');
select is((select count(*)::integer from public.sweepstakes_entry_results r join public.entries e on e.id=r.entry_id where r.show_id=(select id from lion_fixture where key='show') and e.is_fur),0,'fur entries receive neither class points nor bonuses');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L5' and points_source='CLASS'),12::numeric,'fifth place uses one times class count');
select is((select count(*)::integer from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L6'),0,'standard sixth earns zero');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='DOE' and points_source='CLASS'),6::numeric,'sex defines separate class');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='JUNIOR' and points_source='CLASS'),6::numeric,'age defines separate class');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='REW' and points_source='CLASS'),6::numeric,'variety defines separate class');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L1' and points_source='BOB'),30::numeric,'BOB counts fifteen eligible Lionheads once despite aliases and duplicate sources');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='DOE' and points_source='BOSB'),15::numeric,'BOS counts entire breed, deduplicated across aliases');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L1' and points_source='BIS'),20::numeric,'BIS counts all rabbit breeds within Open A');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='DOE' and points_source='RIS'),10::numeric,'RIS counts all eligible rabbit breeds');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L1' and points_source='B4C'),30::numeric,'B4C counts entire breed');
select is((select count(*)::integer from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo like 'EXCLUDED%'),0,'excluded entries earn no points');
select is((select total_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and show_letter='A'),315::numeric,'exhibitor total adds placements and bonuses');
select lives_ok($$select public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','A')$$,'recalculation succeeds');
select is((select total_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and show_letter='A'),315::numeric,'repeated calculations are stable');

update public.shows set is_national_show=true,national_show_section_id=(select id from lion_fixture where key='open_a') where id=(select id from lion_fixture where key='show');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','A');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L1' and points_source='CLASS'),120::numeric,'national first uses ten times class');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L6' and points_source='CLASS'),60::numeric,'national sixth is included');
select is((select points from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L10' and points_source='CLASS'),12::numeric,'national tenth is included');
select is((select count(*)::integer from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and tattoo='L11'),0,'eleventh earns zero');
select is((select count(*)::integer from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and points_source in ('BIS','RIS','B4C')),0,'nationals have no BIS/RIS/B4C');
select is((select total_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and show_letter='A'),735::numeric,'national exhibitor total includes all ten class positions');

update public.shows set is_arba_convention=true where id=(select id from lion_fixture where key='show');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','A');
select is((select total_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and show_letter='A'),755::numeric,'Convention adds all-breed BIS to national class scale');
select is((select count(*)::integer from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and points_source in ('RIS','B4C')),0,'Convention RIS and B4C are zero');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','YOUTH','A');
select is((select class_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and scope='YOUTH'),6::numeric,'Youth stays separate and respects exact national section selection');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','B');
select is((select class_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and show_letter='B'),6::numeric,'companion regular show keeps standard class scale');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','C');
select is((select count(*)::integer from public.sweepstakes_entry_results where show_id=(select id from lion_fixture where key='show') and show_letter='C' and points_source='BIS'),0,'specialty section receives no BIS');
select is((select total_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and show_letter='C'),10::numeric,'specialty still receives class, BOB and B4C');

-- Legacy national events without a section selection apply to each section.
update public.shows set national_show_section_id=null where id=(select id from lion_fixture where key='show');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','YOUTH','A');
select is((select class_points from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and scope='YOUTH'),10::numeric,'legacy national/convention settings apply within Youth separately');

select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN',null);
select is((select count(*)::integer from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and scope='OPEN'),3,'ALL processes enabled sections separately without an extra aggregate cache');
select is((select count(*)::integer from public.sweepstakes_results where show_id=(select id from lion_fixture where key='show') and show_letter='D'),0,'disabled sections excluded');

create temporary table lion_saved as select md5(string_agg(to_jsonb(r)::text,',' order by r.id)) digest from public.sweepstakes_results r where show_id=(select id from lion_fixture where key='show');
create temporary table lion_entry_saved as select md5(string_agg(to_jsonb(r)::text,',' order by r.id)) digest from public.sweepstakes_entry_results r where show_id=(select id from lion_fixture where key='show');
update public.shows set is_closed=true,is_national_show=false,is_arba_convention=false where id=(select id from lion_fixture where key='show');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','A');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN',null);
select is((select md5(string_agg(to_jsonb(r)::text,',' order by r.id)) from public.sweepstakes_results r where show_id=(select id from lion_fixture where key='show')),(select digest from lion_saved),'completed results remain byte-for-byte unchanged');
update public.shows set is_closed=false,finalized_at=now() where id=(select id from lion_fixture where key='show');
select count(*) from public.calculate_sweepstakes_for_breed((select id from lion_fixture where key='show'),'Lionhead','OPEN','A');
select is((select md5(string_agg(to_jsonb(r)::text,',' order by r.id)) from public.sweepstakes_entry_results r where show_id=(select id from lion_fixture where key='show')),(select digest from lion_entry_saved),'finalized entry breakdowns remain byte-for-byte unchanged');
select ok(not has_function_privilege('anon','public.calculate_lionhead_sweepstakes(uuid,text,text)','execute'),'anonymous users cannot invoke calculator');
select ok(not (select prosecdef from pg_proc where oid='public.calculate_lionhead_sweepstakes(uuid,text,text)'::regprocedure),'calculator preserves caller RLS');
select * from finish();
rollback;
