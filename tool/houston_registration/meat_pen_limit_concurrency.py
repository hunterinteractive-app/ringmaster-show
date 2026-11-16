"""Prove competing carts cannot oversubscribe one exhibitor's two-pen limit."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
from threading import Barrier


def run(container, database):
    def execute(query, checked=True):
        result = subprocess.run(
            ['docker', 'exec', '-i', container, 'sh', '-c',
             'export PGPASSWORD="$POSTGRES_PASSWORD"; exec "$@"',
             'sh', 'psql', '-U', 'supabase_admin', '-d', database,
             '-v', 'ON_ERROR_STOP=1', '-At'],
            input=query, text=True, capture_output=True, timeout=30)
        if checked and result.returncode:
            raise RuntimeError(result.stderr)
        return result

    root = Path(__file__).resolve().parents[2]
    fixture = (root / 'supabase/tests/houston_meat_pen_entry_limit.sql').read_text()
    execute(fixture.split('-- Test assertions')[0] + '\ncommit;')
    execute("select meat_limit_test.actor('buyer'); "
            "select meat_limit_test.add('c1','race'); "
            "select meat_limit_test.checkout('c1'); "
            "select meat_limit_test.add('race1','race'); "
            "select meat_limit_test.add('race2','race');")

    def race(queries):
        barrier = Barrier(2)

        def attempt(query):
            barrier.wait(timeout=10)
            return execute("begin; set local lock_timeout='8s'; " + query +
                           "select pg_sleep(0.2); commit;", checked=False)

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, queries))
        assert sum(r.returncode == 0 for r in results) == 1, [r.stderr for r in results]
        assert 'maximum of 2 meat pen entries per exhibitor' in next(
            r.stderr for r in results if r.returncode)

    race([f"select meat_limit_test.checkout('race{n}');" for n in [1, 2]])
    count = execute("select count(*) from public.entries "
                    "where exhibitor_id=meat_limit_test.id('race');").stdout.strip()
    assert count == '2', count
    print('PASS concurrent submissions retain exactly two pens for one exhibitor')

    execute("update public.show_section_fee_settings set fee_per_entry=10 "
            "where section_id=meat_limit_test.id('section'); "
            "insert into public.show_payment_settings(show_id,stripe_enabled,square_enabled,paypal_enabled,default_online_provider) "
            "values(meat_limit_test.id('show'),false,true,false,'square'); "
            "insert into public.show_payment_account_links(show_id,provider,status,provider_account_id,provider_location_id) "
            "values(meat_limit_test.id('show'),'square','active','LOCAL-LIMIT','LOCAL-LOCATION'); "
            "select meat_limit_test.actor('buyer'); "
            "select meat_limit_test.add('paid1','paid'); select meat_limit_test.add('paid1','paid'); "
            "select meat_limit_test.add('paid2','paid'); select meat_limit_test.add('paid2','paid');")
    race(["select set_config('request.jwt.claims',jsonb_build_object('sub',"
          "meat_limit_test.id('buyer'),'role','service_role')::text,true); "
          f"select public.create_payment_quote_attempt(meat_limit_test.id('paid{n}'),"
          "meat_limit_test.id('buyer'),'square',0.03,0.029,30);" for n in [1, 2]])
    count = execute("select count(*) from public.show_payment_sessions "
                    "where show_id=meat_limit_test.id('show');").stdout.strip()
    assert count == '1', count
    print('PASS competing payment checkouts create only one two-pen reservation')
