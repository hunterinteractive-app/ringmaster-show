"""Restore the inspected historical profile contract for the local browser test."""
import json
import sys
from local import Local,ROOT

def restore(lab):
    contract=json.loads((ROOT/'supabase/local/e2e_historical_profiles.json').read_text())
    columns={r['column_name'] for r in lab.rows("select column_name from information_schema.columns where table_schema='public' and table_name='profiles'")}
    statements=['begin;']
    for c in contract['columns']:
        if c['column_name'] not in columns:
            assert c['data_type'] in ('uuid','text','boolean','timestamp with time zone')
            default=' default '+c['column_default'] if c['column_default'] else ''
            statements.append(f"alter table profiles add column {c['column_name']} {c['data_type']}{default};")
    pk=lab.rows("select pg_get_constraintdef(oid) definition from pg_constraint where conrelid='public.profiles'::regclass and contype='p'")
    if pk and pk[0]['definition']=='PRIMARY KEY (id)':
        statements += ['update profiles set user_id=id where user_id is null;',
            'alter table profiles drop constraint profiles_pkey;',
            'alter table profiles alter column id drop not null;',
            'alter table profiles add constraint profiles_pkey primary key(user_id);']
    constraints={r['conname'] for r in lab.rows("select conname from pg_constraint where conrelid='public.profiles'::regclass")}
    for c in contract['constraints']:
        if c['conname'] not in constraints:statements.append(f"alter table profiles add constraint {c['conname']} {c['definition']};")
    policies={r['policyname'] for r in lab.rows("select policyname from pg_policies where schemaname='public' and tablename='profiles'")}
    for p in contract['policies']:
        if p['policyname'] not in ('profiles_read_own','profiles_update_own','profiles_upsert_own') or p['policyname'] in policies:continue
        statement=f"create policy {p['policyname']} on profiles for {p['cmd']} to authenticated"
        if p['qual']:statement+=' using ('+p['qual']+')'
        if p['with_check']:statement+=' with check ('+p['with_check']+')'
        statements.append(statement+';')
    statements += ['alter table profiles enable row level security;',
        'grant select,insert,update on profiles to authenticated;',"notify pgrst,'reload schema';",'commit;']
    lab.sql('\n'.join(statements))

if __name__=='__main__':restore(Local(sys.argv[1]))
