#!/usr/bin/env python3
"""Exercise receipt preservation and RLS only in a new disposable LOCAL database."""
import argparse
from pathlib import Path
import subprocess
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--container', required=True)
args = parser.parse_args()
if not args.container.startswith('supabase_db_'):
    raise SystemExit('Select an existing local supabase_db_ container.')
root = Path(__file__).resolve().parents[2]
database = 'agreement_test_' + uuid.uuid4().hex[:12]

def command(*parts, input=None):
    result = subprocess.run(['docker', 'exec', '-i', args.container, *parts], input=input,
                            text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout

def sql(source):
    return command('psql', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-qAt', input=source)

command('createdb', '-U', 'postgres', database)
try:
    sql("""
    create schema auth;
    create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
    grant usage on schema auth,public to authenticated;
    grant execute on function auth.uid() to authenticated;
    create table public.profiles(user_id uuid primary key,display_name text not null default '',email text,
      accepted_terms_version text,accepted_terms_at timestamptz,
      accepted_privacy_version text,accepted_privacy_at timestamptz);
    alter table public.profiles enable row level security;
    grant select,insert,update on public.profiles to authenticated;
    create policy own_profiles on public.profiles to authenticated
      using(user_id=auth.uid()) with check(user_id=auth.uid());
    insert into public.profiles values
      ('aaaaaaaa-0000-4000-8000-000000000001','Keep my name','fixture@example.invalid',
       '2026-09','2026-09-01','2026-09','2026-09-01'),
      ('aaaaaaaa-0000-4000-8000-000000000002','Not agreed','other@example.invalid',null,null,null,null);
    """)
    for migration in (root/'supabase/migrations').glob('*_preserve_legal_acceptance.sql'):
        sql(migration.read_text())
    output=sql((root/'supabase/tests/legal_acceptance.sql').read_text())
    print(next(line for line in output.splitlines() if 'checks passed' in line))
finally:
    command('dropdb', '-U', 'postgres', '--force', database)
