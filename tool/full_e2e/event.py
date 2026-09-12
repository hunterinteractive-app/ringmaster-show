"""Compressed calendar rehearsal using the actual local event APIs and print UI."""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import threading
import time

from local import Local, ROOT, SHOW, uid
from run import Rehearsal
from workflows import Workflows


def write(path, value):
    path.write_text(json.dumps(value, indent=2))


def specification(out):
    target=out/'event-profile.json'
    if target.exists(): return json.loads(target.read_text())
    entries=json.loads((out/'expected-entries.json').read_text())
    rng=random.Random(20260910)
    exhibitors=list(range(1,2529));rng.shuffle(exhibitors)
    counts=Counter(e['exhibitor'] for e in entries)
    cohorts=[];cursor=0
    for start,end,fraction,concurrency in ((1,14,.25,20),(15,29,.45,100),(30,30,.30,250)):
        group=[];total=0
        while cursor<len(exhibitors) and (total<round(25711*fraction) or end==30):
            n=exhibitors[cursor];cursor+=1;group.append(n);total+=counts[n]
        for day in range(start,end+1):
            daily=group[day-start::end-start+1]
            cohorts.append(dict(day=day,exhibitors=daily,entries=sum(counts[n] for n in daily),concurrency=min(concurrency,len(daily))))
    candidates=entries.copy();rng.shuffle(candidates)
    ears={e['n'] for e in candidates[:round(len(entries)*.30)]}
    other={e['n'] for e in candidates if e['n'] not in ears and e['sex'] in ('Buck','Doe')}
    other=set(sorted(other,key=lambda n:hashlib.sha256(str(n).encode()).hexdigest())[:round(len(entries)*.05)])
    scratches={e['n'] for e in candidates if e['n'] not in ears|other}
    scratches=set(sorted(scratches,key=lambda n:hashlib.sha256(str(n).encode()).hexdigest())[:round(len(entries)*.08)])
    changes=[]
    for e in entries:
        values={'ear_number':e['tattoo']+'X'} if e['n'] in ears else {'sex':'Doe' if e['sex']=='Buck' else 'Buck'} if e['n'] in other else {'scratch_entry':True} if e['n'] in scratches else None
        if values:
            changes.append(dict(n=e['n'],exhibitor=e['exhibitor'],values=values,fee_cents=0 if e['n'] in scratches else 500,
                                kind='scratch_entry' if e['n'] in scratches else 'entry_edit'))
    checkin_order=exhibitors.copy();rng.shuffle(checkin_order)
    profile=dict(seed=20260910,calendar_days=30,calendar_compressed=True,entries=25711,exhibitors=2528,
        registration_days=cohorts,last_day_share_of_all_entries=.30,peak_concurrency_assumption=250,
        change_counts=dict(ear_number=len(ears),other_sex=len(other),scratches=len(scratches)),changes=changes,
        checkin_days=[checkin_order[:1264],checkin_order[1264:]],judging_days=2,judge_sessions=110,
        qr_sessions=55,manual_sessions=55,checkin_sessions=30,admins=10,superintendents=15,
        fee_per_approved_ear_or_sex_change_cents=500,scratch_fee_cents=0,
        final_report_deadline_seconds=7200,physical_printer_tested=False)
    write(target,profile);return profile


class EventFlow(Workflows):
    def __init__(self,test):
        self.t=test;self.lab=test.lab;self.people=[];self.support_stop=threading.Event()
        self.profile=specification(test.output);self.awards={}
        self.by_n={e['n']:e for e in test.entries}
        rows=self.lab.rows(f"select id,animal_id from entries where show_id='{SHOW}'")
        for r in rows:self.by_n[int(r['animal_id'][-12:])]['id']=r['id']

    def staff(self):
        path=self.t.output/'.event-staff.json'
        if path.exists():
            self.people=json.loads(path.read_text())
            for p in self.people:
                auth=self.lab.request('/auth/v1/token?grant_type=refresh_token',{'refresh_token':p['refresh_token']})
                p.update(token=auth['access_token'],refresh_token=auth['refresh_token'])
        else:super().staff()
        write(path,self.people);path.chmod(0o600)

    @contextmanager
    def support_activity(self,phase):
        gate=threading.Barrier(26);stop=threading.Event()
        with ThreadPoolExecutor(max_workers=25) as pool:
            jobs=[pool.submit(self.support,p,gate,stop) for p in self.people[110:]]
            gate.wait();self.t.log('support_started',phase=phase,admins=10,superintendents=15)
            try:yield
            finally:
                stop.set()
                for job in jobs:job.result()

    def registration_calendar(self):
        existing={int(r['exhibitor_id'][-12:]):r['count'] for r in self.lab.rows(f"select exhibitor_id,count(*) from entries where show_id='{SHOW}' group by exhibitor_id")}
        completed=[]
        for day in self.profile['registration_days']:
            saved=self.t.output/f'registration-day-{day["day"]:02d}.json'
            if saved.exists():
                assert not json.loads(saved.read_text())['failures'],'A failed day needs review before continuation'
                completed.extend(day['exhibitors'])
        assert set(existing)==set(completed),'Only completely recorded registration days can be resumed'
        assert all(existing[n]==len(self.t.by_exhibitor[n]) for n in existing)
        self.t.verify_account_lookup=True
        with self.support_activity('registration'):
            for day in self.profile['registration_days']:
                if (self.t.output/f'registration-day-{day["day"]:02d}.json').exists():continue
                began=time.monotonic();failures=[];gate=threading.Barrier(day['concurrency'])
                # A single barrier synchronizes the first burst; subsequent purchasers follow freed slots.
                counter=0;lock=threading.Lock()
                def register(n):
                    nonlocal counter
                    with lock:ordinal=counter;counter+=1
                    if ordinal<day['concurrency']:gate.wait(timeout=60)
                    return self.t.register(n)
                self.t.log('registration_day_started',day=day['day'],entries=day['entries'],sessions=day['concurrency'])
                with ThreadPoolExecutor(max_workers=day['concurrency']) as pool:
                    jobs={pool.submit(register,n):n for n in day['exhibitors']}
                    for job in as_completed(jobs):
                        try:job.result()
                        except Exception as e:failures.append(dict(exhibitor=jobs[job],error=str(e)))
                record=dict(day=day['day'],entries=day['entries'],exhibitors=len(day['exhibitors']),
                            concurrency=day['concurrency'],elapsed_s=time.monotonic()-began,failures=failures)
                write(self.t.output/f'registration-day-{day["day"]:02d}.json',record)
                self.t.log('registration_day_completed',**{k:v for k,v in record.items() if k!='elapsed_s'},duration_s=record['elapsed_s'])
                if failures:raise RuntimeError(f'Registration day {day["day"]} failed; dependent stages paused')
        counts=self.lab.rows(f"select count(*) entries,count(distinct exhibitor_id) exhibitors,sum(case when payment_status='paid' then 1 else 0 end) paid from entries where show_id='{SHOW}'")[0]
        assert counts==dict(entries=25711,exhibitors=2528,paid=25711),counts
        self.t.summary['checks']['registration']=counts

    def print_stage(self,stage):
        if stage=='preprint':
            self.rpc('assign_show_coop_numbers',dict(p_show_id=SHOW,p_scope_mode='separate',p_overwrite_existing=False),self.people[110],'assign_coops')
            collisions=self.lab.rows(f"select scope,coop_number from show_animal_coop_numbers where show_id='{SHOW}' group by scope,coop_number having count(*)>1")
            assert not collisions,collisions
        modes=['coop-recheck'] if stage=='coop-recheck' else ['coop','checkin-open','checkin-youth'] if stage=='preprint' else ['control-open','control-youth','remark-open','remark-youth']
        results=[]
        with self.support_activity(stage):
            for mode in modes:
                out=self.t.output/'print-packs'/mode;out.mkdir(parents=True,exist_ok=True)
                env={**os.environ,'EVENT_API_URL':self.lab.url,'EVENT_ANON_KEY':self.lab.anon,
                     'EVENT_STAFF_ACCESS_TOKEN':self.lab.session_token(self.people[110]),'EVENT_PRINT_MODE':mode,'EVENT_PRINT_OUTPUT':str(out.resolve())}
                start=time.monotonic()
                with (out/'flutter.log').open('w') as log:
                    result=subprocess.run(['flutter','test','test/local_event_print_rehearsal_test.dart','--reporter','expanded'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
                results.append(dict(mode=mode,exit_code=result.returncode,elapsed_s=time.monotonic()-start))
                self.t.log('print_job_completed',mode=mode,exit_code=result.returncode,duration_s=results[-1]['elapsed_s'])
        write(self.t.output/(stage+'-print-results.json'),results)
        self.t.summary['checks']['print_jobs']=results
        if any(r['exit_code'] for r in results):self.t.summary['print_failures_observed']=True

    def recover_registration(self):
        original=json.loads((self.t.output/'registration-day-30.json').read_text())
        assert original['failures'],'This continuation requires a recorded failed burst'
        existing={int(r['exhibitor_id'][-12:]) for r in self.lab.rows(f"select distinct exhibitor_id from entries where show_id='{SHOW}'")}
        missing=sorted(set(range(1,2529))-existing)
        partial=self.lab.rows(f"select x.id,x.owner_user_id,u.email,c.id cart_id from exhibitors x join auth.users u on u.id=x.owner_user_id join entry_cart_items i on i.exhibitor_id=x.id join entry_carts c on c.id=i.cart_id where c.show_id='{SHOW}' and c.status='active' group by x.id,u.email,c.id")
        partial_ids={int(r['id'][-12:]) for r in partial}
        self.t.verify_account_lookup=True;self.t.registration_people={}
        with self.support_activity('registration_recovery'):
            def provision(n):
                return n,self.t.measured('controlled_account_setup',n,lambda:self.lab.person(f'exhibitor-recovery-{n}'))
            with ThreadPoolExecutor(max_workers=12) as pool:
                for n,person in pool.map(provision,[n for n in missing if n not in partial_ids]):self.t.registration_people[n]=person
            # Recover the already-created cart with its same authenticated owner.
            for r in partial:
                link=self.lab.request('/auth/v1/admin/generate_link',dict(type='magiclink',email=r['email']))
                auth=self.lab.request('/auth/v1/verify',dict(type='magiclink',token_hash=link['hashed_token']))
                n=int(r['id'][-12:]);token=auth['access_token']
                quote=self.t.measured('resumed_cart_checkout',n,lambda:self.lab.edge('stripe-create-checkout-session',{'cart_id':r['cart_id']},token))
                import uuid
                self.t.measured('resumed_cart_webhook',n,lambda:self.t.webhook(self.t.providers.checkout(quote['checkout_session_id']),'evt_local_'+str(uuid.uuid4())))
            failures=[];todo=[n for n in missing if n not in partial_ids];gate=threading.Barrier(min(250,len(todo)))
            lock=threading.Lock();started=0
            def purchase(n):
                nonlocal started
                with lock:order=started;started+=1
                if order<gate.parties:gate.wait(timeout=60)
                return self.t.register(n)
            began=time.monotonic()
            with ThreadPoolExecutor(max_workers=250) as pool:
                jobs={pool.submit(purchase,n):n for n in todo}
                for job in as_completed(jobs):
                    try:job.result()
                    except Exception as e:failures.append(dict(exhibitor=jobs[job],error=str(e)))
            result=dict(original_burst_status='failed',original_failed_purchasers=len(original['failures']),
                        preauthenticated_purchasers=len(todo),resumed_carts=len(partial),concurrency=250,
                        elapsed_s=time.monotonic()-began,failures=failures)
            write(self.t.output/'registration-recovery-detail.json',result)
            assert not failures,failures[:3]
        counts=self.lab.rows(f"select count(*) entries,count(distinct exhibitor_id) exhibitors from entries where show_id='{SHOW}'")[0]
        assert counts==dict(entries=25711,exhibitors=2528),counts
        self.t.summary['checks']['recovered_registration']=counts
        self.t.summary['original_registration_burst_passed']=False

    def event_checkin(self):
        portal=self.lab.rpc('regenerate_show_checkin_portal_token',{'p_show_id':SHOW})
        self.lab.sql(f"update show_checkin_settings set is_enabled=true,entry_edit_permissions='{{\"ear_number\":\"approval\",\"sex\":\"approval\",\"scratch_entry\":\"approval\"}}',entry_edit_fee_cents='{{\"ear_number\":500,\"sex\":500,\"scratch_entry\":0}}' where show_id='{SHOW}';")
        changes=defaultdict(list)
        for c in self.profile['changes']:changes[c['exhibitor']].append(c)
        for day,exhibitors in enumerate(self.profile['checkin_days'],1):
            def action(p):
                for n in exhibitors[p['index']::30]:
                    params=dict(p_show_id=SHOW,p_exhibitor_id=uid('952',n))
                    if changes[n]:
                        session=self.t.measured('checkin_portal_auth',p['index'],lambda:self.lab.rpc('authenticate_exhibitor_checkin',dict(p_portal_token=portal,p_exhibitor_number=str(n),p_last_name=f'Exhibitor {n:04d}'),self.lab.anon))
                        for c in changes[n]:
                            e=self.by_n[c['n']]
                            result=self.t.measured('change_request',p['index'],lambda:self.lab.rpc('submit_exhibitor_checkin_change_request',dict(p_session_token=session['session_token'],p_entry_id=e['id'],p_request_type=c['kind'],p_requested_changes=c['values'],p_note='Synthetic event rehearsal'),self.lab.anon))
                            request_id=result.get('id') or result.get('request_id');assert request_id,result
                            self.rpc('review_checkin_change_request',dict(p_request_id=request_id,p_approved=True,p_review_note='Synthetic event approval'),p,'change_approval')
                        due=sum(c['fee_cents'] for c in changes[n])
                        context=self.rpc('get_show_checkin_payment_context',params,p,'cash_payment_context')
                        assert context['balance_due_cents']==due,(n,context,due)
                        if due:self.rpc('record_checkin_manual_payment',dict(params,p_amount_cents=due,p_method='cash',p_reference=f'LOCAL-EVENT-{n}',p_receipt_preference='no_receipt'),p,'cash_change_payment')
                    result=self.rpc('complete_exhibitor_checkin_by_secretary_with_receipt',dict(params,p_entries_confirmed=True,p_initials=f'S{p["index"]}',p_note='Local event rehearsal',p_receipt_preference='no_receipt'),p,'checkin_save')
                    assert result['status']=='completed',result
            self.parallel_phase('checkin_day_'+str(day),self.people[:30],action)
            self.t.log('checkin_day_completed',day=day)
        # Build independent expectations from the requested changes, not DB outcomes.
        for c in self.profile['changes']:
            e=self.by_n[c['n']]
            for key,value in c['values'].items():
                e[{'ear_number':'tattoo','scratch_entry':'scratched'}.get(key,key)]=value
        classes=defaultdict(list)
        for e in self.t.entries:
            e['placement']=0
            if not e.get('scratched'):classes[tuple(e[k] for k in ('section_id','breed','variety','class_name','sex'))].append(e)
        for entries in classes.values():
            for place,e in enumerate(sorted(entries,key=lambda e:e['n']),1):e['placement']=place
        winners={}
        for b in self.t.manifest['breeds']:
            group=[e for e in self.t.entries if not e.get('scratched') and e['section_id']==uid('951',b['section']) and e['breed']==b['breed']]
            if b['bob'] and group:
                first=min(group,key=lambda e:(e['placement'],e['n']));winners[first['n']]=['BOB']
        for section in (1,2):
            ids=[n for n in winners if self.by_n[n]['section_id']==uid('951',section)]
            for n,code in zip(ids[:2],('BIS','RIS')):winners[n].append(code)
        write(self.t.output/'expected-final-entries.json',self.t.entries)
        write(self.t.output/'expected-awards.json',winners)

    def event_judging(self):
        self.awards={int(n):v for n,v in json.loads((self.t.output/'expected-awards.json').read_text()).items()}
        # Class groups keep a single judge/entry method and finish within one day.
        classes=defaultdict(list)
        for e in self.t.entries:
            if not e.get('scratched'):classes[tuple(e[k] for k in ('section_id','breed','variety','class_name','sex'))].append(e)
        assignments=[[] for _ in range(110)]
        groups=sorted(classes.values(),key=lambda rows:(rows[0]['section_id'],rows[0]['n']))
        random.Random(20260911).shuffle(groups)
        for i,rows in enumerate(groups):assignments[i%110].append(rows)
        plan=[]
        for day in (1,2):
            def action(p):
                for rows in assignments[p['index']][day-1::2]:
                    for e in rows:self.save(p,e,'qr' if p['index']%2==0 else 'manual')
            selected=[e for groups_for_staff in assignments for rows in groups_for_staff[day-1::2] for e in rows]
            plan.append(dict(day=day,entries=len(selected),sections=dict(Counter(e['section_id'] for e in selected))))
            self.parallel_phase('simultaneous_open_youth_day_'+str(day),self.people[:110],action)
        write(self.t.output/'judging-day-plan.json',plan)
        for section in (1,2):
            ready=self.lab.readiness(section,self.people[110]['token']);assert ready['ready'],ready
            self.t.summary['checks']['readiness_'+str(section)]=ready
        self.t.log('all_judging_completed_before_closeout')
        write(self.t.output/'judging-completed.json',dict(unix_time=time.time(),both_sections_ready=True))

    def event_closeout(self):
        assert (self.t.output/'judging-completed.json').exists()
        started=time.time()
        with self.support_activity('finalization'):
            for section in (1,2):
                assert self.lab.readiness(section,self.people[110]['token'])['ready']
            # Match the current V2 screen: both sections, one combined run.
            self.finalize_combined()
        self.start_workers()
        from recovery import verify
        # Failure injection is part of the timed closeout. Three peers continue
        # processing; no manual recovery RPC or artifact regeneration is used.
        for _ in range(100):
            if self.lab.rows(f"select id from show_task_queue where show_id='{SHOW}' and worker_id='local-full-e2e-0' and task_status='running' limit 1"):break
            time.sleep(.1)
        else:raise RuntimeError('No owned active worker available for recovery test')
        with ThreadPoolExecutor(max_workers=1) as recovery_pool:
            recovery=recovery_pool.submit(verify,str(self.lab.workspace),self.t.output,self.t.children[-4].pid,
                                          'local-full-e2e-0',ROOT/'output/full_e2e/closeout-renderer',7200)
            self.closeout(max_minutes=120)
            result=recovery.result();assert result['status']=='passed',result
        elapsed=time.time()-started
        self.t.summary['checks']['checkout_generation_deadline']=dict(elapsed_seconds=elapsed,budget_seconds=7200,passed=elapsed<=7200)
        assert elapsed<=7200


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('workspace');p.add_argument('output',type=Path)
    p.add_argument('stage',choices=['registration','registration-recovery','preprint','checkin','judgeprint','coop-recheck','judging','closeout'])
    args=p.parse_args();test=Rehearsal(Local(args.workspace),args.output);flow=EventFlow(test)
    wall_started=time.time();monotonic_started=time.monotonic()
    try:
        flow.staff()
        if args.stage in ('registration','registration-recovery','closeout'):test.start()
        if args.stage=='registration':flow.registration_calendar()
        elif args.stage=='registration-recovery':flow.recover_registration()
        elif args.stage in ('preprint','judgeprint','coop-recheck'):flow.print_stage(args.stage)
        elif args.stage=='checkin':flow.event_checkin()
        elif args.stage=='judging':flow.event_judging()
        else:flow.event_closeout()
        timing=dict(wall_elapsed_seconds=time.time()-wall_started,monotonic_elapsed_seconds=time.monotonic()-monotonic_started)
        timing['clock_gap_seconds']=timing['wall_elapsed_seconds']-timing['monotonic_elapsed_seconds']
        test.summary['checks']['host_clock_continuity']=timing
        assert abs(timing['clock_gap_seconds'])<2,'Host sleep or clock discontinuity invalidated this stage timing'
        test.summary['status']='passed' if not any(not e['ok'] for e in test.events) and not test.summary.get('print_failures_observed') else 'failed'
    except Exception as e:
        test.summary.update(status='failed',error=str(e));test.log('event_stage_failed',stage=args.stage,error=str(e));raise
    finally:
        if flow.people:
            staff_path=args.output/'.event-staff.json';write(staff_path,flow.people);staff_path.chmod(0o600)
        test.finish();write(args.output/(args.stage+'-summary.json'),test.summary)
    if test.summary['status']=='failed':raise SystemExit(1)


if __name__=='__main__':main()
