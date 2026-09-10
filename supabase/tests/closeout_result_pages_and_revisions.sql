create extension if not exists pgtap with schema extensions;
begin;
select plan(13);
create temporary table original_revision as
select public.get_report_result_revision('20000000-0000-0000-0000-000000000004') revision,
       public.get_report_result_revision('20000000-0000-0000-0000-000000000001') other_revision;
update public.entries set tattoo = tattoo || '-REVISION-TEST'
where id = (select id from public.entries where show_id='20000000-0000-0000-0000-000000000004' order by id limit 1);
select isnt(public.get_report_result_revision('20000000-0000-0000-0000-000000000004'),
  (select revision from original_revision), 'editing an entry invalidates its cached population');
select is(public.get_report_result_revision('20000000-0000-0000-0000-000000000001'),
  (select other_revision from original_revision), 'entry edits do not invalidate unrelated shows');
update original_revision set revision=public.get_report_result_revision('20000000-0000-0000-0000-000000000004');
update public.exhibitors set display_name = display_name
where id=(select exhibitor_id from public.entries where show_id='20000000-0000-0000-0000-000000000004' limit 1);
select isnt(public.get_report_result_revision('20000000-0000-0000-0000-000000000004'),
  (select revision from original_revision), 'profile edits invalidate report names and addresses');
update original_revision set revision=public.get_report_result_revision('20000000-0000-0000-0000-000000000004');
update public.show_sections set sort_order=sort_order where id='21000000-0000-0000-0000-000000000004';
select isnt(public.get_report_result_revision('20000000-0000-0000-0000-000000000004'),
  (select revision from original_revision), 'section edits invalidate scope and judging-date data');
create temporary table expected as select * from public.report_results_entry_rows('20000000-0000-0000-0000-000000000004');
create temporary table page1 as select * from public.report_results_entry_rows_page('20000000-0000-0000-0000-000000000004',p_page_size=>2);
create temporary table page2 as select * from public.report_results_entry_rows_page('20000000-0000-0000-0000-000000000004',p_after_entry_id=>(select max(entry_id::text)::uuid from page1),p_page_size=>1000);
select is((select count(*)::int from page1),2,'the SQL bounds the first page');
select results_eq('select * from page1 union all select * from page2 order by entry_id',
  'select * from expected order by entry_id', 'cursor pages preserve every projected result and its domain rules');
select results_eq($q$select * from public.report_results_entry_rows_page('20000000-0000-0000-0000-000000000004',p_breed=>'Mini Rex') order by entry_id$q$,
  $q$select * from expected where breed='Mini Rex' order by entry_id$q$, 'QR breed filtering happens without losing result data');
select results_eq($q$select entry_id from public.report_results_entry_rows_page('20000000-0000-0000-0000-000000000004',p_entry_ids=>array[(select entry_id from page1 order by entry_id limit 1)])$q$,
  'select entry_id from page1 order by entry_id limit 1', 'manual refresh returns only the requested entry');
select ok(not has_function_privilege('authenticated','public.get_report_result_revision(uuid)','execute'),
  'browser clients cannot access the worker revision RPC');
select ok(not has_function_privilege('anon','public.report_results_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer)','execute'),
  'cursor results preserve the existing anonymous-access restriction');
select ok(not has_function_privilege('anon','public.get_show_checkin_roster_page(uuid,text,text,uuid,integer)','execute'),
  'cursor roster preserves the existing anonymous-access restriction');
set local role authenticated;
select set_config('request.jwt.claim.sub','ffffffff-ffff-ffff-ffff-ffffffffffff',true);
select throws_ok($q$select public.get_closeout_dashboard_scoped('20000000-0000-0000-0000-000000000004','scope',array['21000000-0000-0000-0000-000000000004'::uuid])$q$,
  '42501','Not authorized to manage closeout for this show','dashboard denies another show manager');
select throws_ok($q$select public.get_closeout_dashboard_scoped_for_species('20000000-0000-0000-0000-000000000004','scope',array['21000000-0000-0000-0000-000000000004'::uuid],200,0,null,'rabbit')$q$,
  '42501','Not authorized to manage closeout for this show','species dashboard preserves the same permission check');
reset role;
select * from finish();
rollback;
