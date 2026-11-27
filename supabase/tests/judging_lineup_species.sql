begin;
set local search_path=public,extensions;
select no_plan();

create temp table species_fixture(k text primary key,id uuid default gen_random_uuid());
insert into species_fixture(k) values
  ('staff'),('outsider'),('show'),('section'),('workspace'),('rabbit_judge'),('cavy_judge'),
  ('rabbit_entry'),('cavy_entry'),('previously_assigned'),('judged_rabbit'),('legacy');
grant select on species_fixture to authenticated;
create function pg_temp.fixture_id(text) returns uuid language sql as $$select id from species_fixture where k=$1$$;

insert into auth.users(id) select id from species_fixture where k in ('staff','outsider');
insert into public.shows(id,name,created_by,start_date,end_date)
values (pg_temp.fixture_id('show'),'Species assignment fixture',pg_temp.fixture_id('staff'),current_date,current_date);
insert into public.role_assignments(user_id,show_id,role)
values (pg_temp.fixture_id('staff'),pg_temp.fixture_id('show'),'superintendent');
insert into public.show_sections(id,show_id,kind,letter,is_enabled)
values (pg_temp.fixture_id('section'),pg_temp.fixture_id('show'),'open','A',true);
insert into public.superintendent_workspaces(id,name,show_ids)
values(pg_temp.fixture_id('workspace'),'Species fixture',array[pg_temp.fixture_id('show')]);
insert into public.judges(id,name,judge_type) values
  (pg_temp.fixture_id('rabbit_judge'),'Synthetic Rabbit Judge','Rabbit'),
  (pg_temp.fixture_id('cavy_judge'),'Synthetic Cavy Judge','Cavy');
insert into public.judge_assignments(show_id,judge_id,assignment_label)
select pg_temp.fixture_id('show'),id,'All breeds' from species_fixture where k in ('rabbit_judge','cavy_judge');
insert into public.show_judging_assignments(show_id,breed_id,judge_id,is_judge_change,table_number,sort_order)
values
  (pg_temp.fixture_id('show'),'__judge_change__',pg_temp.fixture_id('rabbit_judge'),true,'1',0),
  (pg_temp.fixture_id('show'),'__judge_change__',pg_temp.fixture_id('cavy_judge'),true,'2',0);
insert into public.show_judging_assignments(id,show_id,section_id,breed_id,table_number,sort_order,scope)
values (pg_temp.fixture_id('legacy'),pg_temp.fixture_id('show'),pg_temp.fixture_id('section'),'American','2',1,'open');
insert into public.entries(id,show_id,section_id,species,breed,sex,class_name,judged_by_show_judge_id,result_entered_at)
values
  (pg_temp.fixture_id('rabbit_entry'),pg_temp.fixture_id('show'),pg_temp.fixture_id('section'),'rabbit','American','buck','Senior',null,null),
  (pg_temp.fixture_id('cavy_entry'),pg_temp.fixture_id('show'),pg_temp.fixture_id('section'),'cavy','American','boar','Senior',null,null),
  (pg_temp.fixture_id('previously_assigned'),pg_temp.fixture_id('show'),pg_temp.fixture_id('section'),'rabbit','American','buck','Senior',pg_temp.fixture_id('cavy_judge'),null),
  (pg_temp.fixture_id('judged_rabbit'),pg_temp.fixture_id('show'),pg_temp.fixture_id('section'),'rabbit','American','buck','Senior',pg_temp.fixture_id('rabbit_judge'),now());

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.fixture_id('outsider'))::text,true);
select throws_ok(
  $$select public.add_species_show_judging_breed(pg_temp.fixture_id('show'),pg_temp.fixture_id('section'),'American',null,'1',1,'open',1,null,'rabbit')$$,
  '42501','You do not have permission to manage this show lineup','unrelated accounts cannot add a breed'
);
select is((select count(*)::int from public.get_species_show_judging_lineup(pg_temp.fixture_id('show'))),0,'unrelated accounts cannot read lineup');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.fixture_id('staff'))::text,true);
select is((select a->>'species' from public.get_species_show_judging_lineup(pg_temp.fixture_id('show')) a
  where a->>'id'=pg_temp.fixture_id('legacy')::text),'cavy','legacy shared name resolves to its cavy judge');
select lives_ok($$select public.apply_lineup_to_entries(pg_temp.fixture_id('show'))$$,'single-show sync runs with a legacy row');
reset role;
select is((select judged_by_show_judge_id from public.entries where id=pg_temp.fixture_id('rabbit_entry')),null::uuid,'legacy cavy row never fills a rabbit entry');
select is((select judged_by_show_judge_id from public.entries where id=pg_temp.fixture_id('cavy_entry')),pg_temp.fixture_id('cavy_judge'),'legacy row still fills its cavy entry');

set local role authenticated;
select lives_ok(
  $$select public.add_species_show_judging_breed(pg_temp.fixture_id('show'),pg_temp.fixture_id('section'),'American',null,'1',1,'open',1,null,'rabbit')$$,
  'single-show write retains an explicit rabbit assignment'
);
select lives_ok($$select public.apply_lineup_to_entries(pg_temp.fixture_id('show'))$$,'single-show sync accepts the matching rabbit judge');
select lives_ok(
  $$select public.mutate_workspace_lineup(pg_temp.fixture_id('workspace'),
     public.workspace_lineup_versions(pg_temp.fixture_id('workspace')),'add',
     jsonb_build_object('p_section_id',pg_temp.fixture_id('section'),'p_breed_id','American','p_species','cavy',
       'p_table_number','2','p_sort_order',2,'p_scope','open','p_entry_count_actual',1))$$,
  'workspace write retains explicit species and syncs safely'
);
reset role;
select is((select count(*)::int from public.show_judging_assignments
  where show_id=pg_temp.fixture_id('show') and breed_id='American' and species in ('rabbit','cavy')),2,
  'explicit rabbit and cavy rows coexist in one section'
);
select is((select judged_by_show_judge_id from public.entries where id=pg_temp.fixture_id('rabbit_entry')),pg_temp.fixture_id('rabbit_judge'),'rabbit receives the rabbit judge');
select is((select judged_by_show_judge_id from public.entries where id=pg_temp.fixture_id('cavy_entry')),pg_temp.fixture_id('cavy_judge'),'cavy keeps its cavy judge');
select is((select judged_by_show_judge_id from public.entries where id=pg_temp.fixture_id('previously_assigned')),pg_temp.fixture_id('cavy_judge'),'existing judge choice stays intact');
select is((select judged_by_show_judge_id from public.entries where id=pg_temp.fixture_id('judged_rabbit')),pg_temp.fixture_id('rabbit_judge'),'recorded result keeps its judge');
update public.show_judging_assignments set table_number='2'
where show_id=pg_temp.fixture_id('show') and species='rabbit';
select is((select judge_id from private.workspace_lineup_entry_judges(array[pg_temp.fixture_id('show')])
  where entry_id=pg_temp.fixture_id('rabbit_entry')),null::uuid,'a rabbit row under a cavy-only judge cannot route a rabbit entry');
update public.judges set judge_type='Dual' where id=pg_temp.fixture_id('cavy_judge');
select is((select species from private.lineup_breed_assignments(array[pg_temp.fixture_id('show')])
  where assignment_id=pg_temp.fixture_id('legacy')),null::text,'a mixed legacy row with a dual judge stays unresolved');
select * from finish();
rollback;
