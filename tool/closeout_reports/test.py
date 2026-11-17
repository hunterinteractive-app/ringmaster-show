#!/usr/bin/env python3
"""Test closeout manifest changes using the local synthetic fixture, then roll back."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
container = sys.argv[1]
if not container.startswith('supabase_db_ringmaster-show-full-e2e'):
    raise SystemExit('Only the local full-e2e fixture is supported')
migration = root / 'supabase/migrations/20261117232757_remove_checkin_sheets_from_closeout.sql'
setup = (root / 'supabase/tests/closeout_without_checkin_setup.sql').read_text()
test = (root / 'supabase/tests/closeout_without_checkin_test.sql').read_text()
sql = setup + '\n' + migration.read_text().replace('begin;\n', '', 1).removesuffix('commit;\n') + '\n' + test
if '--internal' in sys.argv:
    internal = root / 'supabase/migrations/20261117234756_move_internal_closeout_reports_to_on_demand.sql'
    setup = setup.replace('select plan(15);', 'select no_plan();')
    setup += """
create temporary table internal_before as select * from public.show_report_artifacts
where finalize_run_id=(select (payload->>'finalize_run_id')::uuid from checkin_test_run)
  and report_name in('unpaid_balances_report','paid_exhibitor_report','entered_exhibitors_contact_report','ribbon_payout_report','payback_report','judge_report','breed_judged_totals_report');
select is((select count(*)::int from internal_before),7,'fixture includes all seven internal reports');
insert into public.show_report_artifacts(show_id,report_name,artifact_status,is_current,scope_key,section_ids,metadata)
select show_id,report_name,'generated',true,'operational',section_ids,'{"operational_report":true}'::jsonb
from internal_before where report_name='judge_report';
create temporary table retained_reports as select id,to_jsonb(a) snapshot from public.show_report_artifacts a
where id not in(select id from internal_before) and report_name <> 'checkin_sheet';
"""
    sql = setup + '\n' + migration.read_text().replace('begin;\n', '', 1).removesuffix('commit;\n')
    sql += '\n' + internal.read_text().replace('begin;\n', '', 1).removesuffix('commit;\n')
    sql += '\n' + (root / 'supabase/tests/closeout_internal_reports_test.sql').read_text()
result = subprocess.run(['docker', 'exec', '-i', container, 'psql', '-U',
    'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At'],
    input=sql, text=True, capture_output=True)
print(result.stdout)
print(result.stderr)
if result.returncode or 'not ok ' in result.stdout:
    raise SystemExit(result.returncode or 1)
