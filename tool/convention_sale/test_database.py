#!/usr/bin/env python3
"""Test the sale in a new disposable DB inside an existing LOCAL Supabase container.

Never accepts a hosted URL, copies production data, or changes the demo database.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--container', required=True)
args = parser.parse_args()
if not args.container.startswith('supabase_db_'):
    raise SystemExit('Select an existing local supabase_db_ container.')
root = Path(__file__).resolve().parents[2]
database = 'sale_test_' + uuid.uuid4().hex[:12]

def command(*parts, input=None):
    result = subprocess.run(['docker', 'exec', '-i', args.container, *parts], input=input,
                            text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout

def sql(source):
    return command('psql', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-qAt', input=source)

bootstrap = """
create schema auth;
create table auth.users(id uuid primary key,email text);
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid() to anon,authenticated,service_role;
create table public.super_admins(user_id uuid primary key);
create function public.is_super_admin(uid uuid) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.super_admins where user_id=uid); $$;
create table public.account_license_balances(
user_id uuid primary key references auth.users(id),purchased_show_days integer not null default 0,
consumed_show_days integer not null default 0,unlimited_access boolean not null default false,
unlimited_active boolean not null default false,unlimited_expires_at timestamptz,
can_change_host_club boolean not null default false,updated_at timestamptz not null default now(),
secretary_name text,secretary_email text,secretary_license_expires_at timestamptz);
create table public.processed_stripe_sessions(stripe_session_id text primary key,
processed_at timestamptz not null default now(),secretary_email text,matched_user_id uuid,matched_plan text);
grant select,insert,update on public.account_license_balances,public.processed_stripe_sessions to service_role;
"""

command('createdb', '-U', 'postgres', database)
try:
    sql(bootstrap)
    migration, = (root / 'supabase/migrations').glob('*_convention_token_sale.sql')
    sql(migration.read_text())
    output = sql((root / 'supabase/tests/convention_token_sale.sql').read_text())
    print(next(line for line in output.splitlines() if 'database checks passed' in line))
    buyer = 'cccccccc-0000-4000-8000-000000000001'
    sql(f"""insert into auth.users values('{buyer}','concurrent@example.invalid');
    update convention_sale_private.settings set enabled=true,starts_at=now()-interval '1 hour',ends_at=now()+interval '1 hour';""")
    claims = [str(uuid.uuid4()) for _ in range(8)]
    for claim in claims:
        sql(f"""select public.convention_sale_claim('{claim}','{buyer}','concurrent@example.invalid',
        'single_show',39.4861,-119.7911,10,now(),'price_test',5000,'usd',false);""")

    def fulfill(index):
        return sql(f"""select public.convention_sale_fulfill('{claims[index]}','cs_concurrent_{index}',
        'price_test',5000,'usd',false,now());""")

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(fulfill, list(range(8)) * 2))
    result = sql(f"""select purchased_show_days,(select count(*) from public.processed_stripe_sessions)
    from public.account_license_balances where user_id='{buyer}';""").strip()
    if result != '16|8':
        raise RuntimeError('Concurrent fulfillment lost or duplicated tokens: ' + result)
    print('16 concurrent deliveries: 8 purchases credited exactly once (16 tokens).')
finally:
    command('dropdb', '-U', 'postgres', '--force', database)
