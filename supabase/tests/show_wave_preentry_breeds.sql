begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table prewave(key text primary key,id uuid default gen_random_uuid());
insert into prewave(key) values('user'),('show'),('other_show'),('section'),('rabbit'),('cavy'),('disabled'),('inactive'),('local'),('foreign'),('wave'),('exhibitor');
grant select on prewave to authenticated;
insert into auth.users(id) select id from prewave where key='user';
insert into public.secretary_feature_access(feature_key,user_id) select 'best_of_best_opposite',id from prewave where key='user';
insert into public.shows(id,name,created_by,owner_user_id,timezone,start_date,end_date)
select id,'Pre-entry wave test',(select id from prewave where key='user'),(select id from prewave where key='user'),'America/Chicago',current_date+365,current_date+367 from prewave where key in ('show','other_show');
insert into public.show_sections(id,show_id,kind,letter,is_enabled)
select id,(select id from prewave where key='show'),'open','A',true from prewave where key='section';
insert into public.breeds(id,name,species,is_active,local_show_id)
select id,case when key in ('rabbit','cavy') then 'Wave Preentry Shared' else 'Wave Preentry '||key end,
case when key='cavy' then 'cavy' else 'rabbit' end,key<>'inactive',
case when key='local' then (select id from prewave where key='show') when key='foreign' then (select id from prewave where key='other_show') end
from prewave where key in ('rabbit','cavy','disabled','inactive','local','foreign');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from prewave where key='user'),'role','authenticated')::text,true);
select ok(exists(select 1 from jsonb_array_elements(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds') b where b->>'breed_name'='Wave Preentry Shared'),'unconfigured show offers active catalog before entries');
insert into public.show_breeds(show_id,breed_id,is_enabled)
select (select id from prewave where key='show'),id,key<>'disabled' from prewave where key in ('rabbit','cavy','disabled','inactive','local','foreign');
select is(jsonb_array_length(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds'),3,'only enabled active breeds and this show local breed are offered');
select is((select count(*)::int from jsonb_array_elements(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds') b where b->>'breed_name'='Wave Preentry Shared'),2,'same-name rabbit and cavy stay separate');
select ok(not exists(select 1 from jsonb_array_elements(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds') b where (b->>'has_entries')::boolean),'catalog choices are not submitted entries');
update public.show_sections set breed_scope='limited',allowed_breed_ids=array[(select id from prewave where key='rabbit')] where id=(select id from prewave where key='section');
select is(jsonb_array_length(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds'),1,'limited section only offers allowed rabbit breed');
update public.show_sections set is_enabled=false where id=(select id from prewave where key='section');
select is(jsonb_array_length(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds'),0,'disabled sections do not offer catalog breeds');
update public.show_sections set is_enabled=true,breed_scope='all' where id=(select id from prewave where key='section');
-- Older local fixtures omit these production columns; DDL is rolled back too.
alter table public.shows add column if not exists is_single_breed_show boolean default false;
alter table public.shows add column if not exists single_breed_id uuid;
update public.shows set is_single_breed_show=true,single_breed_id=(select id from prewave where key='rabbit') where id=(select id from prewave where key='show');
select is(jsonb_array_length(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds'),1,'single-breed show offers only its designated breed');
update public.shows set is_single_breed_show=false,single_breed_id=null where id=(select id from prewave where key='show');

create temporary table prewave_payload as select jsonb_build_array(jsonb_build_object(
'id',(select id from prewave where key='wave'),'wave_number',1,
'checkin_start_local',(current_date+365)::text||'T08:00:00','checkin_end_local',(current_date+365)::text||'T10:00:00',
'show_date',current_date+365,'checkout_date',current_date+366,'email_lead_hours',24)) waves,
jsonb_build_array(jsonb_build_object('species','rabbit','breed_name','Wave Preentry Shared','wave_id',(select id from prewave where key='wave'))) breeds;
grant select on prewave_payload to authenticated;
set local role authenticated;
select lives_ok($$select public.save_show_wave_schedule((select id from prewave where key='show'),true,waves,breeds) from prewave_payload$$,'enabled wave can be saved before entries, leaving unused catalog choices unassigned');
select is((select b->>'wave_id' from jsonb_array_elements(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds') b where b->>'breed_name'='Wave Preentry Shared' and b->>'species'='rabbit'),(select id::text from prewave where key='wave'),'pre-entry assignment survives reload');
reset role;
insert into public.exhibitors(id,first_name,last_name,exhibitor_number,email) select id,'Prewave','Fixture',991103,'prewave@example.invalid' from prewave where key='exhibitor';
insert into public.entries(show_id,section_id,exhibitor_id,species,breed,sex,class_name,tattoo)
select (select id from prewave where key='show'),(select id from prewave where key='section'),(select id from prewave where key='exhibitor'),'rabbit','Wave Preentry Shared','Buck','Senior','PREWAVE';
select is((select count(*)::int from jsonb_array_elements(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds') b where b->>'breed_name'='Wave Preentry Shared' and b->>'species'='rabbit' and (b->>'has_entries')::boolean and b->>'wave_id'=(select id::text from prewave where key='wave')),1,'new entry uses the existing assignment without duplicating the catalog breed');
select is((select count(*)::int from public.report_wave_checkin_entries((select id from prewave where key='show'),(select id from prewave where key='wave'))),1,'later entry is included in its preassigned wave report');
delete from public.entries where show_id=(select id from prewave where key='show');
update public.show_breeds set is_enabled=false where show_id=(select id from prewave where key='show') and breed_id=(select id from prewave where key='rabbit');
select ok(exists(select 1 from jsonb_array_elements(public.get_show_wave_schedule((select id from prewave where key='show'))->'breeds') b where b->>'breed_name'='Wave Preentry Shared' and b->>'species'='rabbit' and not (b->>'has_entries')::boolean and b->>'wave_id' is not null),'saved assignment survives removed entries and disabled catalog');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select public.get_show_wave_schedule((select id from prewave where key='show'))$$,'42501','You do not have permission to view this show schedule.','pre-entry catalog remains protected by show permissions');
select * from finish();
rollback;
