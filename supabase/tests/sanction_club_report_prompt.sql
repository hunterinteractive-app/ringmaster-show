-- Uses the synthetic Mini Rex and Cavy show from the closeout test fixture.
begin;
set local search_path=public,extensions;
select plan(10);

create temporary table test_show as
select '20000000-0000-0000-0000-000000000004'::uuid as id,
  '21000000-0000-0000-0000-000000000004'::uuid as open_a,
  '21000000-0000-0000-0000-000000000005'::uuid as youth_a,
  gen_random_uuid() as run_id,
  (select id from auth.users order by id limit 1) as owner_id;
update public.shows set owner_user_id=test_show.owner_id,created_by=test_show.owner_id,is_locked=false
  from test_show where shows.id=test_show.id;
do $local_permissions$
begin
  if to_regclass('public.show_managers') is not null then
    insert into public.show_managers(show_id,user_id,can_finalize)
    select id,owner_id,true from test_show on conflict(show_id,user_id) do update
      set can_finalize=true;
  end if;
end;
$local_permissions$;
update public.show_sanctions set sanction_number='MR-NEW',sweepstakes_email='club@example.test'
  from test_show where show_id=test_show.id and section_id=test_show.open_a
    and club_name='Synthetic Mini Rex Club';
create temporary table test_changes as
select jsonb_object_agg(s.id,s.sanction_number) as numbers
  from public.show_sanctions s join test_show t on t.id=s.show_id
  where s.club_name='Synthetic Mini Rex Club';
insert into public.show_finalize_runs
  (id,show_id,run_status,results_version,scope_key,scope_label,section_ids,completed_at)
  select run_id,id,'completed',1,'sanction-test','Rabbit Open A + Youth A',
    array[open_a,youth_a],now() from test_show;

select set_config('request.jwt.claims',jsonb_build_object(
  'role','authenticated','sub',(select owner_id from test_show))::text,true);
select is((select count(*) from public.get_sanction_club_report_options(
  (select id from test_show),(select numbers from test_changes))),0::bigint,
  'a completed run alone does not mean PDFs were generated');

insert into public.show_report_artifacts
  (show_id,finalize_run_id,scope_key,artifact_key,section_ids,report_name,
   artifact_status,generated_at,metadata,is_current)
  select t.id,t.run_id,s.scope_key,s.artifact_key,s.section_ids,
    'arba_report','generated',now(),s.metadata,true
  from test_show t cross join lateral public.resolve_closeout_artifact_scope(
    t.id,t.run_id,'arba_report',
    jsonb_build_object('section_id',t.open_a,'scope','OPEN','show_letter','A','species','rabbit')
  ) s;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"ffffffff-ffff-ffff-ffff-ffffffffffff"}',true);
select is((select count(*) from public.get_sanction_club_report_options(
  (select id from test_show),(select numbers from test_changes))),0::bigint,
  'an unrelated user cannot discover report options');
select set_config('request.jwt.claims',jsonb_build_object(
  'role','authenticated','sub',(select owner_id from test_show))::text,true);
select results_eq(
  $$select club_name,recipient,report_count from public.get_sanction_club_report_options(
    (select id from test_show),(select numbers from test_changes))$$,
  $$values ('Synthetic Mini Rex Club'::text,'club@example.test'::text,2::bigint)$$,
  'the preview names the affected club and includes only its two PDFs');
select is((select count(*) from public.get_sanction_club_report_options(
  (select id from test_show),(select replace(numbers::text,'MR-NEW','MR-OLD')::jsonb from test_changes))),0::bigint,
  'a stale number cannot prepare the package');
select is((select count(*) from public.show_task_queue q join test_show t on t.run_id=q.finalize_run_id),
  0::bigint,'checking the option does not queue any tasks');

update public.shows set is_locked=true from test_show where shows.id=test_show.id;
create temporary table prepared as
select * from public.prepare_sanction_club_reports(
  (select id from test_show),(select numbers from test_changes),
  'Synthetic Mini Rex Club','club@example.test',2);
select is((select count(*) from prepared),2::bigint,'accepting the option queues two files');
select ok((select bool_and(a.section_ids=array[t.open_a] and a.metadata->>'sanction_number'='MR-NEW'
  and a.metadata->>'breed_name'='Mini Rex' and a.artifact_status='queued')
  from public.show_report_artifacts a join prepared p on p.artifact_id=a.id
  join test_show t on t.id=a.show_id),'only the affected breed and section are queued with the new number');
select ok((select shows.is_locked from public.shows join test_show t on t.id=shows.id),
  'preparing a correction preserves the existing show lock');
select results_eq(
  $$select * from public.prepare_sanction_club_reports(
    (select id from test_show),(select numbers from test_changes),
    'Synthetic Mini Rex Club','club@example.test',2) order by artifact_id$$,
  $$select * from prepared order by artifact_id$$,
  'retry reuses the queued generations');
select is((select count(*) from public.show_task_queue q join test_show t on t.run_id=q.finalize_run_id),
  2::bigint,'the retry does not queue duplicate tasks');
select * from finish();
rollback;
