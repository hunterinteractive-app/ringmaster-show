begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
create temporary table dashboard_fixture(key text primary key, id uuid default gen_random_uuid());
insert into dashboard_fixture(key) values ('show'),('active'),('empty'),('disabled');
insert into public.shows(id,name,owner_user_id,created_by,start_date,end_date)
select id,'Dashboard counts test', (select owner_user_id from public.shows where owner_user_id is not null limit 1),
 (select owner_user_id from public.shows where owner_user_id is not null limit 1),current_date,current_date
from dashboard_fixture where key='show';
insert into public.show_sections(id,show_id,kind,letter,judging_date,is_enabled)
select id,(select id from dashboard_fixture where key='show'),'open',
 case key when 'active' then 'A' when 'empty' then 'B' else 'C' end,current_date,key<>'disabled'
from dashboard_fixture where key<>'show';
insert into public.entries(show_id,section_id,species,breed,variety,sex,class_name,status)
select (select id from dashboard_fixture where key='show'),(select id from dashboard_fixture where key='active'),
 'rabbit','Rex','Black','Doe','Senior','submitted' from generate_series(1,1501);
insert into public.entries(show_id,section_id,species,breed,variety,sex,class_name,status,scratched_at)
select (select id from dashboard_fixture where key='show'),(select id from dashboard_fixture where key='active'),
 'rabbit','Rex','Black','Doe','Senior',status,scratched_at
from (values ('scratched',null::timestamptz),('submitted',now())) v(status,scratched_at);
select is(jsonb_array_length(public.secretary_show_entry_counts((select id from dashboard_fixture where key='show'))),2,'only enabled sections returned');
select is((public.secretary_show_entry_counts((select id from dashboard_fixture where key='show'))->0->>'entry_count')::int,1501,'all entries beyond 1000 counted and both scratch forms excluded');
select is((public.secretary_show_entry_counts((select id from dashboard_fixture where key='show'))->1->>'entry_count')::int,0,'empty section retained');
select is(public.secretary_show_entry_counts(gen_random_uuid()),'[]'::jsonb,'unknown show empty');
select ok(not (select prosecdef from pg_proc where oid='public.secretary_show_entry_counts(uuid)'::regprocedure),'count function preserves caller RLS');
select ok(not has_function_privilege('anon','public.secretary_show_entry_counts(uuid)','execute'),'anonymous calls denied');
-- No user identity has access to these entries via entry RLS.
grant select on dashboard_fixture to authenticated;
set local role authenticated;
select is((public.secretary_show_entry_counts((select id from dashboard_fixture where key='show'))->0->>'entry_count')::int,0,'caller cannot count inaccessible entries');
reset role;
select * from finish();
rollback;
