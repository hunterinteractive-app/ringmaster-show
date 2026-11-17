-- Run after both migrations inside the rollback-only synthetic fixture.
select is((select count(*)::int from public.show_report_artifacts a where a.id in(select id from internal_before) and is_current),0,'old internal reports are excluded from closeout');
select is((select count(*)::int from public.show_task_queue q where q.report_artifact_id in(select id from internal_before) and task_status in('queued','running','failed')),0,'old internal work cannot retry');
select is((select count(*)::int from public.show_report_artifacts a join internal_before b using(id) where a.storage_path is distinct from b.storage_path),0,'historical PDFs are preserved');
select is((select count(*)::int from public.show_report_artifacts a join retained_reports b using(id) where to_jsonb(a) is distinct from b.snapshot),0,'results, club, ARBA and standalone artifacts are unchanged');
select is((select count(*)::int from pg_proc p join original_privileges b using(oid) where p.proacl is distinct from b.proacl),0,'function access is unchanged');
select is((public.get_closeout_report_generation_progress('20000000-0000-0000-0000-000000000004',(select (payload->>'finalize_run_id')::uuid from checkin_test_run))->'artifact_counts'->>'total')::int,(select count(*)::int from public.show_report_artifacts where finalize_run_id=(select (payload->>'finalize_run_id')::uuid from checkin_test_run) and is_current and report_name <> 'arba_report'),'progress counts only remaining closeout reports');

select public.requeue_closeout_render_tasks_for_species('20000000-0000-0000-0000-000000000004',(select (payload->>'finalize_run_id')::uuid from checkin_test_run),(select payload->>'scope_key' from checkin_test_run),true,null);
select is((select count(*)::int from public.show_report_artifacts where id in(select id from internal_before) and is_current),0,'regenerate all does not restore internal reports');
select is((select count(*)::int from public.show_task_queue where report_artifact_id in(select id from internal_before) and task_status <> 'cancelled'),0,'regenerate all does not queue internal reports');
update public.shows set results_version=results_version+1 where id='20000000-0000-0000-0000-000000000004';
create temporary table new_internal_test_run as
select public.finalize_show_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000005']::uuid[],'Independent reports regression') payload;
create temporary view new_internal_test_artifacts as select * from public.show_report_artifacts where finalize_run_id=(select (payload->>'finalize_run_id')::uuid from new_internal_test_run);
select is((select count(*)::int from new_internal_test_artifacts where report_name in('unpaid_balances_report','paid_exhibitor_report','entered_exhibitors_contact_report','ribbon_payout_report','payback_report','judge_report','breed_judged_totals_report','checkin_sheet')),0,'new closeout excludes all seven internal reports and check-in');
select ok(exists(select 1 from new_internal_test_artifacts where report_name='exhibitor_report'),'exhibitor reports still generated');
select ok(exists(select 1 from new_internal_test_artifacts where report_name='legs'),'leg report still generated');
select ok(exists(select 1 from new_internal_test_artifacts where report_name='arba_report'),'ARBA report remains in its deferred workflow');
select is((select count(*)::int from public.show_task_queue where finalize_run_id=(select (payload->>'finalize_run_id')::uuid from new_internal_test_run) and task_type::text like '%email%'),0,'generation sends no email');
select * from finish();
rollback;
