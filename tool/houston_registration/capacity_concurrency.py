"""Race two local checkouts for the last shared category/session place."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
from threading import Barrier


def run(container, database):
    def execute(query, checked=True):
        result = subprocess.run(
            ['docker', 'exec', '-i', container, 'sh', '-c',
             'export PGPASSWORD="$POSTGRES_PASSWORD"; exec "$@"',
             'sh', 'psql', '-U', 'supabase_admin',
             '-d', database, '-v', 'ON_ERROR_STOP=1', '-At'],
            input=query, text=True, capture_output=True, timeout=30)
        if checked and result.returncode:
            raise RuntimeError(result.stderr)
        return result

    root = Path(__file__).resolve().parents[2]
    fixture = (root / 'supabase/tests/contest_category_session_capacity.sql').read_text()
    execute(fixture.split('-- Test assertions')[0] + '\ncommit;')
    execute('select capacity_test.enter(20); select capacity_test.enter(21);')
    barrier = Barrier(2)

    def checkout(n):
        barrier.wait(timeout=10)
        return execute(f"begin; set local lock_timeout='8s'; "
                       f"select capacity_test.checkout({n}); "
                       "select pg_sleep(0.2); commit;", checked=False)

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(checkout, [20, 21]))
    assert sum(r.returncode == 0 for r in results) == 1, [r.stderr for r in results]
    assert 'This category has reached its limit of 20' in next(
        r.stderr for r in results if r.returncode)
    count = execute("select count(*) from show_addons_private.selections x "
                    "join public.entry_carts c on c.id=x.cart_id "
                    "where x.offering_id=capacity_test.id('contest') "
                    "and c.status='submitted';").stdout.strip()
    assert count == '20', count
    print('PASS concurrent Rabbit/Cavy checkouts reserve exactly 20 shared places')
