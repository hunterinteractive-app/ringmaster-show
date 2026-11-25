begin;
set local search_path=public,extensions;
select no_plan();

create temporary table fixture (key text primary key,id uuid default gen_random_uuid());
insert into fixture(key) select unnest(array[
  'staff','owner','stranger','show','A','B','person','family','outside',
  'old_cart','draft','old_animal','new_animal','old_item','old_entry','draft_item','balance'
]);
create function pg_temp.id(text) returns uuid language sql as $$select id from fixture where key=$1$$;
create function pg_temp.as_user(text) returns text language sql as $$
  select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.id($1))::text,true)
$$;
create function pg_temp.review() returns jsonb language sql as $$select get_entry_cart_review(pg_temp.id('draft'))$$;
create function pg_temp.due() returns integer language sql as $$
  select balance_due_cents from show_exhibitor_balances
  where show_id=pg_temp.id('show') and exhibitor_id=pg_temp.id('person') and source='entries'
$$;

insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
  select id,'authenticated','authenticated',id||'@example.invalid','{}','{}' from fixture
  where key in ('staff','owner','stranger');
insert into shows(id,created_by,name,start_date,end_date,entry_close_at,payment_timing_mode,is_test)
values(pg_temp.id('show'),pg_temp.id('staff'),'Safeguard fixture',current_date+2,current_date+2,
  now()+interval '1 day','pay_at_show_only',true);
insert into exhibitors(id,display_name,email,owner_user_id) values
  (pg_temp.id('person'),'Initial exhibitor','initial@example.invalid',pg_temp.id('owner')),
  (pg_temp.id('family'),'Family exhibitor','family@example.invalid',pg_temp.id('owner')),
  (pg_temp.id('outside'),'Other account','other@example.invalid',pg_temp.id('stranger'));
insert into show_sections(id,show_id,kind,letter,display_name,is_enabled)
  select id,pg_temp.id('show'),'open',key,'Open '||key,true from fixture where key in ('A','B');
insert into show_fee_settings(show_id,currency) values(pg_temp.id('show'),'usd');
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee,fee_per_show)
  select id,5,3,0 from fixture where key in ('A','B')
  on conflict(section_id) do update set fee_per_entry=5,fur_fee=3,fee_per_show=0;
insert into animals(id,owner_user_id,species,tattoo,breed,variety,sex,deleted_at) values
  (pg_temp.id('old_animal'),pg_temp.id('owner'),'rabbit','TAG1','Havana','Black','Buck',now()),
  (pg_temp.id('new_animal'),pg_temp.id('owner'),'rabbit','tag 1','Havana','Black','Buck',null);
insert into entry_carts(id,user_id,show_id,status,payment_status,selected_payment_timing) values
  (pg_temp.id('draft'),pg_temp.id('owner'),pg_temp.id('show'),'active','unpaid',null),
  (pg_temp.id('old_cart'),pg_temp.id('owner'),pg_temp.id('show'),'submitted','unpaid','at_show');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,animal_id,species,tattoo,breed,variety,sex,class_name,is_fur) values
  (pg_temp.id('old_item'),pg_temp.id('old_cart'),pg_temp.id('A'),pg_temp.id('person'),
   pg_temp.id('old_animal'),'rabbit','TAG1','Havana','Black','Buck','Senior',false),
  (pg_temp.id('draft_item'),pg_temp.id('draft'),pg_temp.id('A'),pg_temp.id('family'),
   pg_temp.id('new_animal'),'rabbit','tag 1','Havana','Black','buck','Senior',false);
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,currency,entry_count,fur_count,
  entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,subtotal_before_discount_cents,
  discount_cents,calculated_total_cents,paid_online_cents,paid_manual_cents,refunded_cents,balance_due_cents,
  payment_status,section_breakdown)
values(pg_temp.id('balance'),pg_temp.id('show'),pg_temp.id('person'),pg_temp.id('old_cart'),'cart','usd',1,0,
  500,0,0,1*500,1,499,0,0,0,499,'unpaid',jsonb_build_array(jsonb_build_object(
    'section_id',pg_temp.id('A'),'entry_count',1,'fur_count',0,
    'entries_subtotal_cents',500,'fur_subtotal_cents',0,'show_fee_cents',0)));
insert into entries(id,show_id,section_id,exhibitor_id,exhibitor_user_id,source_cart_id,source_cart_item_id,
  animal_id,species,tattoo,breed,variety,sex,class_name,status,payment_status,is_fur)
values(pg_temp.id('old_entry'),pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('person'),pg_temp.id('owner'),
  pg_temp.id('old_cart'),pg_temp.id('old_item'),pg_temp.id('old_animal'),'rabbit','TAG1','Havana','Black','Buck','Senior',
  'submitted','unpaid',false);
insert into entries(show_id,section_id,exhibitor_id,exhibitor_user_id,species,tattoo,breed,variety,sex,class_name,status)
values(pg_temp.id('show'),pg_temp.id('A'),pg_temp.id('outside'),pg_temp.id('stranger'),'rabbit','TAG1','Havana','Black','Buck','Senior','entered');


insert into breeds(name,species,class_system,is_active) select 'Havana','rabbit','four',true where not exists(select 1 from breeds where name='Havana' and species='rabbit');
update shows set is_published=true,is_locked=false where id=pg_temp.id('show');
grant select on fixture to authenticated;
select pg_temp.as_user('owner');
set local role authenticated;
select lives_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"tag 1"}','{"tattoo":"FIXED","class_name":"Junior","variety":"Chocolate"}'),'owner can correct a draft');
select is((select tattoo from entry_cart_items where id=pg_temp.id('draft_item')),'FIXED','saved tattoo');
select is((select tattoo from animals where id=pg_temp.id('new_animal')),'tag 1','saved animal unchanged');
select is((select tattoo from entries where id=pg_temp.id('old_entry')),'TAG1','submitted result unchanged');
select is(jsonb_array_length(pg_temp.review()->'matches'),0,'duplicate review recalculated after correction');
reset role;
select is((select balance_due_cents from show_exhibitor_balances where coalesce(entry_cart_id,cart_id)=pg_temp.id('draft')),500,'cart is repriced');
set local role authenticated;
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"tag 1"}','{"tattoo":"WRONG"}'),'P0001','This entry changed. Refresh your cart and try again.','stale update rejected');
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"FIXED"}','{"animal_id":null}'),'P0001','Unsupported entry change','cannot change identity');
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"FIXED"}','{"class_name":"Intermediate"}'),'P0001','Choose a valid class for this breed.','four class breed rejects intermediate');
select pg_temp.as_user('stranger');
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"FIXED"}','{"tattoo":"STOLEN"}'),'42501','Cart not found','unrelated account denied');
reset role;
select pg_temp.as_user('owner');
savepoint locked;
update entry_carts set payment_status='pending' where id=pg_temp.id('draft');
set local role authenticated;
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"FIXED"}','{"tattoo":"WRONG"}'),'P0001','This cart is no longer editable. Cancel an unfinished checkout or use My Entries for submitted entries.','pending checkout rejected');
rollback to locked;
savepoint expired;
update shows set entry_close_at=now()-interval '1 minute' where id=pg_temp.id('show');
set local role authenticated;
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"FIXED"}','{"tattoo":"WRONG"}'),'P0001','The entry deadline has passed.','expired entries rejected');
rollback to expired;
savepoint show_locked;
update shows set is_locked=true where id=pg_temp.id('show');
set local role authenticated;
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('draft'),pg_temp.id('draft_item'),'{"tattoo":"FIXED"}','{"tattoo":"WRONG"}'),'P0001','This show is locked.','locked show rejected');
rollback to show_locked;
set local role authenticated;
select throws_ok(format('select edit_entry_cart_item(%L,%L,%L::jsonb,%L::jsonb)',pg_temp.id('old_cart'),pg_temp.id('old_item'),'{"tattoo":"TAG1"}','{"tattoo":"WRONG"}'),'P0001','This cart is no longer editable. Cancel an unfinished checkout or use My Entries for submitted entries.','submitted cart rejected');
select ok(not has_function_privilege('anon','public.edit_entry_cart_item(uuid,uuid,jsonb,jsonb)','execute'),'anonymous execution denied');
select * from finish();
rollback;
