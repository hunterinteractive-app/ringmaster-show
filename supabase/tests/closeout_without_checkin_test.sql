select is((select count(*)::int from public.show_report_artifacts where id in(select id from old_checkins) and is_current),0,'legacy check-ins no longer block current closeout');
select is((select count(*)::int from public.show_task_queue where report_artifact_id in(select id from old_checkins) and task_status <> 'cancelled'),0,'failed check-in jobs are cancelled');
select is((select count(*)::int from public.show_report_artifacts a join old_checkins old using(id) where a.storage_path is distinct from old.storage_path),0,'stored PDF locations are retained');
select is((select count(*)::int from public.show_task_queue where report_artifact_id in(select id from old_checkins) and last_error='Synthetic database timeout'),(select count(*)::int from old_checkins),'failure diagnostics are retained');
select is((select count(*)::int from public.show_report_artifacts a join other_artifacts old using(id) where to_jsonb(a) is distinct from old.snapshot),0,'all non-check-in artifacts are unchanged');
select is((select count(*)::int from pg_proc p join original_privileges old using(oid) where p.proacl is distinct from old.proacl),0,'function privileges are unchanged');
select is((public.get_closeout_report_generation_progress('20000000-0000-0000-0000-000000000004',(select (payload->>'finalize_run_id')::uuid from checkin_test_run))->'artifact_counts'->>'failed')::int,0,'progress excludes retired failures');

select public.requeue_closeout_render_tasks_for_species(
  '20000000-0000-0000-0000-000000000004',
  (select (payload->>'finalize_run_id')::uuid from checkin_test_run),
  (select payload->>'scope_key' from checkin_test_run), true, 'rabbit');
select is((select count(*)::int from public.show_report_artifacts where id in(select id from old_checkins) and is_current),0,'regenerate all does not revive retired sheets');
select is((select count(*)::int from public.show_task_queue where report_artifact_id in(select id from old_checkins) and task_status <> 'cancelled'),0,'regenerate all does not requeue retired jobs');

update public.shows set results_version=results_version+1
where id='20000000-0000-0000-0000-000000000004';
create temporary table new_checkin_test_run as
select public.finalize_show_scoped('20000000-0000-0000-0000-000000000004',
  array['21000000-0000-0000-0000-000000000005']::uuid[], 'Check-in exclusion regression') payload;
create temporary view new_closeout_artifacts as
select * from public.show_report_artifacts
where finalize_run_id=(select (payload->>'finalize_run_id')::uuid from new_checkin_test_run);
select is((select count(*)::int from new_closeout_artifacts where report_name='checkin_sheet'),0,'new finalization creates no check-in artifacts');
select ok((select count(*)>0 from new_closeout_artifacts where report_name='exhibitor_report'),'exhibitor results remain included');
select is((select count(distinct report_name)::int from new_closeout_artifacts where report_name in ('unpaid_balances_report','paid_exhibitor_report','entered_exhibitors_contact_report','ribbon_payout_report','payback_report','judge_report','breed_judged_totals_report')),7,'all seven internal closeout reports remain included');
select is((select count(*)::int from public.show_task_queue where finalize_run_id=(select (payload->>'finalize_run_id')::uuid from new_checkin_test_run) and task_type::text like '%email%'),0,'generation sends no emails');
select ok(exists(select 1 from public.report_checkin_entries('20000000-0000-0000-0000-000000000004',false,'21000000-0000-0000-0000-000000000005')),'pre-show check-in data remains available');
select * from finish();
rollback;
