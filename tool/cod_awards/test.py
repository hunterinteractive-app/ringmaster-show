#!/usr/bin/env python3
"""Exercise COD awards against synthetic local data; always roll back."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
container = sys.argv[1]
if not container.startswith('supabase_db_ringmaster-show-full-e2e'):
    raise SystemExit('Only the local full-e2e fixture is supported')
migrations = [
    '20261114173602_fix_deferred_qr_award_recognition.sql',
    '20261115161351_allow_cod_breed_awards.sql',
]
setup = '\n'.join((root / 'supabase/migrations' / name).read_text()
    .replace('begin;\n', '', 1).removesuffix('commit;\n') for name in migrations)
for name in ['cod_class_placement_only.sql', 'catalog_recognition_timelines.sql']:
    test = (root / 'supabase/tests' / name).read_text().replace('begin;\n', '', 1)
    result = subprocess.run(['docker', 'exec', '-i', container, 'psql', '-U',
        'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At'],
        input='begin;\n' + setup + '\n' + test, text=True, capture_output=True)
    print(name, result.stdout, result.stderr, sep='\n')
    if result.returncode or 'not ok ' in result.stdout:
        raise SystemExit(result.returncode or 1)
