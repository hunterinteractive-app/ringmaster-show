-- Synthetic fixtures only. All writes roll back, including feature access.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temp table cp_ids(key text primary key,id uuid default gen_random_uuid());
insert into cp_ids(key) values ('owner'),('other'),('show'),('other_show'),('open'),('youth'),('foreign_section');
grant select on cp_ids to authenticated;
insert into auth.users(id) select id from cp_ids where key in ('owner','other');
insert into public.secretary_feature_access(user_id,feature_key)
select id,'best_of_best_opposite' from cp_ids where key='owner';
insert into public.shows(id,name,owner_user_id,created_by,start_date,end_date)
select s.id,'Synthetic custom premium test',u.id,u.id,'2027-03-10','2027-03-10'
from cp_ids s join cp_ids u on u.key=case when s.key='show' then 'owner' else 'other' end
where s.key in ('show','other_show');
insert into public.show_sections(id,show_id,kind,letter,judging_date)
select s.id,(select id from cp_ids where key=case when s.key='foreign_section' then 'other_show' else 'show' end),
case when s.key='youth' then 'youth' else 'open' end,'A','2027-03-10' from cp_ids s where key in ('open','youth','foreign_section');
create temp table cp_presets(kind text, payload jsonb);
insert into cp_presets values ('open','[{"applies_to_species": "rabbit", "min_shown": 2, "max_shown": 2, "placement": 1, "amount_cents": 200}, {"applies_to_species": "rabbit", "min_shown": 3, "max_shown": 4, "placement": 1, "amount_cents": 400}, {"applies_to_species": "rabbit", "min_shown": 3, "max_shown": 4, "placement": 2, "amount_cents": 200}, {"applies_to_species": "rabbit", "min_shown": 5, "max_shown": 6, "placement": 1, "amount_cents": 600}, {"applies_to_species": "rabbit", "min_shown": 5, "max_shown": 6, "placement": 2, "amount_cents": 400}, {"applies_to_species": "rabbit", "min_shown": 5, "max_shown": 6, "placement": 3, "amount_cents": 200}, {"applies_to_species": "rabbit", "min_shown": 7, "max_shown": 8, "placement": 1, "amount_cents": 800}, {"applies_to_species": "rabbit", "min_shown": 7, "max_shown": 8, "placement": 2, "amount_cents": 600}, {"applies_to_species": "rabbit", "min_shown": 7, "max_shown": 8, "placement": 3, "amount_cents": 400}, {"applies_to_species": "rabbit", "min_shown": 7, "max_shown": 8, "placement": 4, "amount_cents": 200}, {"applies_to_species": "rabbit", "min_shown": 9, "max_shown": null, "placement": 1, "amount_cents": 1000}, {"applies_to_species": "rabbit", "min_shown": 9, "max_shown": null, "placement": 2, "amount_cents": 800}, {"applies_to_species": "rabbit", "min_shown": 9, "max_shown": null, "placement": 3, "amount_cents": 600}, {"applies_to_species": "rabbit", "min_shown": 9, "max_shown": null, "placement": 4, "amount_cents": 400}, {"applies_to_species": "rabbit", "min_shown": 9, "max_shown": null, "placement": 5, "amount_cents": 200}, {"applies_to_species": "cavy", "min_shown": 2, "max_shown": 2, "placement": 1, "amount_cents": 200}, {"applies_to_species": "cavy", "min_shown": 3, "max_shown": 4, "placement": 1, "amount_cents": 400}, {"applies_to_species": "cavy", "min_shown": 3, "max_shown": 4, "placement": 2, "amount_cents": 200}, {"applies_to_species": "cavy", "min_shown": 5, "max_shown": 6, "placement": 1, "amount_cents": 600}, {"applies_to_species": "cavy", "min_shown": 5, "max_shown": 6, "placement": 2, "amount_cents": 400}, {"applies_to_species": "cavy", "min_shown": 5, "max_shown": 6, "placement": 3, "amount_cents": 200}, {"applies_to_species": "cavy", "min_shown": 7, "max_shown": 8, "placement": 1, "amount_cents": 800}, {"applies_to_species": "cavy", "min_shown": 7, "max_shown": 8, "placement": 2, "amount_cents": 600}, {"applies_to_species": "cavy", "min_shown": 7, "max_shown": 8, "placement": 3, "amount_cents": 400}, {"applies_to_species": "cavy", "min_shown": 7, "max_shown": 8, "placement": 4, "amount_cents": 200}, {"applies_to_species": "cavy", "min_shown": 9, "max_shown": null, "placement": 1, "amount_cents": 1000}, {"applies_to_species": "cavy", "min_shown": 9, "max_shown": null, "placement": 2, "amount_cents": 800}, {"applies_to_species": "cavy", "min_shown": 9, "max_shown": null, "placement": 3, "amount_cents": 600}, {"applies_to_species": "cavy", "min_shown": 9, "max_shown": null, "placement": 4, "amount_cents": 400}, {"applies_to_species": "cavy", "min_shown": 9, "max_shown": null, "placement": 5, "amount_cents": 200}]');
insert into cp_presets values ('youth','[{"applies_to_species": "rabbit", "min_shown": 1, "max_shown": 3, "placement": 1, "amount_cents": 1000}, {"applies_to_species": "rabbit", "min_shown": 4, "max_shown": 5, "placement": 1, "amount_cents": 1200}, {"applies_to_species": "rabbit", "min_shown": 4, "max_shown": 5, "placement": 2, "amount_cents": 1100}, {"applies_to_species": "rabbit", "min_shown": 4, "max_shown": 5, "placement": 3, "amount_cents": 1000}, {"applies_to_species": "rabbit", "min_shown": 6, "max_shown": 7, "placement": 1, "amount_cents": 1400}, {"applies_to_species": "rabbit", "min_shown": 6, "max_shown": 7, "placement": 2, "amount_cents": 1300}, {"applies_to_species": "rabbit", "min_shown": 6, "max_shown": 7, "placement": 3, "amount_cents": 1200}, {"applies_to_species": "rabbit", "min_shown": 6, "max_shown": 7, "placement": 4, "amount_cents": 1100}, {"applies_to_species": "rabbit", "min_shown": 8, "max_shown": 9, "placement": 1, "amount_cents": 1500}, {"applies_to_species": "rabbit", "min_shown": 8, "max_shown": 9, "placement": 2, "amount_cents": 1400}, {"applies_to_species": "rabbit", "min_shown": 8, "max_shown": 9, "placement": 3, "amount_cents": 1300}, {"applies_to_species": "rabbit", "min_shown": 8, "max_shown": 9, "placement": 4, "amount_cents": 1200}, {"applies_to_species": "rabbit", "min_shown": 8, "max_shown": 9, "placement": 5, "amount_cents": 1100}, {"applies_to_species": "rabbit", "min_shown": 10, "max_shown": 14, "placement": 1, "amount_cents": 1800}, {"applies_to_species": "rabbit", "min_shown": 10, "max_shown": 14, "placement": 2, "amount_cents": 1600}, {"applies_to_species": "rabbit", "min_shown": 10, "max_shown": 14, "placement": 3, "amount_cents": 1500}, {"applies_to_species": "rabbit", "min_shown": 10, "max_shown": 14, "placement": 4, "amount_cents": 1400}, {"applies_to_species": "rabbit", "min_shown": 10, "max_shown": 14, "placement": 5, "amount_cents": 1300}, {"applies_to_species": "rabbit", "min_shown": 15, "max_shown": null, "placement": 1, "amount_cents": 2300}, {"applies_to_species": "rabbit", "min_shown": 15, "max_shown": null, "placement": 2, "amount_cents": 2100}, {"applies_to_species": "rabbit", "min_shown": 15, "max_shown": null, "placement": 3, "amount_cents": 2000}, {"applies_to_species": "rabbit", "min_shown": 15, "max_shown": null, "placement": 4, "amount_cents": 1900}, {"applies_to_species": "rabbit", "min_shown": 15, "max_shown": null, "placement": 5, "amount_cents": 1800}, {"applies_to_species": "cavy", "min_shown": 1, "max_shown": 3, "placement": 1, "amount_cents": 1000}, {"applies_to_species": "cavy", "min_shown": 4, "max_shown": 5, "placement": 1, "amount_cents": 1200}, {"applies_to_species": "cavy", "min_shown": 4, "max_shown": 5, "placement": 2, "amount_cents": 1100}, {"applies_to_species": "cavy", "min_shown": 6, "max_shown": 7, "placement": 1, "amount_cents": 1400}, {"applies_to_species": "cavy", "min_shown": 6, "max_shown": 7, "placement": 2, "amount_cents": 1300}, {"applies_to_species": "cavy", "min_shown": 6, "max_shown": 7, "placement": 3, "amount_cents": 1200}, {"applies_to_species": "cavy", "min_shown": 8, "max_shown": 9, "placement": 1, "amount_cents": 1500}, {"applies_to_species": "cavy", "min_shown": 8, "max_shown": 9, "placement": 2, "amount_cents": 1400}, {"applies_to_species": "cavy", "min_shown": 8, "max_shown": 9, "placement": 3, "amount_cents": 1300}, {"applies_to_species": "cavy", "min_shown": 8, "max_shown": 9, "placement": 4, "amount_cents": 1200}, {"applies_to_species": "cavy", "min_shown": 10, "max_shown": null, "placement": 1, "amount_cents": 1800}, {"applies_to_species": "cavy", "min_shown": 10, "max_shown": null, "placement": 2, "amount_cents": 1600}, {"applies_to_species": "cavy", "min_shown": 10, "max_shown": null, "placement": 3, "amount_cents": 1500}, {"applies_to_species": "cavy", "min_shown": 10, "max_shown": null, "placement": 4, "amount_cents": 1400}, {"applies_to_species": "cavy", "min_shown": 10, "max_shown": null, "placement": 5, "amount_cents": 1300}]');
grant select on cp_presets to authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from cp_ids where key='owner'),'role','authenticated')::text,true);
set local role authenticated;
select lives_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),(select id from cp_ids where key='open'),(select payload from cp_presets where kind='open'))$$,'save Open Rabbit and Cavy brackets together');
select lives_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),(select id from cp_ids where key='youth'),(select payload from cp_presets where kind='youth'))$$,'save different Youth Rabbit and Cavy brackets');
select throws_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),(select id from cp_ids where key='foreign_section'),'[]')$$,'22023','Section does not belong to show.','cannot change another show section');
select throws_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),(select id from cp_ids where key='open'),
 '[{"applies_to_species":"rabbit","min_shown":2,"max_shown":4,"placement":1,"amount_cents":200},{"applies_to_species":"rabbit","min_shown":4,"max_shown":null,"placement":2,"amount_cents":200}]')$$,
 '22023','Class-size ranges overlap for the same species.','inclusive overlap is rejected even for different placements');
select throws_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),(select id from cp_ids where key='open'),
 '[{"applies_to_species":"rabbit","min_shown":9,"max_shown":null,"placement":1,"amount_cents":200},{"applies_to_species":"rabbit","min_shown":9,"max_shown":null,"placement":1,"amount_cents":200}]')$$,
 '22023','Duplicate premium placement in a class-size range.','duplicate open-ended placement is rejected');
select throws_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),(select id from cp_ids where key='open'),
 '[{"applies_to_species":"rabbit","min_shown":2,"max_shown":2,"placement":3,"amount_cents":200}]')$$,
 '22023','Invalid class-size range, placement, or premium amount.','impossible placement is rejected');
select throws_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),(select id from cp_ids where key='open'),
 '[{"applies_to_species":"rabbit","min_shown":2,"max_shown":2,"placement":1,"amount_cents":-200}]')$$,
 '22023','Invalid class-size range, placement, or premium amount.','negative amount is rejected');
reset role;
select is((select count(*)::int from public.show_payback_schedule_rows r join public.show_payback_schedules s on s.id=r.schedule_id where s.show_id=(select id from cp_ids where key='show') and s.section_id=(select id from cp_ids where key='open')),30,'rejected saves preserve all original Open payouts');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from cp_ids where key='other'),'role','authenticated')::text,true);
set local role authenticated;
select throws_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='other_show'),null,'[]')$$,'42501','Custom premium ranges are only available for eligible shows.','ordinary show owner cannot use custom RPC');
select throws_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),null,'[]')$$,'42501','Custom premium ranges are only available for eligible shows.','unassigned user cannot edit eligible show');
reset role;
select ok(not has_function_privilege('anon','public.save_show_custom_payback_schedule(uuid,uuid,jsonb)','execute'),'anonymous users cannot save');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from cp_ids where key='owner'),'role','authenticated')::text,true);
set local role authenticated;
select lives_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),null,'[]')$$,'create default schedule');
select lives_ok($$select public.save_show_custom_payback_schedule((select id from cp_ids where key='show'),null,'[]')$$,'save default a second time');
reset role;
select is((select count(*)::int from public.show_payback_schedules where show_id=(select id from cp_ids where key='show') and section_id is null),1,'default save does not duplicate schedules');
-- One independent class per class size and species, places 1..size.
insert into public.entries(id,show_id,section_id,species,breed,variety,class_name,sex,placement,result_status)
select gen_random_uuid(),(select id from cp_ids where key='show'),s.id,sp.species,
 sp.species||' synthetic '||n,'Standard','Senior','Doe',p::text,'Shown'
from cp_ids s cross join (values ('rabbit'),('cavy')) sp(species)
cross join generate_series(1,30) n cross join lateral generate_series(1,n) p where s.key in ('open','youth');
create temp table cp_actual as select * from public.report_payback_rows((select id from cp_ids where key='show'),null);
create temp table cp_expected(kind text,species text,n int,placement int,cents int);
insert into cp_expected
select k.kind,sp.species,n,p,amounts[p]*100
from (values ('open'),('youth')) k(kind)
cross join (values ('rabbit'),('cavy')) sp(species)
cross join generate_series(1,30) n
cross join lateral (select case
 when k.kind='open' then case when n=1 then array[]::int[] when n=2 then array[2]
   when n<=4 then array[4,2] when n<=6 then array[6,4,2] when n<=8 then array[8,6,4,2] else array[10,8,6,4,2] end
 when sp.species='rabbit' then case when n<=3 then array[10] when n<=5 then array[12,11,10]
   when n<=7 then array[14,13,12,11] when n<=9 then array[15,14,13,12,11]
   when n<=14 then array[18,16,15,14,13] else array[23,21,20,19,18] end
 else case when n<=3 then array[10] when n<=5 then array[12,11] when n<=7 then array[14,13,12]
   when n<=9 then array[15,14,13,12] else array[18,16,15,14,13] end end amounts) a
cross join lateral generate_subscripts(amounts,1) p;
select results_eq(
 $$select lower(section_kind),split_part(breed_name,' ',1),eligible_count,placement,amount_cents from cp_actual where source_type='class_placement' order by 1,2,3,4$$,
 $$select kind,species,n,placement,cents from cp_expected order by 1,2,3,4$$,
 'real payout report matches every class size 1–30 and paying place for all four tables with no duplicates');
select * from finish();
rollback;
