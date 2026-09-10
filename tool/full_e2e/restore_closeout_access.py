"""Restore inspected historical manager policies used by closeout forms."""
import json
import sys
from local import Local,ROOT

def restore(lab):
    rows=json.loads((ROOT/'supabase/local/e2e_historical_closeout_policies.json').read_text())
    existing={(r['tablename'],r['policyname']) for r in lab.rows("select tablename,policyname from pg_policies where schemaname='public'")}
    statements=['begin;']
    existing_columns={r['column_name'] for r in lab.rows("select column_name from information_schema.columns where table_schema='public' and table_name='show_arba_report_details'")}
    for c in json.loads((ROOT/'supabase/local/e2e_historical_arba_nullability.json').read_text()):
        if c['is_nullable']=='YES' and c['column_name'] in existing_columns:
            statements.append(f"alter table show_arba_report_details alter column {c['column_name']} drop not null;")
    for p in rows:
        if not p['policyname'].startswith('Show managers ') or (p['tablename'],p['policyname']) in existing:continue
        statement=f"create policy \"{p['policyname']}\" on public.{p['tablename']} for {p['cmd']} to authenticated"
        if p['qual']:statement+=' using ('+p['qual']+')'
        if p['with_check']:statement+=' with check ('+p['with_check']+')'
        statements.append(statement+';')
    statements+=['grant select,insert,update on show_arba_report_details,show_closeout_state to authenticated;',
                 'alter table show_arba_report_details enable row level security;',
                 'alter table show_closeout_state enable row level security;','commit;']
    lab.sql('\n'.join(statements))

if __name__=='__main__':restore(Local(sys.argv[1]))
