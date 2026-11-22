#!/usr/bin/env python3
"""Compare old/new readiness for synthetic scenarios; always roll back locally."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
container = sys.argv[1]
if not container.startswith('supabase_db_ringmaster-show-full-e2e'):
    raise SystemExit('Only the local full-e2e fixture is supported')

migration = (root / 'supabase/migrations/20261122031445_optimize_closeout_recognition_readiness.sql').read_text()
before = """
do $$ begin
  execute replace(pg_get_functiondef('public.show_results_readiness_scoped(uuid,uuid[])'::regprocedure),
    'public.show_results_readiness_scoped(', 'pg_temp.readiness_before(');
end $$;
"""
# Every readiness call made by the fixtures compares the complete JSON response.
compare = """
do $$ begin
  execute replace(pg_get_functiondef('public.show_results_readiness_scoped(uuid,uuid[])'::regprocedure),
    'public.show_results_readiness_scoped(', 'pg_temp.readiness_after(');
end $$;
create or replace function public.show_results_readiness_scoped(p_show_id uuid,p_section_ids uuid[])
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare old_result jsonb; new_result jsonb;
begin
  old_result := pg_temp.readiness_before(p_show_id,p_section_ids);
  new_result := pg_temp.readiness_after(p_show_id,p_section_ids);
  if old_result is distinct from new_result then
    raise exception 'Readiness changed: old %, new %', old_result, new_result;
  end if;
  return new_result;
end $$;
"""
for name, compare_results in [
    ('cod_class_placement_only.sql', True),
    ('catalog_recognition_timelines.sql', False),
    ('closeout_recognition_readiness.sql', True),
    ('closeout_recognition_readiness.sql', False),
]:
    test = (root / 'supabase/tests' / name).read_text().replace('begin;\n', '', 1)
    if name == 'closeout_recognition_readiness.sql' and compare_results:
        # Compare fixture semantics before switching roles. Test RLS against the
        # actual public function separately, without temporary SQL functions or
        # the PL/pgSQL comparison wrapper's cached plans.
        test = test.split('grant select on readiness_fixture')[0] + '\nselect * from finish(); rollback;'
    result = subprocess.run(['docker', 'exec', '-i', container, 'psql', '-U',
        'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At'],
        input='begin;\n' + (before if compare_results else '') + migration
            + (compare if compare_results else '') + test,
        text=True, capture_output=True)
    print(name, result.stdout, result.stderr, sep='\n')
    if result.returncode or 'not ok ' in result.stdout:
        raise SystemExit(result.returncode or 1)
