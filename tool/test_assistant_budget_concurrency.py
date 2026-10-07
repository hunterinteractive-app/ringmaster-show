"""Exercise the actual metering migration in an isolated local Docker database.

Usage: python3 tool/test_assistant_budget_concurrency.py <local-postgres-container>
Creates a uniquely named test database, never changes the source database, and
removes only that new database afterward. No provider/API calls are made.
"""
import concurrent.futures
from pathlib import Path
import subprocess
import sys
import uuid

container = sys.argv[1]
if not container.startswith('supabase_db_'):
    raise SystemExit('Use a local supabase_db_ Docker container.')
database = 'assistant_budget_test_' + uuid.uuid4().hex[:12]

def sql(statement, db=database):
    result = subprocess.run(
        ['docker', 'exec', '-i', container, 'psql', '-U', 'postgres', '-d', db,
         '-v', 'ON_ERROR_STOP=1', '-Atq'], input=statement, text=True,
        capture_output=True, check=True,
    )
    return result.stdout

migration = Path(__file__).resolve().parents[1] / 'supabase/migrations/20260919014108_add_read_only_show_assistant.sql'
sql(f'create database {database};', 'postgres')
try:
    sql("""
      create schema auth;
      create function auth.uid() returns uuid language sql as $$select null::uuid$$;
      create function public.is_super_admin(uuid) returns boolean language sql as $$select false$$;
    """ + migration.read_text().split('-- These read functions')[0] + """
      update assistant_private.settings set enabled=true,monthly_budget_microusd=60000;
    """)
    def reserve(_):
        actor, request, conversation = (str(uuid.uuid4()) for _ in range(3))
        return sql(f"""begin; set local role service_role;
          select public.assistant_reserve('{actor}','{request}','{conversation}','help');
          select pg_sleep(0.2); commit;""")
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(reserve, range(8)))
    assert sum('"allowed": true' in r for r in results) == 1, results
    assert sum('"reason": "budget"' in r for r in results) == 7, results
    assert sql('select sum(charged_microusd) from assistant_private.usage;').strip() == '60000'
    print('PASS: 8 simultaneous requests; exactly one reservation, 7 budget refusals, no overspend.')
finally:
    sql(f'drop database {database};', 'postgres')
