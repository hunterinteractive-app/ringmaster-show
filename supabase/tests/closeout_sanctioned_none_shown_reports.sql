-- Sanctioned breeds remain reportable without entries, on initial finalize
-- and rebuild. No email is sent; all fixture changes are rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(19);
insert into public.breeds(name,species) values ('Czech Frosty','rabbit');
insert into public.show_sections(id,show_id,kind,letter,judging_date,display_name)
values ('21000000-0000-0000-0000-000000000099','20000000-0000-0000-0000-000000000004','open','Z','2026-08-04','None shown test');
insert into public.show_sanctions(id,show_id,section_id,breed_name,club_name,sanction_number,sanctioning_body,sweepstakes_email,request_status)
values
('a6000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000099','Czech Frosty','Synthetic Frosty Club','CF-123','NATIONAL CLUB','club@example.test','received'),
('a6000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000099','Dutch','Pending Dutch Club',null,'NATIONAL CLUB','pending@example.test','secretary_requested'),
('a6000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000099','Cavy','Synthetic ACBA','CV-123','NATIONAL CLUB','cavy@example.test','received');
select results_eq($$select species from public.closeout_sanction_report_species('a6000000-0000-0000-0000-000000000001')$$,$$values ('rabbit'::text)$$,'confirmed rabbit sanction yields a report species without entries');
select is((select count(*)::int from public.closeout_sanction_report_species('a6000000-0000-0000-0000-000000000002')),0,'pending requests do not create false none-shown reports');
select results_eq($$select species from public.closeout_sanction_report_species('a6000000-0000-0000-0000-000000000003')$$,$$values ('cavy'::text)$$,'aggregate Cavy sanction works without catalog entry or shown animals');
insert into public.sweepstakes_json_export_opt_ins(club_name,breed_name,enabled) values ('Synthetic Frosty Club','Czech Frosty',true);
create temporary table none_shown_run as
select public.finalize_show_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000099']::uuid[],'None shown test') response;
create temporary view none_shown_artifacts as select a.* from public.show_report_artifacts a join public.show_finalize_runs f on f.id=a.finalize_run_id where f.show_id='20000000-0000-0000-0000-000000000004' and f.scope_label='None shown test' and a.is_current and a.report_name in ('sweepstakes_report','breed_results_detail_report');
select is((select count(*)::int from none_shown_artifacts),4,'initial finalization generates both club reports for both confirmed sanctions');
select is((select count(*)::int from none_shown_artifacts where metadata->>'club_name'='Synthetic Frosty Club'),2,'Czech Frosty has sweepstakes and breed detail reports');
select is((select count(*)::int from none_shown_artifacts where metadata->>'sanction_number'='CF-123' and metadata->>'sweepstakes_email'='club@example.test'),2,'sanction number and recipient are preserved');
select is((select count(*)::int from none_shown_artifacts where metadata->>'show_letter'='Z' and metadata->>'scope'='OPEN'),4,'exact section scope is preserved');
select is((select count(*)::int from public.show_task_queue q where q.payload->>'artifact_id' in(select id::text from none_shown_artifacts) and q.task_type='render_report'),4,'initial finalization queues all four render jobs');
select is((select count(*)::int from public.show_task_queue q where q.finalize_run_id in(select finalize_run_id from none_shown_artifacts) and q.task_type::text like '%email%'),0,'generation does not queue email');
select public.rebuild_closeout_club_report_manifest('20000000-0000-0000-0000-000000000004',finalize_run_id,metadata->>'run_scope_key',null) from none_shown_artifacts limit 1;
select is((select count(*)::int from none_shown_artifacts),4,'rebuilding retains none-shown artifacts without duplicates');
select is((select count(distinct artifact_key)::int from none_shown_artifacts),4,'all four canonical identities are distinct');
select is((select count(*)::int from public.show_report_artifacts where finalize_run_id in(select finalize_run_id from none_shown_artifacts) and is_current and report_name='sweepstakes_json_export'),1,'manifest rebuild preserves opted-in JSON companion');
select is((select count(*)::int from public.show_report_artifacts where finalize_run_id in(select finalize_run_id from none_shown_artifacts) and is_current and report_name in ('details_by_breed','exh_by_breed')),2,'manifest rebuild preserves both ACBA companions');
-- Confirming a previously requested sanction must be discovered on reuse too.
update public.show_sanctions set sanction_number='DU-123', request_status='received' where id='a6000000-0000-0000-0000-000000000002';
select public.finalize_show_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000099']::uuid[],'None shown test');
select is((select count(*)::int from none_shown_artifacts),6,'reusing finalization discovers newly confirmed no-show sanctions');
select is((select count(*)::int from none_shown_artifacts where metadata->>'breed_name'='Dutch'),2,'new sanctioned breed is selectable for both reports');
select is((select count(*)::int from none_shown_artifacts where metadata->>'breed_name'='Mini Rex'),0,'other sections sanctions do not leak into the selected section');
select ok(not has_function_privilege('anon','public.closeout_sanction_report_species(uuid)','EXECUTE'),'no new anonymous RPC access');
select ok(not (select prosecdef from pg_proc where oid='public.closeout_sanction_report_species(uuid)'::regprocedure),'species helper respects invoker row access');
delete from public.show_sanctions where id='a6000000-0000-0000-0000-000000000001';
select public.rebuild_closeout_club_report_manifest('20000000-0000-0000-0000-000000000004',finalize_run_id,metadata->>'run_scope_key',null) from none_shown_artifacts limit 1;
select is((select count(*)::int from public.show_report_artifacts where finalize_run_id in(select finalize_run_id from none_shown_artifacts) and is_current and metadata->>'club_name'='Synthetic Frosty Club'),0,'removing a sanction retires its PDFs and JSON companion together');
select * from finish();
rollback;
