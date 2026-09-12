"""Reproduce first-finalization dashboard plan staleness and verify its repair.

Requires the retained, finalized synthetic event before report workers start.
Temporary private schemas copy its report queue only. Existing entries, payments,
artifacts and tasks are fingerprinted and never edited. The candidate migration
is applied to this disposable local database; original function definitions and
all failed baseline requests are retained in the evidence directory.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import secrets
import threading
import time

from local import Local, ROOT, SHOW, ApiError
from configure_capacity import configure

MIGRATION = ROOT / 'supabase/migrations/20260912145011_replan_closeout_dashboard_after_queue_growth.sql'
TABLES = ('show_report_artifacts', 'show_task_queue', 'show_finalize_runs')


def write(path, value):
    path.write_text(json.dumps(value, indent=2))


def definitions(lab):
    return lab.rows("select p.proname name,pg_get_functiondef(p.oid) definition "
                    "from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
                    "where n.nspname='public' and p.proname like 'get_closeout_dashboard%' order by p.proname")


def metadata(lab):
    return lab.rows("select p.proname,proowner,proacl,prosecdef,provolatile,proconfig,"
                    "pg_get_function_arguments(p.oid) arguments,pg_get_function_result(p.oid) result "
                    "from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
                    "where n.nspname='public' and p.proname like 'get_closeout_dashboard%' order by p.proname")


def fingerprint(lab):
    return {table: lab.sql(f"select count(*)::text||':'||md5(string_agg(md5(to_jsonb(t)::text),',' order by id)) "
                          f"from public.{table} t where show_id='{SHOW}'").strip()
            for table in (*TABLES, 'entries', 'show_payments')}


def growth_trial(lab, out, label, functions, people, params, expected):
    """Keep the same REST connections through empty warmup, commit and reads."""
    schema = 'local_dashboard_' + label + '_' + secrets.token_hex(4)
    proxy = schema + '_probe'
    sql = [f'begin; create schema {schema}; revoke all on schema {schema} from public;']
    for table in TABLES:
        sql += [f'create table {schema}.{table} (like public.{table} including all);',
                f'alter table {schema}.{table} enable row level security;',
                # Hold the empty-table statistics through the measured transition.
                f'alter table {schema}.{table} set (autovacuum_enabled=false);',
                f'analyze {schema}.{table};']
    for fn in functions:
        definition = fn['definition']
        for name in [f['name'] for f in functions]:
            definition = definition.replace('public.' + name + '(', schema + '.' + name + '(')
        for table in TABLES:
            definition = definition.replace('public.' + table, schema + '.' + table)
        sql.append(definition + ';')
    sql += [f'revoke all on all functions in schema {schema} from public,anon,authenticated;',
            f'grant usage on schema {schema} to authenticated,service_role;',
            f'grant execute on function {schema}.get_closeout_dashboard_scoped_for_species(uuid,text,uuid[],integer,integer,public.report_type,text) to authenticated,service_role;',
            f"""create function public.{proxy}(p_parameters jsonb,p_warm boolean default false)
            returns jsonb language plpgsql security invoker set search_path='' as $probe$
            declare v_dashboard jsonb;
            begin
              v_dashboard := {schema}.get_closeout_dashboard_scoped_for_species(
                (p_parameters->>'p_show_id')::uuid,p_parameters->>'p_scope_key',
                array(select jsonb_array_elements_text(p_parameters->'p_section_ids'))::uuid[],
                (p_parameters->>'p_artifact_limit')::integer,(p_parameters->>'p_artifact_offset')::integer,
                (p_parameters->>'p_report_name')::public.report_type,p_parameters->>'p_species_filter');
              -- Warm every pooled connection, then remove this delay for measurement.
              if p_warm then perform pg_catalog.pg_sleep(0.05); end if;
              return jsonb_build_object('backend_pid',pg_backend_pid(),'dashboard',v_dashboard);
            end; $probe$;
            revoke all on function public.{proxy}(jsonb,boolean) from public,anon;
            grant execute on function public.{proxy}(jsonb,boolean) to authenticated,service_role;
            notify pgrst,'reload schema'; commit;"""]
    (out / (label + '-setup.sql')).write_text('\n'.join(sql))
    created = False
    records = []
    lock = threading.Lock()
    admins = [p for p in people if p['role'] == 'admin']
    supers = [p for p in people if p['role'] == 'superintendent']
    assert len(admins) == 20 and len(supers) == 30

    def call(person, stage, warm=False, support=False):
        started = time.monotonic()
        row = dict(stage=stage,role=person['role'],ok=False)
        try:
            if support:
                lab.rpc('get_show_checkin_dashboard',dict(p_show_id=SHOW),person['token'])
            else:
                data = lab.rpc(proxy,dict(p_parameters=params,p_warm=warm),person['token'])
                row['backend_pid'] = data['backend_pid']
                row['count'] = data['dashboard']['artifact_counts']['total']
                if stage == 'warm': assert row['count'] == 0
                if stage == 'after': assert data['dashboard'] == expected, 'Dashboard contents differ'
            row['ok'] = True
        except Exception as error:
            row['error'] = str(error)
        row['duration_ms'] = (time.monotonic() - started) * 1000
        with lock:
            records.append(row)
            with (out / (label + '-requests.jsonl')).open('a') as target:
                target.write(json.dumps(row) + '\n')

    try:
        lab.sql('\n'.join(sql)); created = True
        # Wait only for initial schema publication, before any warmed measurements.
        for attempt in range(50):
            try:
                lab.rpc(proxy,dict(p_parameters=params,p_warm=True),admins[0]['token'])
                break
            except ApiError as error:
                if error.code != 404: raise
                time.sleep(.1)
        else: raise RuntimeError('Local probe RPC was not published')
        gate = threading.Barrier(20)

        def warm(person):
            gate.wait()
            for _ in range(8): call(person,'warm',warm=True)

        with ThreadPoolExecutor(max_workers=20) as pool: list(pool.map(warm,admins))
        pids = {r['backend_pid'] for r in records if r['stage']=='warm' and r['ok']}
        assert len(pids) == 20, f'Only {len(pids)} REST connections warmed'
        assert all(r['ok'] for r in records), 'Empty queue warmup failed'
        stop = threading.Event(); gate = threading.Barrier(51)

        def concurrent_reads(person):
            gate.wait()
            while not stop.is_set():
                call(person,'transition',support=person['role']=='superintendent')
                stop.wait(.15)

        with ThreadPoolExecutor(max_workers=50) as pool:
            jobs = [pool.submit(concurrent_reads,p) for p in admins+supers]
            gate.wait()
            # DML only: no ANALYZE, DDL, cache invalidation or service restart.
            lab.sql('begin;\n'+'\n'.join(f'insert into {schema}.{table} select * from public.{table};' for table in TABLES)+'\ncommit;')
            stop.set()
            for job in jobs: job.result()
        gate = threading.Barrier(51)

        def after(person):
            gate.wait()
            for _ in range(3 if label=='fixed' else 1):
                call(person,'after',support=person['role']=='superintendent')

        with ThreadPoolExecutor(max_workers=50) as pool:
            jobs = [pool.submit(after,p) for p in admins+supers]
            gate.wait()
            for job in jobs: job.result()
        errors = [r for r in records if not r['ok']]
        times = sorted(r['duration_ms'] for r in records if r['stage']=='after' and r['role']=='admin' and r['ok'])
        result = dict(status='passed' if not errors else 'failed',warmed_backends=len(pids),
                      requests=len(records),errors=len(errors),statement_timeouts=sum('57014' in r.get('error','') for r in errors),
                      admin_after_p95_ms=times[min(len(times)-1,int(len(times)*.95))] if times else None,
                      admin_after_max_ms=max(times) if times else None,
                      autoanalyze_disabled_on_probe_tables_only=True,services_restarted_during_trial=False)
        write(out/(label+'-summary.json'),result)
        print(json.dumps(dict(trial=label,**result)),flush=True)
        return result
    finally:
        if created:
            lab.sql(f'drop function public.{proxy}(jsonb,boolean); drop schema {schema} cascade; notify pgrst,\'reload schema\';')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace');parser.add_argument('staff_file',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--baseline-functions',type=Path,help='Saved before-functions.json for repeating the test on an already patched local fixture')
    args=parser.parse_args();lab=Local(args.workspace);out=args.output;out.mkdir(parents=True,exist_ok=False)
    assert lab.rows(f"select is_test from shows where id='{SHOW}'")==[dict(is_test=True)]
    assert not lab.rows(f"select id from show_task_queue where show_id='{SHOW}' and task_status<>'queued' limit 1")
    write(out/'capacity.json',configure(lab))
    people=json.loads(args.staff_file.read_text())
    # Refresh and save these exact synthetic staff accounts, without provisioning new ones.
    for p in people:
        if p['role'] in ('admin','superintendent') or p==people[0]:
            p['token']=lab.session_token(p)
    write(out/'.staff.json',people);(out/'.staff.json').chmod(0o600)
    admin=next(p for p in people if p['role']=='admin')
    sections=['95100000-0000-0000-0000-000000000001','95100000-0000-0000-0000-000000000002']
    params=dict(p_show_id=SHOW,p_scope_key=SHOW+':'+','.join(sections),p_section_ids=sections,p_artifact_limit=100,p_artifact_offset=0,p_species_filter='rabbit')
    cases=[dict(params),dict(params,p_species_filter=None),dict(params,p_species_filter='cavy'),
           dict(params,p_report_name='exhibitor_report',p_artifact_limit=7),
           dict(params,p_report_name='exhibitor_report',p_artifact_limit=7,p_artifact_offset=5049),
           dict(params,p_report_name='arba_report'),dict(params,p_artifact_limit=200,p_artifact_offset=11600),
           dict(params,p_artifact_limit=0,p_artifact_offset=-1),
           *[dict(params,p_scope_key=SHOW+':'+s,p_section_ids=[s]) for s in sections]]
    before_functions=definitions(lab);write(out/'before-functions.json',before_functions)
    baseline_functions=json.loads(args.baseline_functions.read_text()) if args.baseline_functions else before_functions
    assert {f['name'] for f in baseline_functions}=={f['name'] for f in before_functions}, 'Baseline function set differs'
    assert 'LANGUAGE sql' in next(f['definition'] for f in baseline_functions if f['name']=='get_closeout_dashboard_scoped_without_activity'), 'Use an unpatched baseline or its saved --baseline-functions'
    write(out/'baseline-functions.json',baseline_functions)
    before=fingerprint(lab);before_meta=metadata(lab)
    expected=[lab.rpc('get_closeout_dashboard_scoped_for_species',c,admin['token']) for c in cases]
    write(out/'expected-dashboards.json',expected)
    assert expected[0]['artifact_counts']['total']==11693
    baseline=growth_trial(lab,out,'baseline',baseline_functions,people,params,expected[0])
    assert baseline['statement_timeouts']>0,'The original failure was not reproduced'
    migration=MIGRATION.read_text();lab.sql(migration);first=definitions(lab);lab.sql(migration)
    assert definitions(lab)==first,'Migration is not idempotent'
    after_meta=metadata(lab)
    for old,new in zip(before_meta,after_meta):
        assert {k:v for k,v in old.items() if k!='proconfig'}=={k:v for k,v in new.items() if k!='proconfig'},'Function contract or access changed'
        expected_config=old['proconfig'] or []
        if old['proname'] in ('get_closeout_dashboard_scoped','get_closeout_dashboard_scoped_without_activity'):
            expected_config=[v for v in expected_config if not v.startswith('plan_cache_mode=')]+['plan_cache_mode=force_custom_plan']
        assert sorted(new['proconfig'] or [])==sorted(expected_config)
    actual=[lab.rpc('get_closeout_dashboard_scoped_for_species',c,admin['token']) for c in cases]
    assert actual==expected,'Dashboard JSON changed'
    write(out/'actual-dashboards.json',actual)
    denied=[]
    for label,token,parameters in [('anonymous',lab.anon,params),('reporting_clerk',people[0]['token'],params),
                                  ('unrelated_show',admin['token'],dict(params,p_show_id='ffffffff-ffff-ffff-ffff-ffffffffffff'))]:
        try: lab.rpc('get_closeout_dashboard_scoped_for_species',parameters,token)
        except ApiError as error:
            assert error.code in (401,403),(label,error)
            denied.append(label)
        else: raise AssertionError('Unauthorized read succeeded: '+label)
    fixed=growth_trial(lab,out,'fixed',first,people,params,expected[0])
    assert fixed['status']=='passed',fixed
    assert fingerprint(lab)==before,'Original event rows changed'
    assert lab.sql('show plan_cache_mode').strip()=='auto','Planner setting leaked outside the function'
    result=dict(status='passed',baseline=baseline,fixed=fixed,equal_dashboard_cases=len(cases),denied_callers=denied,
                migration_idempotent=True,original_event_rows_unchanged=True,contracts_and_acl_preserved=True,
                migration_sha256=hashlib.sha256(migration.encode()).hexdigest())
    write(out/'summary.json',result);print(json.dumps(result),flush=True)


if __name__=='__main__':main()
