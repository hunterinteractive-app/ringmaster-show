#!/usr/bin/env python3
"""Isolated financial regression suite; never changes the local postgres DB."""
from pathlib import Path
import subprocess,sys,uuid
root=Path(__file__).resolve().parents[2]
container=sys.argv[1]
database='finance_'+uuid.uuid4().hex[:12]
def sql(text):
 r=subprocess.run(['docker','exec','-i',container,'psql','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-At'],input=text,text=True,capture_output=True)
 if r.returncode: print(r.stdout);print(r.stderr);raise RuntimeError('SQL failed')
 return r.stdout
subprocess.run(['docker','exec',container,'createdb','-U','postgres',database],check=True)
try:
 sql((root/'supabase/tests/manual_entry_balances_fixture.sql').read_text())
 sql('''alter table shows add primary key(id); alter table exhibitors add primary key(id);
 alter table show_payments add primary key(id); alter table show_payments alter id set default gen_random_uuid();
 alter table show_payments alter created_at set default now();
 create function auth.uid() returns uuid language sql as $$select (auth.jwt()->>'sub')::uuid$$;
 alter table entry_cart_items add cart_id uuid, add exhibitor_id uuid, add is_fur boolean,
 add is_show_addon_carrier boolean,add is_checkin_fee_carrier boolean,add is_exhibitor_fee_carrier boolean;
 create table show_payment_sessions(id uuid,cart_id uuid,status text,quote_snapshot jsonb,created_at timestamptz default now());
 create schema entry_refunds_private;
 create table entry_refunds_private.requests(show_id uuid,currency text,online_fee_cents integer,status text);
 create table show_checkin_audit_events(show_id uuid,exhibitor_id uuid,event_type text,actor_type text,actor_user_id uuid,details jsonb);
 ''')
 sql((root/'supabase/migrations/20261112014121_maintain_manual_entry_balances.sql').read_text())
 sql((root/'supabase/migrations/20261114040900_show_finances_payment_allocation.sql').read_text())
 sql((root/'supabase/migrations/20261114045659_preserve_entry_payment_provenance.sql').read_text())
 sql((root/'supabase/migrations/20261114051532_filter_zero_payment_history_allocations.sql').read_text())
 sql((root/'supabase/migrations/20261114051711_index_show_finance_exhibitors.sql').read_text())
 sql((root/'supabase/migrations/20261114054901_show_finance_summary_and_name_sort.sql').read_text())
 report=(root/'supabase/migrations/20260910213930_attribute_checkin_fees_to_report_sections.sql').read_text()
 marker='create or replace function public.report_show_exhibitor_balances_scoped('
 start=report.index(marker,report.index(marker)+len(marker));end=report.index('\n$$;',start)+len('\n$$;')
 sql(report[start:end])
 legacy=(root/'supabase/tests/manual_entry_balances_test.sql').read_text()
 # The new design intentionally materializes a single authoritative aggregate
 # for online-only exhibitors too. All existing financial expectations remain.
 legacy=legacy.replace("),0,'cart-only checkout retains existing path'", "),1,'cart-only checkout has one authoritative aggregate'")
 output=sql(legacy); print(output)
 if 'not ok ' in output or '1..29' not in output: raise RuntimeError('Legacy regressions failed')
 output=sql((root/'supabase/tests/show_finances_test.sql').read_text());print(output)
 if 'not ok ' in output or '1..' not in output: raise RuntimeError('Tests failed')
 output=sql((root/'supabase/tests/show_finance_summary_test.sql').read_text());print(output)
 if 'not ok ' in output or '1..' not in output: raise RuntimeError('Summary tests failed')
 from concurrency import run
 run(container,database)
finally:
 subprocess.run(['docker','exec',container,'dropdb','-U','postgres',database],check=True)
