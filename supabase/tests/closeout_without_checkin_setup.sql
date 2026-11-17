begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local request.jwt.claims = '{"role":"service_role"}';
select plan(15);

-- The slim full-e2e fixture omits this production cached counter.
alter table public.show_closeout_state add column if not exists reports_generated_count integer default 0;
insert into public.exhibitors(id,first_name,last_name,display_name,email)
values ('f9000000-0000-0000-0000-000000000001','Synthetic','Exhibitor','Synthetic Exhibitor','closeout-regression@example.test');
update public.entries set exhibitor_id='f9000000-0000-0000-0000-000000000001'
where id='40000000-0000-0000-0000-000000000003';

-- Force a fresh old-style run with the synthetic Youth A exhibitor.
update public.shows set results_version = results_version + 1
where id = '20000000-0000-0000-0000-000000000004';
create temporary table checkin_test_run as
select public.finalize_show_scoped(
  '20000000-0000-0000-0000-000000000004',
  array['21000000-0000-0000-0000-000000000005']::uuid[],
  'Check-in exclusion regression'
) payload;
create temporary table old_checkins as
select * from public.show_report_artifacts
where finalize_run_id = (select (payload->>'finalize_run_id')::uuid from checkin_test_run)
  and report_name = 'checkin_sheet';
select ok((select count(*) > 0 from old_checkins), 'fixture includes legacy closeout check-in sheets');
update public.show_task_queue set task_status='failed', attempt_count=max_attempts,
  last_error='Synthetic database timeout'
where report_artifact_id in (select id from old_checkins);
update public.show_report_artifacts set artifact_status='failed'
where id in (select id from old_checkins);
create temporary table other_artifacts as
select id, to_jsonb(a) snapshot from public.show_report_artifacts a
where report_name <> 'checkin_sheet';
create temporary table original_privileges as
select oid, proacl from pg_proc where oid in (
  'public.finalize_show_scoped(uuid,uuid[],text,text)'::regprocedure,
  'public.enqueue_report_render_tasks(uuid,uuid,boolean)'::regprocedure
);
