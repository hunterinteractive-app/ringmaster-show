#!/usr/bin/env python3
"""Run against the synthetic full-e2e stack only; every change is rolled back."""
from pathlib import Path
import subprocess, sys
root=Path(__file__).resolve().parents[2]
container=sys.argv[1]
if not container.startswith('supabase_db_ringmaster-show-full-e2e'):
    raise SystemExit('Only the local full-e2e fixture is supported')
sql='begin;\n'+(root/'supabase/migrations/20261114153728_restore_public_breed_qr_results.sql').read_text()
sql+='\n'+(root/'supabase/tests/qr_results_test.sql').read_text()+'\nrollback;'
p=subprocess.run(['docker','exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-At'],input=sql,text=True,capture_output=True)
print(p.stdout);print(p.stderr)
raise SystemExit(p.returncode)
