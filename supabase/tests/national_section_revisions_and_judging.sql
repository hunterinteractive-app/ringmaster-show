create extension if not exists pgtap with schema extensions;
begin;
select plan(14);
insert into public.show_sections(id,show_id,kind,letter,display_name,is_enabled,sort_order)
values('21000000-0000-0000-0000-000000000098','20000000-0000-0000-0000-000000000004','youth','Z','Revision test',true,98);
create temporary table revision_before as select
 public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000004'::uuid]) open,
 public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000098'::uuid]) youth;
update public.entries set tattoo=tattoo || '-SECTION-TEST'
where id=(select id from public.entries where show_id='20000000-0000-0000-0000-000000000004' order by id limit 1);
select isnt(public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000004'::uuid]),(select open from revision_before),'edits invalidate their own section');
select is(public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000098'::uuid]),(select youth from revision_before),'edits do not invalidate another section');
update revision_before set open=public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000004'::uuid]);
update public.entries set section_id='21000000-0000-0000-0000-000000000098'
where id=(select id from public.entries where show_id='20000000-0000-0000-0000-000000000004' order by id limit 1);
select isnt(public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000004'::uuid]),(select open from revision_before),'moving an entry invalidates its old section');
select isnt(public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000098'::uuid]),(select youth from revision_before),'moving an entry invalidates its new section');
update revision_before set youth=public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000098'::uuid]);
update public.exhibitors set display_name=display_name
where id=(select exhibitor_id from public.entries where show_id='20000000-0000-0000-0000-000000000004' limit 1);
select isnt(public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000098'::uuid]),(select youth from revision_before),'shared exhibitor changes invalidate cached names');
select is(public.get_report_result_revision_scoped('20000000-0000-0000-0000-000000000004'),public.get_report_result_revision('20000000-0000-0000-0000-000000000004'),'whole-show snapshots retain the complete revision');
select ok(not has_function_privilege('authenticated','public.get_report_result_revision_scoped(uuid,uuid[])','execute'),'scoped revisions remain worker-only');
select ok(not has_function_privilege('anon','public.get_judging_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer)','execute'),'anonymous callers cannot load staff results');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
create temporary table hydrated as select r from public.get_judging_entry_rows_page('20000000-0000-0000-0000-000000000004',p_page_size=>2) r;
select is((select count(*)::int from hydrated),2,'hydrated staff results remain bounded');
select ok((select bool_and(r->>'species'=e.species::text) from hydrated join public.entries e on e.id=(r->>'entry_id')::uuid),'species comes from the entry, including shared breed names');
select ok((select bool_and(jsonb_typeof(r->'_awards')='array' and r ? 'coop_number') from hydrated),'awards and coop labels arrive with each page');
select set_config('request.jwt.claims','{"role":"authenticated","sub":"ffffffff-ffff-ffff-ffff-ffffffffffff"}',true);
set local role authenticated;
select throws_ok($q$select public.get_judging_entry_rows_page('20000000-0000-0000-0000-000000000004')$q$,'42501','You do not have access to this show','another account cannot load staff results');
reset role;
insert into auth.users(id,aud,role,email,encrypted_password)
values ('60000000-0000-0000-0000-000000000098','authenticated','authenticated',
        'local-results-clerk@example.invalid','');
insert into public.role_assignments(show_id,user_id,role)
values ('20000000-0000-0000-0000-000000000004',
        '60000000-0000-0000-0000-000000000098','reporting_clerk');
select set_config('request.jwt.claims','{"role":"authenticated","sub":"60000000-0000-0000-0000-000000000098"}',true);
set local role authenticated;
select ok(not public.user_can_manage_show_settings('20000000-0000-0000-0000-000000000004'),'reporting clerk has no settings permission');
select is((select count(*)::int from public.get_judging_entry_rows_page('20000000-0000-0000-0000-000000000004',p_page_size=>2)),2,'reporting clerk can load a bounded judging page');
reset role;
select * from finish();
rollback;
