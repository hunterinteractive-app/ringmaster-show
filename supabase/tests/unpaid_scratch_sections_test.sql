begin;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
create temporary table ids(k text primary key,id uuid default gen_random_uuid());
insert into ids(k) values('show'),('A'),('B'),('person'),('other'),('cart'),('balance'),('oldA'),('oldB'),('newA'),('newB'),('extra'),('itemA'),('itemB');
create function pg_temp.id(text) returns uuid language sql as $$select id from ids where k=$1$$;
create function pg_temp.balance() returns jsonb language sql as $$select to_jsonb(b) from show_exhibitor_balances b where source='entries' and exhibitor_id=pg_temp.id('person')$$;
create function pg_temp.due() returns integer language sql as $$select (pg_temp.balance()->>'balance_due_cents')::int$$;
create function pg_temp.offset_cents() returns integer language sql as $$select (pg_temp.balance()->'fee_snapshot'->>'replacement_credit_cents')::int$$;
update show_finances_private.replacement_policy set enabled_at=now()-interval '1 day';
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
select ('00000000-0000-4000-8000-0000000000'||n)::uuid,'authenticated','authenticated','bulk'||n||'@example.invalid','{}','{}' from unnest(array['01','99','98']) n on conflict do nothing;
insert into shows(id,created_by,name,entry_close_at,start_date,end_date) values(pg_temp.id('show'),'00000000-0000-4000-8000-000000000001','Replacement fixture',now()+interval '2 days',current_date+3,current_date+3);
insert into exhibitors(id,display_name,email,owner_user_id) select id,k,k||'@example.invalid','00000000-0000-4000-8000-000000000099' from ids where k in ('person','other');
insert into show_sections(id,show_id,kind,letter,is_enabled,sort_order) select id,pg_temp.id('show'),'open',k,true,1 from ids where k in ('A','B');
insert into show_fee_settings(show_id,currency) values(pg_temp.id('show'),'usd');
insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee,fee_per_show) select id,5,1,0 from ids where k in ('A','B') on conflict(section_id) do update set fee_per_entry=5,fur_fee=1,fee_per_show=0;
insert into entry_carts(id,show_id,status,user_id) values(pg_temp.id('cart'),pg_temp.id('show'),'submitted','00000000-0000-4000-8000-000000000099');
insert into entry_cart_items(id,cart_id,section_id,exhibitor_id,is_fur,species,breed) select pg_temp.id('item'||k),pg_temp.id('cart'),id,pg_temp.id('person'),false,'rabbit','Havana' from ids where k in ('A','B');
insert into show_exhibitor_balances(id,show_id,exhibitor_id,entry_cart_id,source,currency,entry_count,fur_count,
 entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,subtotal_before_discount_cents,discount_cents,calculated_total_cents,
 paid_online_cents,paid_manual_cents,refunded_cents,addons_subtotal_cents,balance_due_cents,section_breakdown)
select pg_temp.id('balance'),pg_temp.id('show'),pg_temp.id('person'),pg_temp.id('cart'),'cart','usd',2,0,1000,0,0,1000,0,1000,0,0,0,0,1000,
 jsonb_agg(jsonb_build_object('section_id',id,'entry_count',1,'fur_count',0,'entries_subtotal_cents',500,'fur_subtotal_cents',0,'show_fee_cents',0)) from ids where k in ('A','B');
create temporary table original_receipts as select to_jsonb(p) data from show_payments p;
insert into entries(id,show_id,section_id,exhibitor_id,source_cart_id,source_cart_item_id,is_fur,status,species,tattoo,breed,created_at)
 select pg_temp.id('old'||k),pg_temp.id('show'),id,pg_temp.id('person'),pg_temp.id('cart'),pg_temp.id('item'||k),false,'entered','rabbit','OLD','Havana',now()-interval '3 days' from ids where k in ('A','B');

select is(pg_temp.due(),1000,'unpaid checkout initially owes both sections');
create temporary table original_quote as select to_jsonb(b) data from show_exhibitor_balances b where source='cart';
update entries set scratched_at=now(),status='scratched' where id=pg_temp.id('oldA');
select is(pg_temp.due(),500,'predeadline scratch removes unpaid section A fee');
select is((select count(*)::integer from show_finances_private.unpaid_scratch_lines where active),1,'one auditable fee exclusion');
select is((select (r->>'balance_due_cents')::integer from report_show_exhibitor_balances_scoped(pg_temp.id('show'),array[pg_temp.id('A')],false) r where r->>'exhibitor_id'=pg_temp.id('person')::text),0,'section A report no longer charges scratched entry');
select is((select (r->>'balance_due_cents')::integer from report_show_exhibitor_balances_scoped(pg_temp.id('show'),array[pg_temp.id('B')],false) r where r->>'exhibitor_id'=pg_temp.id('person')::text),500,'section B report remains due');
select is((select to_jsonb(b) from show_exhibitor_balances b where source='cart'),(select data from original_quote),'frozen quote remains unchanged');
update entries set scratched_at=null,status='entered' where id=pg_temp.id('oldA');
select is(pg_temp.due(),1000,'restore restores charge');
update show_exhibitor_balances set discount_cents=1,calculated_total_cents=999 where source='cart';
update entries set scratched_at=now(),status='scratched' where id in (pg_temp.id('oldA'),pg_temp.id('oldB'));
select is(pg_temp.due(),0,'both scratches remove discounted charge without rounding residue');
select is((select sum(discount_cents)::integer from show_finances_private.unpaid_scratch_lines where active),1,'one-cent discount allocated exactly once');
update show_exhibitor_balances set discount_cents=0,calculated_total_cents=1000 where source='cart';
update entries set scratched_at=null,status='entered';
update show_exhibitor_balances set paid_online_cents=0 where source='cart';
update shows set entry_close_at=now()-interval '1 minute';
update entries set scratched_at=now(),status='scratched' where id=pg_temp.id('oldA');
select is(pg_temp.due(),1000,'late scratch keeps original charge');
update entries set scratched_at=null,status='entered';
update shows set entry_close_at=now()+interval '1 day';
update entry_carts set payment_status='pending';
select throws_ok(format('update entries set scratched_at=now(),status=%L where id=%L','scratched',pg_temp.id('oldA')),'P0001','A payment is in progress. Finish or cancel it before scratching this entry.','in-flight payment blocks balance-changing scratch');
select is((select status from entries where id=pg_temp.id('oldA')),'entered','failed scratch is atomic');

update entry_carts set payment_status='unpaid';
update entries set scratched_at=null,status='entered';
update show_exhibitor_balances set discount_cents=0,calculated_total_cents=1000,paid_online_cents=1000 where source='cart';
update entries set scratched_at=now(),status='scratched' where id=pg_temp.id('oldA');
select is((select count(*)::integer from show_finances_private.unpaid_scratch_lines where active),0,'paid scratch does not waive fees');
select is((pg_temp.balance()->>'calculated_total_cents')::integer,1000,'paid receipt charges preserved');

update entry_carts set payment_status='unpaid';
update entries set scratched_at=null,status='entered';
insert into animals(id,owner_user_id,species,tattoo,breed,variety,sex) values(pg_temp.id('extra'),'00000000-0000-4000-8000-000000000099','rabbit','OLD','Havana','Black','Buck');
update entries set animal_id=pg_temp.id('extra'),exhibitor_user_id='00000000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
grant select on ids to authenticated;
set local role authenticated;
select is((apply_entry_section_changes(pg_temp.id('oldA'),array[pg_temp.id('A'),pg_temp.id('B')],'{"tattoo":"  new42  "}'::jsonb)->>'entry_count')::integer,2,'exhibitor edits matching animal across selected sections');
reset role;
select is((select count(*)::integer from entries where tattoo='NEW42'),2,'tattoos normalized and saved directly');
select throws_ok(format('select apply_entry_section_changes(%L,array[%L::uuid,%L::uuid],%L::jsonb)',pg_temp.id('oldA'),pg_temp.id('A'),pg_temp.id('other'),'{"tattoo":"WRONG"}'),'P0001','A selected section no longer contains this animal. Refresh and try again.','invalid section rejects whole batch');
select is((select count(*)::integer from entries where tattoo='NEW42'),2,'failed batch changes no entries');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000098","role":"authenticated"}',true);
set local role authenticated;
select throws_ok(format('select apply_entry_section_changes(%L,array[%L::uuid],%L::jsonb)',pg_temp.id('oldA'),pg_temp.id('A'),'{"tattoo":"WRONG"}'),'42501','You do not have permission to update this entry','unrelated exhibitor denied');
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
select is(has_function_privilege('anon','public.apply_entry_section_changes(uuid,uuid[],jsonb,boolean)','execute'),false,'anonymous access denied');
update entries set class_name=case when section_id=pg_temp.id('A') then 'Senior' else 'Junior' end;
select apply_entry_section_changes(pg_temp.id('oldA'),array[pg_temp.id('A')],'{"tattoo":"ONLYA"}');
select is((select tattoo from entries where id=pg_temp.id('oldB')),'NEW42','unselected section remains unchanged');
select is((select class_name from entries where id=pg_temp.id('oldB')),'Junior','tattoo edit preserves other section class');
select is((select tattoo from animals where id=pg_temp.id('extra')),'OLD','saved animal profile remains unchanged');
select apply_entry_section_changes(pg_temp.id('oldA'),array[pg_temp.id('A'),pg_temp.id('B')],'{}',true);
select is((select count(*)::integer from entries where status='scratched'),2,'bulk scratch selects both sections');
select apply_entry_section_changes(pg_temp.id('oldA'),array[pg_temp.id('A')],'{}',false);
select is((select status from entries where id=pg_temp.id('oldB')),'scratched','restore leaves unselected section scratched');
select apply_entry_section_changes(pg_temp.id('oldB'),array[pg_temp.id('B')],'{}',false);
update shows set entry_close_at=now()-interval '1 minute';
select throws_ok(format('select apply_entry_section_changes(%L,array[%L::uuid],%L::jsonb)',pg_temp.id('oldA'),pg_temp.id('A'),'{"tattoo":"LATE"}'),'P0001','Entry deadline passed. Editing and restoring are locked.','exhibitor edits enforce deadline');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select is((apply_entry_section_changes(pg_temp.id('oldA'),array[pg_temp.id('A'),pg_temp.id('B')],'{"tattoo":"STAFF"}'::jsonb)->>'entry_count')::integer,2,'secretary can correct entries after deadline');
update shows set is_locked=true;
select throws_ok(format('select apply_entry_section_changes(%L,array[%L::uuid],%L::jsonb)',pg_temp.id('oldA'),pg_temp.id('A'),'{"tattoo":"LOCKED"}'),'P0001','Show is locked. Changes are not allowed.','show lock also protects staff edits');
select * from finish();
rollback;
