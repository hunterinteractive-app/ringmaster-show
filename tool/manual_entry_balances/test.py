#!/usr/bin/env python3
"""Run isolated manual balance SQL tests using an existing local Supabase DB container.
Usage: python3 tool/manual_entry_balances/test.py CONTAINER
Creates and drops a separate database; never modifies the container's postgres DB.
"""
from pathlib import Path
import subprocess
import sys
import uuid

root = Path(__file__).resolve().parents[2]
container = sys.argv[1]
database = 'manual_balances_' + uuid.uuid4().hex[:12]

def sql(source):
    result = subprocess.run(
        ['docker', 'exec', '-i', container, 'psql', '-U', 'postgres',
         '-d', database, '-v', 'ON_ERROR_STOP=1', '-At'],
        input=source, text=True, capture_output=True, check=True)
    return result.stdout

subprocess.run(['docker', 'exec', container, 'createdb', '-U', 'postgres', database], check=True)
try:
    sql((root / 'supabase/tests/manual_entry_balances_fixture.sql').read_text())
    sql((root / 'supabase/migrations/20261112014121_maintain_manual_entry_balances.sql').read_text())
    report = (root / 'supabase/migrations/20260910213930_attribute_checkin_fees_to_report_sections.sql').read_text()
    marker = 'create or replace function public.report_show_exhibitor_balances_scoped('
    start = report.index(marker, report.index(marker) + len(marker))
    end = report.index('\n$$;', start) + len('\n$$;')
    sql(report[start:end])
    output = sql((root / 'supabase/tests/manual_entry_balances_test.sql').read_text())
    print(output)
    if 'not ok ' in output or '1..29' not in output:
        raise SystemExit('Regression tests failed or did not finish')
finally:
    subprocess.run(['docker', 'exec', container, 'dropdb', '-U', 'postgres', database], check=True)
