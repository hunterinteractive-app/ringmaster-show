begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table sweep_fixture(key text primary key,id uuid default gen_random_uuid());
insert into sweep_fixture(key) values ('owner'),('show'),('exhibitor'),('open_a'),('open_b'),('youth_a'),('youth_c');
insert into auth.users(id) select id from sweep_fixture where key='owner';
insert into public.shows(id,name,created_by,owner_user_id,start_date,end_date)
select (select id from sweep_fixture where key='show'),'Mixed species preparation test',id,id,current_date,current_date
from sweep_fixture where key='owner';
insert into public.exhibitors(id,first_name,last_name,email)
select id,'Sweepstakes','Fixture','sweepstakes@example.test' from sweep_fixture where key='exhibitor';
insert into public.show_sections(id,show_id,kind,letter,judging_date,is_enabled)
select id,(select id from sweep_fixture where key='show'),
 case when key like 'open%' then 'open' else 'youth' end,
 case when key='open_b' then 'B' when key='youth_c' then 'C' else 'A' end,current_date,true
from sweep_fixture where key in ('open_a','open_b','youth_a','youth_c');
insert into public.entries(show_id,section_id,exhibitor_id,species,breed,variety,sex,class_name,tattoo,placement,is_shown,result_status,judged_by_show_judge_id)
select (select id from sweep_fixture where key='show'),s.id,
 (select id from sweep_fixture where key='exhibitor'),b.species,b.breed,'Black',
 case when b.species='cavy' then 'Boar' else 'Buck' end,'Senior',s.key||'-'||b.breed,'1',true,'Shown',gen_random_uuid()
from sweep_fixture s cross join (values ('cavy','Abyssinian'),('cavy','Peruvian'),('cavy','Silkie'),('rabbit','Lionhead')) b(species,breed)
where s.key in ('open_a','open_b','youth_a','youth_c') and (s.key<>'youth_c' or b.species='rabbit');
insert into public.entry_awards(show_id,entry_id,award_code)
select show_id,id,case when species='cavy' then 'BSB' else 'BOB' end
from public.entries where show_id=(select id from sweep_fixture where key='show');

create temporary table cavy_calls(scope text,letter text);
do $$ begin
 execute replace(pg_get_functiondef('public.calculate_cavy_sweepstakes_for_section(uuid,text,text)'::regprocedure),
   'public.calculate_cavy_sweepstakes_for_section(', 'pg_temp.cavy_original(');
end $$;
create or replace function public.calculate_cavy_sweepstakes_for_section(p_show_id uuid,p_scope text,p_show_letter text)
returns integer language plpgsql set search_path='' as $$ begin
 insert into pg_temp.cavy_calls values(p_scope,p_show_letter);
 return pg_temp.cavy_original(p_show_id,p_scope,p_show_letter);
end $$;

create function pg_temp.point_snapshot(p_show_id uuid) returns jsonb language sql as $$
 select jsonb_build_object(
 'totals',(select jsonb_agg(j order by j::text) from
   (select to_jsonb(r)-'id'-'created_at'-'updated_at' j from public.sweepstakes_results r where show_id=p_show_id) x),
 'entries',(select jsonb_agg(j order by j::text) from
   (select to_jsonb(r)-'id' j from public.sweepstakes_entry_results r where show_id=p_show_id) x));
$$;
create temporary table sweep_comparisons(label text,before_points jsonb,after_points jsonb,old_calls integer,new_calls integer);
do $$ declare s record; expected jsonb; old_count integer; v_show uuid := (select id from sweep_fixture where key='show'); begin
 for s in select * from (values ('OPEN','A'),('OPEN','B'),('YOUTH','A'),('YOUTH','C'),('OPEN',null::text)) x(scope,letter) loop
  delete from public.sweepstakes_entry_results where show_id=v_show;
  delete from public.sweepstakes_results where show_id=v_show;
  truncate cavy_calls;
  perform pg_temp.sweepstakes_before(v_show,s.scope,s.letter);
  expected := pg_temp.point_snapshot(v_show);
  select count(*) into old_count from cavy_calls;
  delete from public.sweepstakes_entry_results where show_id=v_show;
  delete from public.sweepstakes_results where show_id=v_show;
  truncate cavy_calls;
  perform public.calculate_sweepstakes_for_show(v_show,s.scope,s.letter);
  insert into sweep_comparisons values(s.scope||coalesce(s.letter,'ALL'),expected,pg_temp.point_snapshot(v_show),old_count,(select count(*) from cavy_calls));
 end loop;
end $$;
select is(after_points,before_points,label||': every entry and exhibitor point total is unchanged') from sweep_comparisons;
select is(new_calls,case when label='OPENALL' then 2 when label='YOUTHC' then 0 else 1 end,label||': at most one cavy calculation per section') from sweep_comparisons;
select ok(old_calls>new_calls,label||': fixture exercises repeated cavy work') from sweep_comparisons where label<>'YOUTHC';
select is((select count(*)::integer from jsonb_array_elements(after_points->'entries') r
 where r->>'points_source'='BSB' and (r->>'points')::numeric>0),
 case when label='OPENALL' then 6 else 3 end,label||': all cavy breed winners receive points')
from sweep_comparisons where new_calls>0;
select ok(exists(select 1 from jsonb_array_elements(after_points->'entries') r where r->>'breed_name'='Lionhead' and (r->>'points')::numeric>0),label||': comparison includes rabbit points') from sweep_comparisons;
select is((select proacl::text from pg_proc where oid='public.calculate_sweepstakes_for_show(uuid,text,text)'::regprocedure),
 (select acl from sweep_original_acl),'dispatcher execute privileges are unchanged');
select ok(not (select prosecdef from pg_proc where oid='public.calculate_sweepstakes_for_show(uuid,text,text)'::regprocedure),'dispatcher remains SECURITY INVOKER');
select * from finish();
rollback;
