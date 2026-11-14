-- Synthetic fixture, enclosed by the runner's rollback transaction.
create function pg_temp.check_qr(ok boolean,label text) returns text language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; return 'PASS: '||label; end $$;
create function pg_temp.qr_error(query text,expected text) returns boolean language plpgsql as $$
begin execute query; return false; exception when others then
 if position(expected in sqlerrm)>0 then return true; end if; raise; end $$;
update public.shows set is_published=true,is_locked=false where id='20000000-0000-0000-0000-000000000004';
update public.show_sections set is_enabled=true where show_id='20000000-0000-0000-0000-000000000004';
delete from public.entry_awards where show_id='20000000-0000-0000-0000-000000000004';
delete from public.show_result_entry_locks where show_id='20000000-0000-0000-0000-000000000004';
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
select pg_temp.check_qr(not (get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex')->>'locked')::boolean,'anonymous QR opens without account');
select pg_temp.check_qr(count(*)=2,'anonymous read scoped to breed and section') from get_qr_results_entry_rows('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004',' mini rex ');
select pg_temp.check_qr(not bool_or(r ? 'exhibitor_address_line1' or r ? 'result_entered_by_phone'),'no private contact information in public feed') from get_qr_results_entry_rows('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex') r;
select pg_temp.check_qr(count(*)=1,'cursor pagination returns remaining row') from get_qr_results_entry_rows('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex','40000000-0000-0000-0000-000000000001',1);
select pg_temp.check_qr(pg_temp.qr_error($q$select get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000001','Mini Rex')$q$,'unavailable'),'reject section from different show');
select pg_temp.check_qr(pg_temp.qr_error($q$select get_qr_results_context('20000000-0000-0000-0000-000000000004',null,'')$q$,'unavailable'),'no unscoped public query');
select pg_temp.check_qr(pg_temp.qr_error($q$select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001','1','Shown',null,true,false,null,'','3175550100',array[]::text[],true)$q$,'Writer name and phone'),'writer name required');
select pg_temp.check_qr(pg_temp.qr_error($q$select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001','1','Shown',null,true,false,null,'QR Test','',array[]::text[],true)$q$,'Writer name and phone'),'writer phone required');
select pg_temp.check_qr(pg_temp.qr_error($q$select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001','1','Shown',null,true,false,null,'QR Test','3175550100',array[]::text[],false)$q$,'permission'),'cannot bypass QR lock by claiming staff mode');
select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001','1','Shown',null,true,false,null,'QR Test','3175550100',array['BOB'],true);
select pg_temp.check_qr((get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex')->>'lock_starts_at')::timestamptz between now()+interval '19 minutes' and clock_timestamp()+interval '20 minutes','BOB starts 20-minute clock');
select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000002','1','Shown',null,true,false,null,'QR Test','3175550100',array['BOSB'],true);
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
select pg_temp.check_qr(result_entered_by_name='QR Test' and result_entered_by_phone='3175550100','writer attribution saved') from public.entries where id='40000000-0000-0000-0000-000000000001';
create temp table qr_deadline as select lock_starts_at from public.show_result_entry_locks where show_id='20000000-0000-0000-0000-000000000004' and breed_id='Mini Rex';
grant select on qr_deadline to anon;
set local role anon;
select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001','1','Shown',null,true,false,null,'QR Test','3175550100',array[]::text[],true);
select pg_temp.check_qr((get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex')->>'lock_starts_at')::timestamptz=(select lock_starts_at from qr_deadline),'removing BOB does not reset timer');
select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001','1','Shown',null,true,false,null,'QR Test','3175550100',array['BOB'],true);
select pg_temp.check_qr((get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex')->>'lock_starts_at')::timestamptz=(select lock_starts_at from qr_deadline),'resaving BOB does not restart timer');
select pg_temp.check_qr(pg_temp.qr_error($q$select set_qr_results_judge('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex',array['40000000-0000-0000-0000-000000000003']::uuid[],null,'QR Test','3175550100')$q$,'belong to this QR breed'),'bulk judge cannot cross breed or section');
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
update public.show_result_entry_locks set lock_starts_at=clock_timestamp()-interval '1 second' where show_id='20000000-0000-0000-0000-000000000004';
set local role anon;
select pg_temp.check_qr((get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex')->>'locked')::boolean,'expired QR shows locked');
select pg_temp.check_qr(pg_temp.qr_error($q$select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000002','2','Shown',null,true,false,null,'QR Test','3175550100',array[]::text[],true)$q$,'20-minute'),'stale open page cannot save after deadline');
select pg_temp.check_qr(pg_temp.qr_error($q$select set_qr_results_judge('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex',array['40000000-0000-0000-0000-000000000001']::uuid[],null,'QR Test','3175550100')$q$,'20-minute'),'bulk judge changes blocked after deadline');
select pg_temp.check_qr(pg_temp.qr_error($q$select apply_qr_entry_correction('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000002','tattoo','CORRECTED','test','QR Test','3175550100','1234')$q$,'20-minute'),'QR correction requests also honor deadline');
select pg_temp.check_qr(not (get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000005','Jersey Wooly')->>'locked')::boolean,'other breed and section remain open');
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}',true);
set local role authenticated;
select pg_temp.check_qr(count(*)=2,'signed-in nonstaff gets same QR access') from get_qr_results_entry_rows('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex');
select pg_temp.check_qr(pg_temp.qr_error($q$select * from save_results_entry('20000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000002','2','Shown',null,true,false,null,'QR Test','3175550100',array[]::text[],true)$q$,'20-minute'),'signed-in QR also honors deadline');
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
update shows set is_published=false where id='20000000-0000-0000-0000-000000000004';
set local role anon;
select pg_temp.check_qr(pg_temp.qr_error($q$select get_qr_results_context('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex')$q$,'unavailable'),'unpublished show denied');
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
update shows set is_published=true,is_locked=true where id='20000000-0000-0000-0000-000000000004';
set local role anon;
select pg_temp.check_qr(pg_temp.qr_error($q$select * from get_qr_results_entry_rows('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex')$q$,'unavailable'),'locked show denied');
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
-- Fur/Wool on the photographed sheet must also work without staff RPC access.
update shows set is_published=true,is_locked=false where id='95000000-0000-0000-0000-000000000001';
update show_sections set is_enabled=true where id='95100000-0000-0000-0000-000000000001';
delete from entry_awards where show_id='95000000-0000-0000-0000-000000000001';
delete from show_result_entry_locks where show_id='95000000-0000-0000-0000-000000000001';
update entries set placement='1',result_status='Shown',is_shown=true,is_disqualified=false,result_entered_at=now()
where id='8639f3c0-07ba-4e86-bbce-205b3caef184';
insert into entries(id,show_id,section_id,exhibitor_id,animal_id,breed,species,variety,class_name,sex,tattoo,is_fur,status)
select '40000000-0000-0000-0000-000000009999',show_id,section_id,exhibitor_id,animal_id,breed,species,'Colored','Fur / Wool',null,tattoo,true,status
from entries where id='8639f3c0-07ba-4e86-bbce-205b3caef184';
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
select pg_temp.check_qr(blocked_reason is null,'anonymous fur eligibility sees matching breed result') from get_qr_fur_eligibility('95000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000009999');
select * from save_results_entry('95000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000009999','1','Shown',null,true,false,null,'QR Test','3175550100',array[]::text[],true);
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
select pg_temp.check_qr(fur_placement=1 and placement is null,'fur placement stays separate from breed placement') from entries where id='40000000-0000-0000-0000-000000009999';
select pg_temp.check_qr(not exists(select 1 from show_result_entry_locks where show_id='95000000-0000-0000-0000-000000000001'),'ordinary fur save does not start BOB timer');
-- Authenticated staff keep their normal correction path after the QR closes.
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select * from save_results_entry('95000000-0000-0000-0000-000000000001','8639f3c0-07ba-4e86-bbce-205b3caef184','1','Shown',null,true,false,null,'Staff',null,array['BOB'],false);
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
update show_result_entry_locks set lock_starts_at=clock_timestamp()-interval '1 second' where show_id='95000000-0000-0000-0000-000000000001';
set local role service_role;
select * from save_results_entry('95000000-0000-0000-0000-000000000001','8639f3c0-07ba-4e86-bbce-205b3caef184','1','Shown',null,true,false,null,'Staff',null,array['BOB'],false);
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
select pg_temp.check_qr(result_entered_by_name='Staff','staff can still correct results after QR expires') from entries where id='8639f3c0-07ba-4e86-bbce-205b3caef184';
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
select pg_temp.check_qr(pg_temp.qr_error($q$select * from save_results_entry('95000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000009999','2','Shown',null,true,false,null,'QR Test','3175550100',array[]::text[],true)$q$,'20-minute'),'breed deadline also locks fur results');
-- Fire deferred validations before restoring the privileged test role.
set constraints all immediate;
set constraints all deferred;
reset role;
