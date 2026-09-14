begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
create temporary table fee_fixture(k text primary key,id uuid default gen_random_uuid());
insert into fee_fixture(k) values('show'),('other_show'),('owner'),('other'),('first'),('second'),('already_paid'),('manual'),('draft'),('section'),('youth'),('cart'),('second_cart'),('paid_cart'),('draft_cart'),('new_cart');
grant select on fee_fixture to authenticated,service_role;
insert into auth.users(id) select id from fee_fixture where k in ('owner','other');
insert into public.secretary_feature_access(feature_key,user_id) select 'best_of_best_opposite',id from fee_fixture where k='owner';
insert into public.shows(id,name,created_by,owner_user_id,start_date,end_date,entry_close_at)
select id,'Exhibitor fee fixture',(select id from fee_fixture where k=case when f.k='show' then 'owner' else 'other' end),
(select id from fee_fixture where k=case when f.k='show' then 'owner' else 'other' end),current_date,current_date+2,now()+interval '1 day'
from fee_fixture f where k in ('show','other_show');
insert into public.exhibitors(id,display_name,owner_user_id,exhibitor_number,email)
select id,k,(select id from fee_fixture where k='owner'),995000+row_number() over(order by k),'fee-fixture@example.invalid' from fee_fixture where k in ('first','second','already_paid','manual','draft');
insert into public.show_sections(id,show_id,kind,letter,sort_order) select id,(select id from fee_fixture where k='show'),case when k='youth' then 'youth' else 'open' end,'A',case when k='youth' then 2 else 1 end from fee_fixture where k in ('section','youth');
insert into public.show_fee_settings(show_id,currency) select id,'usd' from fee_fixture where k in ('show','other_show');
insert into public.show_section_fee_settings(section_id,fee_per_entry,fur_fee) select id,10,3 from fee_fixture where k in ('section','youth') on conflict(section_id) do update set fee_per_entry=10,fur_fee=3;
insert into public.entry_carts(id,show_id,user_id) select id,(select id from fee_fixture where k='show'),(select id from fee_fixture where k='owner') from fee_fixture where k in ('cart','second_cart','paid_cart','draft_cart','new_cart');
insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,sex,class_name)
select (select id from fee_fixture where k='paid_cart'),(select id from fee_fixture where k='section'),(select id from fee_fixture where k='already_paid'),'rabbit','PAID','Dutch','Buck','Senior';
select set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',(select id from fee_fixture where k='owner'))::text,true);
select is((select calculated_total_cents from public.calculate_entry_cart_balance((select id from fee_fixture where k='paid_cart'))),1000,'disabled fee leaves normal total unchanged');
update public.show_exhibitor_balances set paid_manual_cents=1000,balance_due_cents=0,payment_status='paid' where entry_cart_id=(select id from fee_fixture where k='paid_cart');
insert into public.entries(show_id,section_id,exhibitor_id,species,tattoo,breed,source_cart_id) select (select id from fee_fixture where k='show'),(select id from fee_fixture where k='section'),(select id from fee_fixture where k='already_paid'),'rabbit','PAID','Dutch',(select id from fee_fixture where k='paid_cart');
insert into public.entries(show_id,section_id,exhibitor_id,species,tattoo,breed) select (select id from fee_fixture where k='show'),(select id from fee_fixture where k='youth'),(select id from fee_fixture where k='manual'),'cavy','MANUAL','American';
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from fee_fixture where k='owner'))::text,true);
set local role authenticated;
select lives_ok($$update public.show_fee_settings set exhibitor_fee_enabled=true,exhibitor_fee_label='Facility Fee',exhibitor_fee_amount=7.5 where show_id=(select id from fee_fixture where k='show')$$,'selected secretary enables custom fee');
reset role;
select is((select count(*)::integer from exhibitor_fees_private.charges),2,'existing paid and manual exhibitors each assessed once');
select is((select sum(balance_due_cents)::integer from public.show_exhibitor_balances where exhibitor_id=(select id from fee_fixture where k='already_paid')),750,'already-paid exhibitor owes only the new charge');
select is((select paid_manual_cents from public.show_exhibitor_balances where entry_cart_id=(select id from fee_fixture where k='paid_cart')),1000,'prior payment remains intact');
select is((select sum(entry_count)::integer from public.show_exhibitor_balances where exhibitor_id=(select id from fee_fixture where k='manual')),0,'fee-only balance does not invent animal entries');
select is((select sum(entries_subtotal_cents)::integer from public.show_exhibitor_balances where exhibitor_id=(select id from fee_fixture where k='manual')),0,'fee-only balance does not add entry fees');
select is((select sum((s->>'show_fee_cents')::int)::integer from public.show_exhibitor_balances b cross join lateral jsonb_array_elements(b.section_breakdown) s where b.exhibitor_id=(select id from fee_fixture where k='manual')),750,'section report includes one fee');
insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,sex,class_name)
select (select id from fee_fixture where k='cart'),section.id,ex.id,'rabbit',ex.k||'-'||section.k,'Dutch','Buck','Senior'
from fee_fixture section cross join fee_fixture ex where section.k in ('section','youth') and ex.k in ('first','second');
select is((select sum(calculated_total_cents)::integer from public.calculate_entry_cart_balance((select id from fee_fixture where k='cart'))),5500,'two exhibitor numbers in one household each pay one fee across two sections');
select is((select sum(calculated_total_cents)::integer from public.calculate_entry_cart_balance((select id from fee_fixture where k='cart'))),5500,'recalculation does not duplicate fees');
select is((select sum((x->>'amount_cents')::integer)::integer from jsonb_array_elements(public.get_cart_exhibitor_fees((select id from fee_fixture where k='cart'))) x),1500,'cart displays both custom charges');
select lives_ok($$select public.commit_entry_cart_day_of((select id from fee_fixture where k='cart'))$$,'pay-at-show submission works with the one-time fee');
insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,sex,class_name)
select (select id from fee_fixture where k='second_cart'),(select id from fee_fixture where k='section'),(select id from fee_fixture where k='first'),'rabbit','LATER','Dutch','Buck','Senior';
select is((select calculated_total_cents from public.calculate_entry_cart_balance((select id from fee_fixture where k='second_cart'))),1000,'later entries in another cart do not repeat fee');
select is((select count(*)::integer from exhibitor_fees_private.charges where exhibitor_id=(select id from fee_fixture where k='first')),1,'one durable charge per exhibitor');
-- A draft quote cannot strand the charge in an abandoned checkout.
insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,sex,class_name)
select c.id,(select id from fee_fixture where k='section'),(select id from fee_fixture where k='draft'),'rabbit',c.k,'Dutch','Buck','Senior' from fee_fixture c where c.k in ('draft_cart','new_cart');
select is((select calculated_total_cents from public.calculate_entry_cart_balance((select id from fee_fixture where k='draft_cart'))),1750,'first draft includes fee');
select is((select calculated_total_cents from public.calculate_entry_cart_balance((select id from fee_fixture where k='new_cart'))),1750,'another draft can take its uncommitted fee');
select is((select calculated_total_cents from public.show_exhibitor_balances where entry_cart_id=(select id from fee_fixture where k='draft_cart')),1000,'previous draft no longer contains the transferred fee');
select is((select sum((s->>'show_fee_cents')::integer)::integer from public.show_exhibitor_balances b cross join lateral jsonb_array_elements(b.section_breakdown) s where b.entry_cart_id=(select id from fee_fixture where k='draft_cart')),0,'transferred fee removed from old section breakdown');
delete from public.entry_cart_items where cart_id=(select id from fee_fixture where k='new_cart');
select is((select count(*)::integer from exhibitor_fees_private.charges where exhibitor_id=(select id from fee_fixture where k='draft')),0,'removing unsubmitted exhibitor releases charge');
select is((select calculated_total_cents from public.calculate_entry_cart_balance((select id from fee_fixture where k='draft_cart'))),1750,'remaining draft can assess it once again');
-- Fee never receives entry discounts.
update public.show_fee_settings set multi_show_discount_enabled=true,multi_show_discount_type='percent',multi_show_discount_value=100,multi_show_discount_min_entries=1,multi_show_discount_required_shows=1 where show_id=(select id from fee_fixture where k='show');
select is((select calculated_total_cents from public.calculate_entry_cart_balance((select id from fee_fixture where k='draft_cart'))),750,'100 percent entry discount leaves exhibitor fee due');
update public.show_fee_settings set exhibitor_fee_amount=20 where show_id=(select id from fee_fixture where k='show');
select is((select amount_cents from exhibitor_fees_private.charges where exhibitor_id=(select id from fee_fixture where k='first')),750,'existing assessments retain their original amount');
select is((select count(*)::integer from public.entries where tattoo='EXHIBITOR-FEE'),0,'fee carriers never become show entries');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from fee_fixture where k='other'))::text,true);
set local role authenticated;
select throws_ok($$update public.show_fee_settings set exhibitor_fee_enabled=true,exhibitor_fee_amount=10 where show_id=(select id from fee_fixture where k='other_show')$$,'42501','The one-time exhibitor fee is only available for selected secretaries’ shows.','unselected secretary cannot enable fee through API');
select throws_ok($$select public.get_cart_exhibitor_fees((select id from fee_fixture where k='cart'))$$,'42501','You do not have access to this cart','fee preview protects another household cart');
reset role;
select ok(not has_table_privilege('authenticated','exhibitor_fees_private.charges','UPDATE'),'client cannot alter recorded charges');
select ok(not has_function_privilege('authenticated','exhibitor_fees_private.ensure_charge(uuid,uuid,uuid,uuid)','EXECUTE'),'internal assessment helper is not callable');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from fee_fixture where k='other'))::text,true);
set local role authenticated;
select throws_ok($$update public.show_fee_settings set exhibitor_fee_enabled=false where show_id=(select id from fee_fixture where k='show')$$,'42501','The one-time exhibitor fee is only available for selected secretaries’ shows.','unrelated user cannot disable the restricted fee');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',(select id from fee_fixture where k='owner'))::text,true);
insert into fee_fixture(k) values('reassigned');
insert into public.exhibitors(id,display_name,exhibitor_number,email,owner_user_id)
select id,'Reassigned',995020,'reassigned@example.invalid',(select id from fee_fixture where k='owner') from fee_fixture where k='reassigned';
update public.entries set exhibitor_id=(select id from fee_fixture where k='reassigned') where tattoo='MANUAL';
select is((select amount_cents from exhibitor_fees_private.charges where exhibitor_id=(select id from fee_fixture where k='reassigned')),2000,'reassigning an entry assesses the new exhibitor at the current rate');
update public.entries set tattoo='MANUAL-UPDATED' where tattoo='MANUAL';
select is((select count(*)::integer from exhibitor_fees_private.charges where exhibitor_id=(select id from fee_fixture where k='reassigned')),1,'other entry edits do not repeat the fee');
update public.shows set is_locked=true where id=(select id from fee_fixture where k='show');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from fee_fixture where k='owner'))::text,true);
set local role authenticated;
select throws_ok($$update public.show_fee_settings set exhibitor_fee_amount=30 where show_id=(select id from fee_fixture where k='show')$$,'42501','This show is locked or finalized. Fees cannot be changed.','locked show rejects fee changes');
reset role;
select * from finish();
rollback;
