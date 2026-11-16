-- Synthetic shared judging registration; never creates hosted entries/payments.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table fx(k text primary key,id uuid default gen_random_uuid());
insert into fx(k) values('secretary'),('buyer'),('other'),('host'),('cavy'),('ordinary'),
 ('host_section'),('cavy_section'),('ordinary_section'),('kid'),('kid2'),('stranger'),
 ('cart'),('host_cart'),('ordinary_cart'),('judging'),('team'),('costume');
grant select on fx to authenticated;
create function pg_temp.fx(text) returns uuid language sql as $$select id from fx where k=$1$$;
create function pg_temp.actor(text) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx($1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.fx($1),'role','authenticated')::text,true);
end;$$;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',k||'-'||id||'@example.invalid','{}','{}' from fx where k in('secretary','buyer','other');
insert into shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test,entry_open_at,entry_close_at,payment_timing_mode,online_payment_fee_mode,contests_enabled)
select id,pg_temp.fx('secretary'),pg_temp.fx('secretary'),k,current_date,current_date+2,true,true,
 now()-interval '1 day',now()+interval '1 day','online_or_at_show','club_absorbs',k='host'
from fx where k in('host','cavy','ordinary');
insert into exhibitors(id,display_name,owner_user_id,exhibitor_number,email,is_active,is_test)
select id,k,case when k='stranger' then pg_temp.fx('other') else pg_temp.fx('buyer') end,
 998300+row_number() over(order by k),k||'@example.invalid',true,true from fx where k in('kid','kid2','stranger');
insert into show_sections(id,show_id,kind,letter,display_name,sort_order)
select pg_temp.fx(k||'_section'),id,'youth','A','Youth',1 from fx where k in('host','cavy','ordinary');
insert into show_fee_settings(show_id,currency) select id,'USD' from fx where k in('host','cavy','ordinary');
insert into entry_carts(id,user_id,show_id)
select id,pg_temp.fx('buyer'),pg_temp.fx(case k when 'cart' then 'cavy' when 'host_cart' then 'host' else 'ordinary' end)
from fx where k in('cart','host_cart','ordinary_cart');
insert into show_addons_private.offerings(id,show_id,kind,name,price_cents,enabled,requires_animal_entry,animal_selection,divisions,contest_config)
select id,pg_temp.fx('host'),'contest',k,case when k='team' then 2000 else 500 end,true,k='costume',
 case when k='costume' then 'required' else 'none' end,'["Junior","Senior"]'::jsonb,
 jsonb_build_object('entry_type',case when k='team' then 'team' else 'individual' end,
 'age_as_of','custom','age_date','2026-08-31','collect_birthdate',true,'team_min',3,'team_max',4,
 'age_rules',jsonb_build_array(jsonb_build_object('division','Junior','min',8,'max',10),jsonb_build_object('division','Senior','min',14,'max',18)))
from fx where k in('judging','team','costume');
insert into show_addons_private.contest_show_links select id,pg_temp.fx('cavy') from fx where k in('judging','team','costume');
create function pg_temp.child() returns jsonb language sql as $$select '{"birthdate":"2017-01-01"}'::jsonb$$;
create function pg_temp.team() returns jsonb language sql as $$select '{"team":{"name":"Cavy Team","authorized":true,"members":[{"name":"A","birthdate":"2017-01-01"},{"name":"B","birthdate":"2016-01-01"},{"name":"C","birthdate":"2017-02-01"}]}}'::jsonb$$;
select pg_temp.actor('buyer');
set local role authenticated;
select is(jsonb_array_length(get_show_addons(pg_temp.fx('cavy'))->'items'),3,'both judging options appear alongside existing shared contest');
select is(jsonb_array_length(get_show_addons(pg_temp.fx('ordinary'))->'items'),0,'unlinked show gets no shared offerings');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('judging'),pg_temp.fx('stranger'),1,'{}','Junior',null,pg_temp.child())$$,
 '42501','Choose an active exhibitor from this household.','shared judging keeps household authorization');
select throws_ok($$select save_contest_registration(pg_temp.fx('ordinary_cart'),pg_temp.fx('judging'),pg_temp.fx('kid'),1,'{}','Junior',null,pg_temp.child())$$,
 'P0001','This contest or add-on is not available.','unlinked show cannot register shared judging');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('judging'),pg_temp.fx('kid'),1,'{}','Senior',null,pg_temp.child())$$,
 'P0001','The selected division does not match the age requirements.','shared judging retains age/division rules');
select throws_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('costume'),pg_temp.fx('kid'),1,'{}','Junior',null,pg_temp.child())$$,
 'P0001','costume requires a youth animal entry in the rabbit or linked cavy show for this exhibitor.','animal-required contest still rejects no-animal entry');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('judging'),pg_temp.fx('kid'),1,'{}','Junior',null,pg_temp.child())$$,
 'Cavy cart registers individual judging without selecting or entering an animal');
select throws_ok($$select save_contest_registration(pg_temp.fx('host_cart'),pg_temp.fx('judging'),pg_temp.fx('kid'),1,'{}','Junior',null,pg_temp.child())$$,
 'P0001','The limit for judging is 1 per exhibitor across the full show.','cross-portal duplicate judging registration rejected');
select lives_ok($$select save_contest_registration(pg_temp.fx('host_cart'),pg_temp.fx('judging'),pg_temp.fx('kid2'),1,'{}','Junior',null,pg_temp.child())$$,
 'Rabbit portal retains standalone judging registration after linking');
select lives_ok($$select save_contest_registration(pg_temp.fx('cart'),pg_temp.fx('team'),pg_temp.fx('kid'),1,'{}','Junior',null,pg_temp.team())$$,
 'Cavy cart registers judging team with original roster rules and no animal requirement');
reset role;
select is((select sum(quantity*unit_price_cents)::int from show_addons_private.selections where cart_id=pg_temp.fx('cart')),2500,'original individual and team fees retained in Cavy cart');
select is((select count(*)::int from show_addons_private.selections where cart_id=pg_temp.fx('cart') and show_id=pg_temp.fx('host')),2,'both Cavy registrations belong to original Rabbit contest roster');
select is((select count(*)::int from entry_carts),3,'shared registration creates no additional cart');
set local role authenticated;
select lives_ok($$select commit_entry_cart_day_of(pg_temp.fx('cart'))$$,'shared judging checkout succeeds locally without a payment provider');
select pg_temp.actor('secretary');
select is(jsonb_array_length(get_show_addon_registrations(pg_temp.fx('host'))),2,'Rabbit secretary sees submitted individual and team registrations');
select is(jsonb_array_length(get_show_addon_registrations(pg_temp.fx('cavy'))),0,'no duplicate Cavy roster');
reset role;
select * from finish();
rollback;
