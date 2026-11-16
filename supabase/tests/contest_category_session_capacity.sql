-- Disposable fixtures only; all entries/payment holds are local and rolled back.
begin;
create extension if not exists pgtap with schema extensions;
create schema capacity_test;
set local search_path=capacity_test,public,extensions;
select no_plan();
create table fx(k text primary key,id uuid default gen_random_uuid());
insert into fx(k) values('secretary'),('buyer'),('host'),('cavy'),('contest'),('payment');
create function capacity_test.id(text) returns uuid language sql as $$select id from capacity_test.fx where k=$1$$;
create table people(n integer primary key,ex uuid default gen_random_uuid(),cart uuid default gen_random_uuid(),registration uuid default gen_random_uuid());
insert into people(n) select generate_series(1,30);
create function capacity_test.actor() returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',capacity_test.id('buyer')::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',capacity_test.id('buyer'),'role','authenticated')::text,true);
end;$$;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',k||'-'||id||'@example.invalid','{}','{}' from fx where k in('secretary','buyer');
insert into shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test,entry_open_at,entry_close_at,payment_timing_mode,online_payment_fee_mode,contests_enabled)
select id,capacity_test.id('secretary'),capacity_test.id('secretary'),k,current_date,current_date+2,true,true,
 now()-interval '1 day',now()+interval '1 day','online_or_at_show','club_absorbs',k='host'
from fx where k in('host','cavy');
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
select ex,'Capacity child '||n,capacity_test.id('buyer'),998400+n,'capacity@example.invalid',true,true from people;
insert into show_sections(id,show_id,kind,letter,display_name,sort_order)
select id,id,'youth','A','Youth',1 from fx where k in('host','cavy');
insert into show_fee_settings(show_id,currency) select id,'USD' from fx where k in('host','cavy');
insert into entry_carts(id,user_id,show_id)
select cart,capacity_test.id('buyer'),capacity_test.id(case when n%2=0 then 'host' else 'cavy' end) from people;
insert into show_addons_private.offerings(id,show_id,kind,name,price_cents,enabled,requires_animal_entry,animal_selection,contest_config)
values(capacity_test.id('contest'),capacity_test.id('host'),'contest','Costume capacity fixture',500,true,false,'none',
 '{"entry_type":"individual","category_session_capacity":20,"categories":["Theme","Funny"],"sessions":[{"id":"sat","name":"Saturday","starts_at":"2030-03-06T12:00:00Z","ends_at":"2030-03-06T14:00:00Z","capacity":100},{"id":"mon","name":"Monday","starts_at":"2030-03-08T12:00:00Z","ends_at":"2030-03-08T14:00:00Z","capacity":100}]}');
insert into show_addons_private.contest_show_links values(capacity_test.id('contest'),capacity_test.id('cavy'));
create function capacity_test.enter(p_n integer,p_category text default 'Theme',p_session text default 'sat') returns uuid language plpgsql as $$
declare r capacity_test.people%rowtype;
begin
 perform capacity_test.actor(); select * into r from capacity_test.people where n=p_n;
 return public.save_contest_registration(r.cart,capacity_test.id('contest'),r.ex,1,'{}',null,null,
  jsonb_build_object('category',p_category,'session_id',p_session),r.registration);
end;$$;
create function capacity_test.checkout(p_n integer) returns void language plpgsql as $$begin
 perform capacity_test.actor();
 perform public.commit_entry_cart_day_of((select cart from capacity_test.people where n=p_n));
end;$$;
create function capacity_test.config() returns jsonb language sql as $$
 select contest_config from show_addons_private.offerings where id=capacity_test.id('contest');
$$;
grant usage on schema capacity_test to authenticated;
grant select on all tables in schema capacity_test to authenticated;
-- Seed 19 submitted places across both portals, leaving one available.
set local role authenticated;
do $$begin for n in 1..19 loop perform capacity_test.enter(n); perform capacity_test.checkout(n); end loop; end;$$;
reset role;
-- Test assertions (the concurrency runner reuses only the fixture above).
select lives_ok($$select show_addons_private.validate_config(capacity_test.config(),'[]')$$,'category/session capacity is a supported setting');
select lives_ok($$select show_addons_private.validate_config('{}','[]')$$,'existing contests without this setting remain valid');
select throws_ok($$select show_addons_private.validate_config('{"category_session_capacity":-1}','[]')$$,'P0001','Invalid number for category_session_capacity.','negative capacity rejected');
select throws_ok($$select show_addons_private.validate_config('{"category_session_capacity":1.5}','[]')$$,'P0001','Invalid number for category_session_capacity.','fractional capacity rejected');
select throws_ok($$select show_addons_private.validate_config('{"category_session_capacity":"20"}','[]')$$,'P0001','Invalid number for category_session_capacity.','text capacity rejected');
select throws_ok($$select show_addons_private.validate_config('{"category_session_capacity":100001}','[]')$$,'P0001','Invalid number for category_session_capacity.','unbounded capacity value rejected');
select throws_ok($$select show_addons_private.validate_config('{"category_session_capacity":20}','[]')$$,'P0001','Add categories and sessions before setting a category/session limit.','capacity needs category and session definitions');
select is((select count(distinct c.show_id)::int from show_addons_private.selections x join public.entry_carts c on c.id=x.cart_id),2,'capacity population contains Rabbit and Cavy carts');
set local role authenticated;
select lives_ok($$select capacity_test.enter(20)$$,'20th place can be added from Rabbit portal');
select lives_ok($$select capacity_test.enter(21)$$,'another draft can exist before the last place is reserved');
select lives_ok($$select capacity_test.enter(20)$$,'editing the same registration does not count it twice');
reset role;
-- Simulated local payment reservation; no provider is called.
insert into show_payment_sessions(id,show_id,cart_id,provider,expected_amount_cents,expected_currency)
select capacity_test.id('payment'),c.show_id,c.id,'square',500,'usd' from entry_carts c where c.id=(select cart from people where n=20);
update entry_carts set active_payment_session_id=capacity_test.id('payment') where id=(select cart from people where n=20);
set local role authenticated;
select throws_ok($$select capacity_test.enter(22)$$,'P0001','This category has reached its limit of 20 entries for this session. Choose another category or session.','payment reservation holds the final place');
reset role;
update entry_carts set active_payment_session_id=null where id=(select cart from people where n=20);
set local role authenticated;
select lives_ok($$select capacity_test.enter(22)$$,'released payment reservation makes place available');
select lives_ok($$select capacity_test.checkout(20)$$,'20th registration completes checkout');
select throws_ok($$select capacity_test.checkout(21)$$,'P0001','This category has reached its limit of 20 entries for this session. Choose another category or session.','checkout rechecks a stale Cavy draft after Rabbit takes last place');
select throws_ok($$select capacity_test.enter(22)$$,'P0001','This category has reached its limit of 20 entries for this session. Choose another category or session.','21st Rabbit entry rejected');
select throws_ok($$select capacity_test.enter(23)$$,'P0001','This category has reached its limit of 20 entries for this session. Choose another category or session.','21st Cavy entry rejected by same shared limit');
select lives_ok($$select capacity_test.enter(21,'Funny','sat')$$,'another category in the same session remains available');
select lives_ok($$select capacity_test.enter(22,'Theme','mon')$$,'same category in another session has an independent limit');
select lives_ok($$select capacity_test.checkout(21)$$,'another category can complete checkout');
select lives_ok($$select capacity_test.checkout(22)$$,'another session can complete checkout');
reset role;
select is((select count(*)::int from show_addons_private.selections x join entry_carts c on c.id=x.cart_id where c.status='submitted' and x.registration_data->>'category'='Theme' and x.registration_data->>'session_id'='sat'),20,'completed category/session total stays at 20');
-- One cart must count siblings already in that cart as well.
update show_addons_private.offerings set contest_config=jsonb_set(contest_config,'{category_session_capacity}','1') where id=capacity_test.id('contest');
set local role authenticated;
select lives_ok($$select capacity_test.enter(24,'Funny','mon')$$,'empty category/session accepts one draft');
select throws_ok($$select public.save_contest_registration((select cart from capacity_test.people where n=24),capacity_test.id('contest'),(select ex from capacity_test.people where n=25),1,'{}',null,null,'{"category":"Funny","session_id":"mon"}')$$,'P0001','This category has reached its limit of 1 entries for this session. Choose another category or session.','siblings in the same cart cannot overfill a category/session');
reset role;
update show_addons_private.offerings set contest_config=jsonb_set(contest_config,'{category_session_capacity}','0') where id=capacity_test.id('contest');
set local role authenticated;
select lives_ok($$select capacity_test.enter(23)$$,'zero disables only the new category/session capacity');
reset role;
select * from finish();
rollback;
