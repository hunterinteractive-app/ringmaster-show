"""Restore inspected browser contracts only inside a guarded synthetic project."""
import json
import sys
from local import Local, ROOT, SHOW


def restore(lab):
    contract = json.loads((ROOT / 'supabase/local/e2e_historical_judging_browser.json').read_text())
    existing = {(r['table_name'], r['column_name']) for r in lab.rows(
        "select table_name,column_name from information_schema.columns where table_schema='public'")}
    tables = {table for table, _ in existing}
    sql = ['begin;']
    for table in ('show_result_entry_locks', 'judge_judging_sessions'):
        if table not in tables:
            sql += [f'create table public.{table} ();',
                    f'alter table public.{table} enable row level security;',
                    f'grant all on public.{table} to service_role;']
    for row in contract['columns']:
        table, column = row['table_name'], row['column_name']
        if (table, column) in existing:
            continue
        assert row['data_type'] in ('uuid', 'text', 'boolean', 'integer', 'numeric', 'timestamp with time zone')
        default = ' default ' + row['column_default'] if row['column_default'] else ''
        # A legacy fixture may already contain assignments without labels.
        nullable = '' if column == 'assignment_label' or row['is_nullable'] == 'YES' else ' not null'
        sql.append(f'alter table public.{table} add column {column} {row["data_type"]}{default}{nullable};')
    for table in ('show_result_entry_locks', 'judge_judging_sessions'):
        if table not in tables:
            sql.append(f'alter table public.{table} add primary key(id);')
    if 'show_result_entry_locks' not in tables:
        sql.append('alter table public.show_result_entry_locks add unique(show_id,section_id,breed_id);')
    sql += ["update public.judge_assignments set assignment_label='Synthetic Assignment' where assignment_label is null;",
            'alter table public.judge_assignments alter column assignment_label set not null;']
    existing_policies = {(r['tablename'], r['policyname']) for r in lab.rows(
        "select tablename,policyname from pg_policies where schemaname='public'")}
    for policy in contract['read_policies']:
        if (policy['tablename'], policy['policyname']) in existing_policies:
            continue
        roles = policy['roles']
        roles = ','.join(roles) if isinstance(roles, list) else roles.strip('{}')
        sql.append(f'create policy "{policy["policyname"]}" on public.{policy["tablename"]} for SELECT to {roles} using ({policy["qual"]});')
    sql.append('grant select on public.judges, public.judge_assignments, public.variety_groups, public.varieties, public.show_result_entry_locks to authenticated;')
    sql.append('grant select on public.show_result_entry_locks to anon;')
    for function in contract['functions']:
        assert function['proname'] == 'record_judging_session_entry'
        sql += [function['definition'] + ';',
                'revoke all on function public.record_judging_session_entry(uuid,uuid,uuid,text) from public,anon;',
                'grant execute on function public.record_judging_session_entry(uuid,uuid,uuid,text) to authenticated,service_role;']
    sql += [f"insert into public.judge_assignments(show_id,judge_id,assignment_label) select distinct s.show_id,j.id,coalesce(j.display_name,j.name,'Synthetic Judge') from public.show_judges s join public.judges j on j.id=s.judge_id where s.show_id='{SHOW}' and not exists(select 1 from public.judge_assignments a where a.show_id=s.show_id and a.judge_id=j.id);",
            "notify pgrst,'reload schema';", 'commit;']
    lab.sql('\n'.join(sql))


if __name__ == '__main__':
    restore(Local(sys.argv[1]))
