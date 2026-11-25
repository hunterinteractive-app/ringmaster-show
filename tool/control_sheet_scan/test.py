#!/usr/bin/env python3
"""Exercise the scan batch transaction against the local synthetic full-e2e DB."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
container = sys.argv[1]
if not container.startswith('supabase_db_ringmaster-show-full-e2e'):
    raise SystemExit('Only the local full-e2e fixture is supported')
sql = 'begin;\n'
sql += (root / 'supabase/migrations/20261125042825_save_reviewed_control_sheet_results.sql').read_text()
sql += '\n' + (root / 'supabase/tests/control_sheet_scan_save_test.sql').read_text()
sql += '\nrollback;'
result = subprocess.run(
    ['docker', 'exec', '-i', container, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At'],
    input=sql, text=True, capture_output=True,
)
print(result.stdout)
print(result.stderr)
raise SystemExit(result.returncode)
