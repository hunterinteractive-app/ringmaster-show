"""40 authenticated staff sessions plus real closeout workers, LOCAL only."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from collections import Counter, defaultdict
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import threading
import time

from lab import ApiError, Lab, ROOT, SHOW, elapsed, uid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('workspace')
parser.add_argument('--historical-40-session-replay', action='store_true',
                    help='Explicitly replay the superseded 40-session diagnostic.')
parser.add_argument('--max-minutes', type=int, default=45)
parser.add_argument('--workers', type=int, default=4)
args = parser.parse_args()
if not args.historical_40_session_replay:
    parser.error('This runner replays the historical 40-session diagnostic. The next phased 55/135-session workload is in workload.json; do not use this run as evidence for it.')
if not 1 <= args.workers <= 8 or not 1 <= args.max_minutes <= 60:
    parser.error('Use 1–8 workers and a 1–60 minute diagnostic limit.')
lab = Lab(args.workspace)
out = ROOT / 'output/closeout_rehearsal'
manifest = json.loads((out / 'convention_manifest.json').read_text())
run_dir = out / time.strftime('run-%Y%m%d-%H%M%S')
run_dir.mkdir()
events = []
lock = threading.Lock()
stop = threading.Event()
start_gate = threading.Barrier(41)
workers = []
worker_logs = []
started = time.monotonic()
summary = {'staff_sessions': 40, 'workers': args.workers,
           'max_concurrent_renders': args.workers * 4, 'runs': {}, 'checks': {},
           'limitations': manifest['closeout_rehearsal']['limitations']}

# A stop request never leaves the executor waiting on infinite admin polling.
signal.signal(signal.SIGTERM, lambda *_: stop.set())
signal.signal(signal.SIGINT, lambda *_: stop.set())


def log(message, **fields):
    print(json.dumps({'event': message, 'elapsed_s': round(time.monotonic() - started, 2), **fields}), flush=True)


def measured(kind, session, call):
    began = time.monotonic()
    event = {'kind': kind, 'session': session}
    try:
        value = call()
        event['ok'] = True
        return value
    except Exception as error:
        event.update(ok=False, error=str(error))
        raise
    finally:
        event['duration_ms'] = round((time.monotonic() - began) * 1000, 2)
        event['at_s'] = round(began - started, 2)
        with lock:
            events.append(event)


def checkin(person):
    i, token = person['index'], person['token']
    start_gate.wait()
    for n in range(i + 1, 2529, 16):
        if stop.is_set():
            break
        params = {'p_show_id': SHOW, 'p_exhibitor_id': uid('952', n)}
        try:
            if n <= 64:
                balance = measured('payment_context', i, lambda: lab.rpc('get_show_checkin_payment_context', params, token))
                amount = balance['balance_due_cents']
                if amount:
                    measured('manual_payment', i, lambda: lab.rpc('record_checkin_manual_payment',
                        dict(params, p_amount_cents=amount, p_method='cash',
                             p_reference=f'LOCAL-REHEARSAL-{n}', p_receipt_preference='no_receipt'), token))
            confirm = dict(params, p_entries_confirmed=True, p_initials=f'S{i + 1}',
                           p_note='Synthetic local rehearsal', p_receipt_preference='no_receipt')
            result = measured('checkin_save', i, lambda: lab.rpc('complete_exhibitor_checkin_by_secretary_with_receipt', confirm, token))
            if result['status'] != 'completed':
                raise AssertionError('Check-in did not complete')
            if n <= 16:
                # A committed response is discarded to model an ambiguous ACK.
                replay = measured('checkin_retry', i, lambda: lab.rpc('complete_exhibitor_checkin_by_secretary_with_receipt', confirm, token))
                if replay['id'] != result['id']:
                    raise AssertionError('Check-in retry created another identity')
        except Exception:
            # Record failures and continue independent exhibitors.
            pass
        stop.wait(1.0)


expected_placements = {}
for row in manifest['classes']:
    for n in range(max(18868, row['first']), min(19867, row['last']) + 1):
        expected_placements[n] = n - row['first'] + 1
awards = defaultdict(list)
for b in manifest['breeds']:
    if b['bob']:
        awards[b['first']].append('BOB')
for section in (1, 2):
    bobs = [b for b in manifest['breeds'] if b['bob'] and b['section'] == section][:2]
    for b, code in zip(bobs, ('BIS', 'RIS')):
        awards[b['first']].append(code)


def judging(person):
    i, token = person['index'], person['token']
    start_gate.wait()
    for n in range(18868 + i - 16, 19868, 20):
        if stop.is_set():
            break
        params = {'p_show_id': SHOW, 'p_entry_id': uid('954', n),
            'p_placement': str(expected_placements[n]), 'p_result_status': 'Shown',
            'p_disqualified_reason': None, 'p_is_shown': True, 'p_is_disqualified': False,
            'p_judged_by_show_judge_id': '31000000-0000-0000-0000-000000000001',
            'p_result_entered_by_name': f'Local Staff {i + 1}', 'p_result_entered_by_phone': None,
            'p_awards': awards[n], 'p_is_qr_entry_mode': False}
        try:
            result = measured('judging_save', i, lambda: lab.rpc('save_results_entry', params, token))
            if not result or int(result[0]['placement']) != expected_placements[n]:
                raise AssertionError('Incorrect saved placement')
            if n < 18888:
                measured('judging_retry', i, lambda: lab.rpc('save_results_entry', params, token))
        except Exception:
            pass
        stop.wait(1.0)


def admin(person):
    i, token = person['index'], person['token']
    start_gate.wait()
    iteration = 0
    while not stop.is_set() and time.monotonic() - started < args.max_minutes * 60:
        section = 1 + iteration % 2
        ids = [uid('951', section)]
        try:
            measured('closeout_dashboard', i, lambda: lab.rpc('get_closeout_dashboard_scoped_for_species',
                {'p_show_id': SHOW, 'p_scope_key': SHOW + ':' + ','.join(ids),
                 'p_section_ids': ids, 'p_artifact_limit': 200, 'p_artifact_offset': 0,
                 'p_species_filter': 'rabbit'}, token))
            if iteration % 5 == 0:
                measured('checkin_dashboard', i, lambda: lab.rpc('get_show_checkin_dashboard', {'p_show_id': SHOW}, token))
        except Exception:
            pass
        iteration += 1
        stop.wait(2.0)


def queue_status():
    return json.loads(lab.sql(f"select coalesce(json_object_agg(s,n),'{{}}') from (select task_status::text s,count(*) n from public.show_task_queue where show_id='{SHOW}' group by task_status) q;"))


try:
    # Worker claims are global. Refuse to touch another show's pending work.
    other = int(lab.sql(f"select count(*) from public.show_task_queue where show_id<>'{SHOW}' and task_status::text in ('queued','running');").strip())
    if other:
        raise RuntimeError('Other shows have pending tasks in this local stack')
    existing = int(lab.sql(f"select count(*) from public.show_finalize_runs where show_id='{SHOW}';"))
    if existing:
        raise RuntimeError('Use a fresh fixture; existing closeout evidence must be preserved')
    log('creating_local_staff')
    staff = lab.staff()
    summary['authenticated_users'] = len({p['user_id'] for p in staff})
    allowed = lab.rpc('user_can_finalize_show', {'p_show_id': SHOW, 'p_user_id': staff[36]['user_id']})
    if allowed is not True:
        raise AssertionError('Admin is not authorized to initiate closeout')
    summary['checks']['open_ready_before_work'] = lab.readiness(1, staff[36]['token'])['ready']
    youth_before = lab.readiness(2, staff[36]['token'])
    summary['checks']['youth_missing_before_work'] = youth_before['missing_placement_count']
    if youth_before['missing_placement_count'] != 1000:
        raise AssertionError('The fixture must begin with exactly 1,000 unfinished Youth results')
    try:
        lab.finalize(2)
        summary['checks']['unfinished_youth_finalize_rejected'] = False
    except ApiError as error:
        summary['checks']['unfinished_youth_finalize_rejected'] = 'not ready' in str(error)
    with ThreadPoolExecutor(max_workers=40) as pool:
        jobs = [pool.submit(checkin, p) for p in staff[:16]]
        judges = [pool.submit(judging, p) for p in staff[16:36]]
        admins = [pool.submit(admin, p) for p in staff[36:]]
        start_gate.wait()
        log('staff_work_started', sessions=40)
        try:
            value, ms = elapsed(lambda: lab.finalize(1))
            summary['runs']['open'] = {'result': value, 'duration_ms': ms}
            log('open_finalize_completed', duration_ms=ms, result=value)
        except Exception as error:
            summary['runs']['open'] = {'error': str(error)}
            log('open_finalize_failed', error=str(error))
        # The real worker executes unchanged loaders/builders/queue/storage.
        if 'result' in summary['runs']['open']:
            for n in range(args.workers):
                handle = (run_dir / f'worker-{n + 1}.log').open('w')
                worker_logs.append(handle)
                workers.append(subprocess.Popen([str(out / 'closeout-renderer'), '--continuous'],
                    cwd=ROOT, env=lab.worker_env(f'local-rehearsal-{n + 1}'),
                    stdout=handle, stderr=subprocess.STDOUT))
            log('workers_started', count=len(workers))
        for job in judges:
            job.result()
        youth_after = lab.readiness(2, staff[36]['token'])
        summary['checks']['youth_after_judging'] = youth_after
        if youth_after['ready']:
            try:
                value, ms = elapsed(lambda: lab.finalize(2))
                summary['runs']['youth'] = {'result': value, 'duration_ms': ms}
                log('youth_finalize_completed', duration_ms=ms, result=value)
            except Exception as error:
                summary['runs']['youth'] = {'error': str(error)}
                log('youth_finalize_failed', error=str(error))
        else:
            log('youth_still_not_ready', readiness=youth_after)
        while workers and not stop.is_set() and time.monotonic() - started < args.max_minutes * 60:
            status = queue_status()
            log('queue_progress', status=status, workers_alive=sum(p.poll() is None for p in workers))
            (run_dir / 'events.json').write_text(json.dumps(events, indent=2))
            (run_dir / 'summary.partial.json').write_text(json.dumps(summary, indent=2))
            if not any(status.get(k, 0) for k in ('queued', 'running')):
                break
            if not any(p.poll() is None for p in workers):
                break
            # Halt early on widespread failures; preserve diagnostic evidence.
            if status.get('failed', 0) >= 50:
                summary['halt_reason'] = 'At least 50 render tasks failed; investigate before retrying'
                break
            stop.wait(15)
        # Staff saves finish even if rendering fails independently.
        for job in jobs:
            job.result()
        stop.set()
        for job in admins:
            job.result()
except Exception as error:
    summary['fatal_error'] = str(error)
    log('rehearsal_error', error=str(error))
finally:
    stop.set()
    for process in workers:
        if process.poll() is None:
            process.terminate()
    for process in workers:
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    for handle in worker_logs:
        handle.close()
    summary['elapsed_s'] = round(time.monotonic() - started, 2)
    summary['queue'] = queue_status()
    stats = {}
    for kind in sorted({e['kind'] for e in events}):
        rows = [e for e in events if e['kind'] == kind]
        times = sorted(e['duration_ms'] for e in rows)
        stats[kind] = {'requests': len(rows), 'failures': sum(not e['ok'] for e in rows),
                       'p50_ms': times[math.ceil(len(times)*.50)-1],
                       'p95_ms': times[math.ceil(len(times)*.95)-1],
                       'max_ms': max(times)}
    summary['staff_metrics'] = stats
    summary['outcome'] = ('failed' if summary.get('fatal_error')
        or any(row['failures'] for row in stats.values())
        or any(summary['queue'].get(status, 0) for status in ('queued','running','failed'))
        else 'render_stage_complete')
    summary['checks']['database_totals'] = json.loads(lab.sql(f"""select json_build_object(
      'entries',(select count(*) from public.entries where show_id='{SHOW}'),
      'exhibitors',(select count(distinct exhibitor_id) from public.entries where show_id='{SHOW}'),
      'completed_checkins',(select count(*) from public.show_checkin_records where show_id='{SHOW}' and status='completed'),
      'award_rows',(select count(*) from public.entry_awards where show_id='{SHOW}'),
      'judging_writers',(select count(distinct result_entered_by_user_id) from public.entries where show_id='{SHOW}'),
      'judged_entries',(select count(*) from public.entries where show_id='{SHOW}' and result_entered_by_user_id is not null),
      'fees_cents',(select sum(calculated_total_cents) from public.show_exhibitor_balances where show_id='{SHOW}'),
      'paid_cents',(select sum(paid_manual_cents) from public.show_exhibitor_balances where show_id='{SHOW}'),
      'due_cents',(select sum(balance_due_cents) from public.show_exhibitor_balances where show_id='{SHOW}'),
      'payment_rows',(select count(*) from public.show_payments where show_id='{SHOW}')
    );"""))
    (run_dir / 'events.json').write_text(json.dumps(events, indent=2))
    (run_dir / 'summary.json').write_text(json.dumps(summary, indent=2))
    log('rehearsal_finished', summary_path=str(run_dir / 'summary.json'), summary=summary)
raise SystemExit(1 if summary['outcome'] == 'failed' else 0)
