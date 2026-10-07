"""Prepare or run the local registration-only scenario with resource evidence."""
import argparse
from collections import Counter
import json
from pathlib import Path
import shutil
import subprocess
import threading
import time

from local import Local, SHOW, uid
from event import EventFlow, write
from prepare import prepare
from registration_scenario import manifest_for, calendar
from run import Rehearsal


def audit(test):
    lab = test.lab
    actual = lab.rows(f"select animal_id,exhibitor_id,section_id,breed,variety,class_name,sex,tattoo,payment_status from entries where show_id='{SHOW}'")
    fields = ('animal_id','exhibitor_id','section_id','breed','variety','class_name','sex','tattoo','payment_status')
    expected = [dict(e, animal_id=uid('953',e['n']), exhibitor_id=uid('952',e['exhibitor']), payment_status='paid') for e in test.entries]
    def identities(rows):
        return Counter(tuple(str(r.get(k) or '') for k in fields) for r in rows)
    want, got = identities(expected), identities(actual)
    payments = lab.rows(f"select count(*) n,sum(total_cents) total,sum(refunded_cents) refunded from show_payments where show_id='{SHOW}' and payment_status='paid' and provider='stripe'")[0]
    balances = lab.rows(f"select count(*) n,sum(calculated_total_cents) charged,sum(paid_online_cents) online,sum(balance_due_cents) due from show_exhibitor_balances where show_id='{SHOW}'")[0]
    health = lab.rpc('get_stripe_payment_queue_health', {})
    checks = dict(entry_field_multiset_matches=want==got,
                  entries=len(actual), exhibitors=len({r['exhibitor_id'] for r in actual}),
                  missing_entries=sum((want-got).values()), unexpected_entries=sum((got-want).values()),
                  payments=payments, balances=balances, queue_health=health,
                  provider_checkout_sessions=len(test.providers.sessions))
    write(test.output/'registration-reconciliation.json',checks)
    assert want==got, 'Saved entry fields do not match the independently prepared fixture'
    owners, cents = len(test.by_exhibitor), len(expected)*500
    assert payments==dict(n=owners,total=cents,refunded=0),payments
    assert balances==dict(n=owners,charged=cents,online=cents,due=0),balances
    assert len(test.providers.sessions)==owners
    assert all(health[k]==0 for k in ('pending','blocked','retrying')),health
    return checks


class ResourceSampler:
    def __init__(self, lab, output):
        self.lab,self.output=lab,output
        self.stop=threading.Event()
        self.thread=threading.Thread(target=self.collect,daemon=True)
        self.started=time.monotonic()
    def collect(self):
        while not self.stop.is_set():
            record=dict(unix_time=time.time(),elapsed_s=time.monotonic()-self.started,
                        host_disk_free_bytes=shutil.disk_usage(self.output).free)
            try:
                names=subprocess.check_output(['docker','ps','--filter','label=com.supabase.cli.project='+self.lab.project,'--format','{{.Names}}'],text=True,timeout=10).split()
                raw=subprocess.check_output(['docker','stats','--no-stream','--format','{{json .}}',*names],text=True,timeout=15)
                record['containers']=[json.loads(line) for line in raw.splitlines() if line]
                record['database']=self.lab.rows("select count(*) connections,count(*) filter(where state='active') active_connections,pg_database_size(current_database()) bytes from pg_stat_activity")[0]
            except Exception as e: record['sampling_error']=str(e)
            with (self.output/'resource-samples.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
            self.stop.wait(3)
    def start(self):self.thread.start()
    def close(self):
        self.stop.set()
        if self.thread.is_alive():self.thread.join(timeout=30)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode',choices=('prepare','run'));p.add_argument('workspace');p.add_argument('output',type=Path)
    p.add_argument('--entries',type=int,default=35000);p.add_argument('--final-day-percent',type=int,default=65);p.add_argument('--peak',type=int,default=500)
    a=p.parse_args();lab=Local(a.workspace)
    if a.mode=='prepare':
        m,entries=prepare(lab,a.output,manifest=manifest_for(a.entries))
        profile=calendar(entries,a.final_day_percent,a.peak)
        write(a.output/'event-profile.json',profile)
        assert lab.rows(f"select (select count(*) from entries where show_id='{SHOW}') entries,(select count(*) from show_payments where show_id='{SHOW}') payments")==[dict(entries=0,payments=0)]
        print(json.dumps(dict(status='prepared',entries=len(entries),exhibitors=m['totals']['exhibitors'],final_day=profile['registration_days'][-1]['entries'],peak=a.peak)))
        return
    assert not (a.output/'registration-summary.json').exists(), 'Preserve existing run evidence; prepare a fresh run'
    test=Rehearsal(lab,a.output)
    assert test.manifest.get('fixture_kind')=='registration_only', 'A registration-only fixture is required'
    flow=EventFlow(test)
    assert flow.profile.get('scope')=='registration_only'
    monitor=ResourceSampler(lab,a.output)
    test.summary['limitations']=test.manifest['assumptions']+[
        'Compressed local API workload; not a day-long browser or hosted capacity test.',
        'Stripe/Resend are emulated and OTP emails are captured by local SMTP.',
        'Historical baseline contracts are selectively restored; complete production parity is not claimed.',
        'Resource sampling is approximately every five seconds; short peaks may fall between samples.']
    try:
        flow.staff();test.start();test.start_email_code_login()
        monitor.start();wall=time.time();began=time.monotonic()
        flow.registration_calendar()
        test.summary['calendar_elapsed_s']=time.monotonic()-began
        test.summary['clock_gap_s']=time.time()-wall-test.summary['calendar_elapsed_s']
        assert abs(test.summary['clock_gap_s'])<2,'Host sleep/clock discontinuity invalidated timing'
        test.summary['checks']['independent_reconciliation']=audit(test)
        test.summary['status']='passed' if all(e['ok'] for e in test.events) else 'failed'
    except Exception as e:
        test.summary.update(status='failed',error=str(e));test.log('registration_stress_failed',error=str(e))
        raise
    finally:
        monitor.close();test.finish();write(a.output/'registration-summary.json',test.summary)
    if test.summary['status']!='passed':raise SystemExit(1)
    print(json.dumps(dict(status=test.summary['status'],calendar_elapsed_s=test.summary['calendar_elapsed_s'])))


if __name__=='__main__':main()
