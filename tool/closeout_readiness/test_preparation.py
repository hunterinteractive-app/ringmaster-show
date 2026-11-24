#!/usr/bin/env python3
"""Compare mixed-species sweepstakes before/after; roll back all local data."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
container = sys.argv[1]
if not container.startswith('supabase_db_ringmaster-show-full-e2e'):
    raise SystemExit('Only the local full-e2e fixture is supported')
before = """
begin;
create temporary table sweep_original_acl as
select proacl::text acl from pg_proc where oid='public.calculate_sweepstakes_for_show(uuid,text,text)'::regprocedure;
do $$ begin
 execute replace(pg_get_functiondef('public.calculate_sweepstakes_for_show(uuid,text,text)'::regprocedure),
   'public.calculate_sweepstakes_for_show(', 'pg_temp.sweepstakes_before(');
end $$;
"""
migration = (root / 'supabase/migrations/20261124203130_optimize_grand_finals_closeout_preparation.sql').read_text()
test = (root / 'supabase/tests/closeout_sweepstakes_single_cavy_pass.sql').read_text().replace('begin;\n','',1)
result = subprocess.run(['docker','exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-At'],
    input=before+migration+test,text=True,capture_output=True)
print(result.stdout)
print(result.stderr)
if result.returncode or 'not ok ' in result.stdout:
    raise SystemExit(result.returncode or 1)
