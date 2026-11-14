#!/usr/bin/env python3
"""Disposable schema clone; no hosted access, emails, or provider payments."""
from pathlib import Path
import subprocess
import sys
import uuid

root = Path(__file__).resolve().parents[2]
container = sys.argv[1]
if not container.startswith('supabase_db_ringmaster-show-full-e2e'):
    raise SystemExit('Use the isolated local show rehearsal database container.')
database = 'houston_' + uuid.uuid4().hex[:12]

def command(args, **kwargs):
    kwargs.setdefault('input', '')
    return subprocess.run(['docker', 'exec', '-i', container, 'sh', '-c',
                          'export PGPASSWORD="$POSTGRES_PASSWORD"; exec "$@"',
                          'sh', *args], text=True, capture_output=True,
                          timeout=120, **kwargs)

def sql(source):
    result = command(['psql', '-U', 'supabase_admin', '-d', database,
                      '-v', 'ON_ERROR_STOP=1', '-At'], input=source)
    if result.returncode:
        print(result.stdout[-4000:])
        print(result.stderr[-4000:])
        raise RuntimeError('Local SQL failed')
    return result.stdout

command(['createdb', '-U', 'supabase_admin', database], check=True)
try:
    schema = command(['pg_dump', '-U', 'supabase_admin', '-d', 'postgres',
                      '--schema-only', '--no-owner', '--exclude-schema=cron',
                      '--exclude-schema=net'], check=True).stdout
    # Cron/HTTP workers are tied to the main local DB and must not be started
    # by this disposable checkout fixture.
    schema = '\n'.join(line for line in schema.splitlines()
                       if not ('EXTENSION' in line and
                               ('pg_cron' in line or 'pg_net' in line))
                       and not (line.startswith(('GRANT ', 'REVOKE '))
                                and any(s in line for s in
                                        ('cron.', 'net.', 'graphql_public.'))))
    sql('create schema cron; create schema net;\n' + schema)
    sql("insert into storage.buckets(id,name,public) values ('contest-submissions','contest-submissions',false);")
    sql("""insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
        values(gen_random_uuid(),'authenticated','authenticated',
        'local-deletion-fixture@example.invalid','{}','{}');""")
    for name in ['20261114074227_houston_checkout_requirements.sql',
                 '20261114074237_linked_youth_contest_registration.sql',
                 '20261114074909_guard_houston_school_household.sql',
                 '20261114092521_staff_exhibitor_school_information.sql']:
        sql((root / 'supabase/migrations' / name).read_text())
    for name in ['houston_registration.sql', 'show_contests_and_extras.sql',
                 'contest_expansion.sql', 'contest_registration_windows.sql',
                 'show_addon_deletion.sql']:
        output = sql((root / 'supabase/tests' / name).read_text())
        print(name + '\n' + output)
        if 'not ok ' in output or not (
                '1..' in output or 'Add-on deletion integration checks passed' in output):
            raise RuntimeError('Regression failed')
finally:
    command(['dropdb', '-U', 'supabase_admin', database], check=True)
