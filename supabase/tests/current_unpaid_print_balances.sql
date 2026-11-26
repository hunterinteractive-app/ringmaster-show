begin;
set local search_path=public,extensions;
select no_plan();

create temporary table fixtures(key text primary key,id uuid default gen_random_uuid());
insert into fixtures(key) select unnest(array[
  'staff','stranger','show','section','submitted_cart_a','submitted_cart_b','unfinished_cart',
  'cart_exhibitor','secretary_exhibitor','draft_exhibitor','partial_exhibitor','paid_exhibitor'
]);
create function pg_temp.id(text) returns uuid language sql as $$select id from fixtures where key=$1$$;
create function pg_temp.as_user(text) returns text language sql as $$
  select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.id($1))::text,true)
$$;

insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select id,'authenticated','authenticated',id||'@example.invalid','{}','{}' from fixtures where key in('staff','stranger');
insert into shows(id,name,created_by,start_date,end_date,is_test)
values(pg_temp.id('show'),'Current balances fixture',pg_temp.id('staff'),current_date,current_date,true);
insert into show_sections(id,show_id,kind,letter,is_enabled)
values(pg_temp.id('section'),pg_temp.id('show'),'open','A',true);
insert into exhibitors(id,display_name,email,owner_user_id)
select id,key,key||'@example.invalid',pg_temp.id('staff') from fixtures where key like '%_exhibitor';

insert into entry_carts(id,user_id,show_id,status)
select id,pg_temp.id('staff'),pg_temp.id('show'),case when key='unfinished_cart' then 'active' else 'submitted' end
from fixtures where key like 'submitted_cart_%' or key='unfinished_cart';

select set_config('ringmaster.manual_balance_refresh','on',true);
insert into show_exhibitor_balances(show_id,exhibitor_id,entry_cart_id,source,currency,
  entry_count,fur_count,entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,
  subtotal_before_discount_cents,discount_cents,calculated_total_cents,paid_online_cents,
  paid_manual_cents,refunded_cents,balance_due_cents,payment_status,section_breakdown)
select pg_temp.id('show'),pg_temp.id(exhibitor),pg_temp.id(cart),source,'usd',
  entries,0,charge,0,0,charge,0,charge,online,0,0,charge-online,
  case when charge=online then 'paid' when online>0 then 'partial' else 'unpaid' end,
  jsonb_build_array(jsonb_build_object('section_id',pg_temp.id('section'),'label','Open A',
    'kind','open','letter','A','entry_count',entries,'fur_count',0,'entries_subtotal_cents',charge))
from (values
  ('cart_exhibitor','submitted_cart_a','cart',2,1000,0),
  ('cart_exhibitor','submitted_cart_b','cart',1,500,0),
  ('cart_exhibitor','unfinished_cart','cart',9,4500,0),
  ('draft_exhibitor','unfinished_cart','cart',1,500,0),
  ('secretary_exhibitor',null,'entries',2,1000,0),
  ('secretary_exhibitor','submitted_cart_a','cart',4,2000,0),
  ('partial_exhibitor','submitted_cart_b','cart',2,1000,300),
  ('paid_exhibitor',null,'entries',1,500,500)
) v(exhibitor,cart,source,entries,charge,online);
select set_config('ringmaster.manual_balance_refresh','off',true);
select pg_temp.as_user('staff');

grant select on fixtures to authenticated;
set local role authenticated;
create temporary table current_report as select r from report_current_show_balances(pg_temp.id('show')) r;
select is((select count(*)::int from current_report),4,'one row per exhibitor, unfinished cart excluded');
select is((select r->>'balance_due_cents' from current_report where r->>'exhibitor_id'=pg_temp.id('cart_exhibitor')::text),'1500',
  'two submitted carts are combined, active cart is excluded');
select is((select r->'section_breakdown'->0->>'entry_count' from current_report
  where r->>'exhibitor_id'=pg_temp.id('cart_exhibitor')::text),'3','entries for the same section are aggregated through both carts');
select is((select r->>'balance_due_cents' from current_report where r->>'exhibitor_id'=pg_temp.id('secretary_exhibitor')::text),'1000',
  'the exhibitor balance supersedes its submitted cart');
select is((select r->>'payment_status' from current_report where r->>'exhibitor_id'=pg_temp.id('partial_exhibitor')::text),'partial',
  'partial on a submitted cart is clearly classified');
select is(
  (select jsonb_object_agg(r->>'exhibitor_id',r->'balance_due_cents') from current_report),
  (select jsonb_object_agg(f->>'exhibitor_id',f->'due_cents') from jsonb_array_elements(get_show_finances(pg_temp.id('show'))->'exhibitors') f),
  'Show Finances and the printable report reconcile for each exhibitor');
select pg_temp.as_user('stranger');
select throws_ok(format('select report_current_show_balances(%L)',pg_temp.id('show')),'42501',
  'You do not have permission to manage this show''s finances.','other accounts cannot read the report');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is((select count(*)::int from report_current_show_balances(pg_temp.id('show'))),4,
  'background service role can generate the report');
select ok(not has_function_privilege('anon','report_current_show_balances(uuid)','execute'),'anonymous report access denied');

select * from finish();
rollback;
