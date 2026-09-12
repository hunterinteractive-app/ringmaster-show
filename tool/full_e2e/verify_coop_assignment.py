"""Compare optimized coop assignment with the historical function, then rollback.

Requires a populated, disposable local event and an admin from its saved staff.
No event data or function changes survive the test transaction.
"""
import argparse
import json
from pathlib import Path
import subprocess
from local import Local, ROOT, SHOW

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('workspace');p.add_argument('event',type=Path);p.add_argument('output',type=Path)
args=p.parse_args();lab=Local(args.workspace);out=args.output;out.mkdir(parents=True,exist_ok=False)
admin=next(p for p in json.loads((args.event/'.event-staff.json').read_text()) if p['role']=='admin')
original=lab.sql("select pg_get_functiondef('public.assign_show_coop_numbers(uuid,text,boolean)'::regprocedure)")
assert 'where p_overwrite_existing\n     or not exists (' in original
before=lab.rows(f"select * from show_animal_coop_numbers where show_id='{SHOW}' order by animal_id,scope")
assert not before,'This comparison expects the stopped preprint fixture'
claims=json.dumps(dict(sub=admin['user_id'],role='authenticated'))
migration=(ROOT/'supabase/migrations/20260912125700_optimize_coop_assignment_existing_lookup.sql').read_text()
script=f"""
begin;
set local statement_timeout='60s';
set local request.jwt.claims='{claims}';
create temporary table coop_function_metadata as select proowner,proacl,prosecdef,proconfig from pg_proc where oid='public.assign_show_coop_numbers(uuid,text,boolean)'::regprocedure;
set local role authenticated;
select public.assign_show_coop_numbers('{SHOW}','separate',false);
reset role;
create temporary table expected_separate as select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}';
set local role authenticated;
select public.assign_show_coop_numbers('{SHOW}','combined',false);
reset role;
create temporary table expected_combined as select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}';
delete from show_animal_coop_numbers where show_id='{SHOW}';
{migration}
-- Reapplying must preserve the same definition and permissions.
{migration}
do $check$ begin
  assert not exists(select proowner,proacl,prosecdef,proconfig from pg_proc where oid='public.assign_show_coop_numbers(uuid,text,boolean)'::regprocedure except select * from coop_function_metadata), 'Function permissions changed';
end $check$;
set local statement_timeout='8s';
set local role authenticated;
select public.assign_show_coop_numbers('{SHOW}','separate',false);
reset role;
do $check$ begin
  assert not exists((select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}' except select * from expected_separate) union all (select * from expected_separate except select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}')), 'Separate assignments changed';
end $check$;
create temporary table manual_target as select animal_id,scope from show_animal_coop_numbers where show_id='{SHOW}' order by animal_id,scope limit 1;
update show_animal_coop_numbers c set coop_number='MANUAL-REHEARSAL',is_manual=true from manual_target m where c.show_id='{SHOW}' and c.animal_id=m.animal_id and c.scope=m.scope;
update show_animal_coop_numbers set coop_number='' where show_id='{SHOW}' and animal_id=(select animal_id from expected_separate order by animal_id offset 1 limit 1);
set local role authenticated;
do $check$ begin
  assert public.assign_show_coop_numbers('{SHOW}','separate',false)=1, 'Only the blank assignment should be filled';
  assert public.assign_show_coop_numbers('{SHOW}','separate',false)=0, 'An identical retry should not rewrite assignments';
  assert public.assign_show_coop_numbers('{SHOW}','separate',null)=0, 'A NULL overwrite flag must preserve existing assignments';
end $check$;
reset role;
do $check$ begin
  assert exists(select 1 from show_animal_coop_numbers c join manual_target m using(animal_id,scope) where c.show_id='{SHOW}' and c.coop_number='MANUAL-REHEARSAL' and c.is_manual), 'Manual assignment was overwritten';
end $check$;
set local role authenticated;
select public.assign_show_coop_numbers('{SHOW}','separate',true);
reset role;
do $check$ begin
  assert not exists((select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}' except select * from expected_separate) union all (select * from expected_separate except select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}')), 'Regeneration changed numbering';
end $check$;
set local role authenticated;
select public.assign_show_coop_numbers('{SHOW}','combined',false);
reset role;
do $check$ begin
  assert not exists((select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}' except select * from expected_combined) union all (select * from expected_combined except select animal_id,scope,breed_name,coop_number,is_manual from show_animal_coop_numbers where show_id='{SHOW}')), 'Combined assignments changed';
end $check$;
set local request.jwt.claims='{{"sub":"ffffffff-ffff-ffff-ffff-ffffffffffff","role":"authenticated"}}';
set local role authenticated;
do $check$ begin
  begin
    perform public.assign_show_coop_numbers('{SHOW}','separate',false);
    raise exception 'Unauthorized caller succeeded';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'Not authorized to assign coop numbers' then raise; end if;
  end;
end $check$;
reset role;
select json_build_object('separate_assignments',(select count(*) from expected_separate),'combined_assignments',(select count(*) from expected_combined),'status','passed');
rollback;
"""
(out/'test.sql').write_text(script)
with (out/'test.log').open('w') as log:
    result=subprocess.run(['docker','exec','-i',lab.container,'psql','-X','-At','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],input=script,text=True,stdout=log,stderr=subprocess.STDOUT)
unchanged=lab.sql("select pg_get_functiondef('public.assign_show_coop_numbers(uuid,text,boolean)'::regprocedure)")==original and lab.rows(f"select * from show_animal_coop_numbers where show_id='{SHOW}' order by animal_id,scope")==before
report=dict(status='passed' if result.returncode==0 and unchanged else 'failed',exit_code=result.returncode,original_data_and_function_preserved=unchanged,
    checks=['separate numbering matches historical','combined numbering matches historical','blank-only filling','retry preserves assignments','NULL flag preserves assignments','manual labels preserved','explicit regeneration','unrelated user denied','owner/ACL/security/search path preserved','migration idempotent'],candidate_statement_timeout_seconds=8)
(out/'summary.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
if report['status']!='passed':raise SystemExit(1)
