"""Public new/returning purchaser bursts against a populated local synthetic show.

No purchaser semaphore or pre-authenticated sessions. Returning accounts are
created before timing; all purchasers sign in during the burst. Every success
requires saved paid entries, then an independent cohort ledger reconciliation.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
import time
import uuid
from local import Local, SHOW
from run import Rehearsal
from workflows import Workflows
from registration_retry import insert, retry

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('workspace');p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--purchasers',type=int,choices=(500,750,1000),required=True)
    p.add_argument('--cohort-size',type=int,help='Total purchasers; defaults to concurrency. Allows a sustained final-day cohort.')
    p.add_argument('--accounts',choices=('new','returning','mixed'),required=True)
    p.add_argument('--login',choices=('password','email-code'),default='password')
    args=p.parse_args();lab=Local(args.workspace);out=args.output;out.mkdir(parents=True,exist_ok=False)
    for name in ('manifest.json','expected-entries.json'):(out/name).write_bytes((args.source/name).read_bytes())
    peak=args.purchasers
    assert lab.project=='ringmaster-show-full-e2e-pc-0913', 'Use the isolated capacity clone'
    test=Rehearsal(lab,out)
    class SupportFlow(Workflows):
        def __init__(self):self.t=test;self.lab=lab;self.people=[]
    flow=SupportFlow()
    final_day=json.loads((args.source/'event-profile.json').read_text())['registration_days'][-1]['exhibitors']
    total=args.cohort_size if args.cohort_size is not None else peak
    if not peak<=total<=len(final_day):p.error('Cohort size must be between concurrency and the planned final-day exhibitor count')
    cohort=final_day[:total]
    assert len(cohort)==total
    nonce=secrets.token_hex(6);staff_path=lab.workspace/'diagnostic-support-sessions.json'
    people=json.loads((staff_path if staff_path.exists() else args.source/'.event-staff.json').read_text())
    flow.people=[person for person in people if person['role'] in ('admin','superintendent')]
    assert len(flow.people)==100 and sum(p['role']=='admin' for p in flow.people)==40
    with ThreadPoolExecutor(max_workers=10) as pool:list(pool.map(lab.session_token,flow.people))
    with os.fdopen(os.open(staff_path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),'w') as f:json.dump(flow.people,f)
    samples=[];failures=[];stop=threading.Event();gate=threading.Barrier(peak+101)
    records={};credentials={};record_lock=threading.Lock();before_entries=int(lab.sql(f"select count(*) from entries where show_id='{SHOW}'"))
    for i in range(total):
        credentials[i]=dict(email=f'burst-{nonce}-{i}@example.invalid',password=secrets.token_urlsafe(32),returning=args.accounts=='returning' or (args.accounts=='mixed' and i%2==0))
    def save_private():
        path=out/'recovery-credentials-private.json'
        with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),'w') as f:json.dump(credentials,f)
    save_private()
    def provision(i):
        p=credentials[i]
        if p['returning']:
            user=lab.request('/auth/v1/admin/users',dict(email=p['email'],password=p['password'],email_confirm=True))
            p['user_id']=user['id']
    with ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(provision,range(total)))
    save_private()
    def statements():
        return lab.rows("select queryid::text,query,calls,total_exec_time,mean_exec_time,max_exec_time,rows,shared_blks_hit,shared_blks_read,temp_blks_written from pg_stat_statements where dbid=(select oid from pg_database where datname=current_database())")
    def monitor():
        while not stop.is_set():
            sample=dict(at_s=round(time.monotonic()-test.started,3))
            try:
                sample['connections']=lab.rows("select count(*) total,count(*) filter(where usename='supabase_auth_admin') auth,count(*) filter(where usename='authenticator') rest,count(*) filter(where state='active') active from pg_stat_activity")[0]
                metrics=subprocess.check_output(['docker','exec',lab.container,'curl','-sf',f'http://supabase_rest_{lab.project}:3001/metrics'],text=True,timeout=5)
                sample['pool']={line.split()[0]:float(line.split()[1]) for line in metrics.splitlines() if line.startswith('pgrst_db_pool_')}
            except Exception as e:sample['error']=str(e)[:300]
            samples.append(sample);stop.wait(.5)
    def buy(i):
        if i<peak:gate.wait(timeout=90)
        original_n=cohort[i];rows=test.by_exhibitor[original_n]
        person=credentials[i];email=person['email'];password=person['password']
        auth=None
        if args.login=='email-code':
            login=test.measured('email_code_login',i,lambda:email_codes.login(test,email,i))
        elif not person['returning']:
            auth=test.measured('public_signup',i,lambda:lab.request('/auth/v1/signup',{'email':email,'password':password},lab.anon,timeout=90))
        if args.login=='password':
            login=test.measured('password_signin',i,lambda:lab.request('/auth/v1/token?grant_type=password',{'email':email,'password':password},lab.anon,timeout=90))
        token=login['access_token'];owner=login['user']['id']
        if person['returning']:assert person['user_id']==owner
        elif auth:assert auth['user']['id']==owner
        lookup=test.measured('account_lookup',i,lambda:retry(test,'account_lookup',i,lambda:lab.edge('claim-or-import-exhibitor',{'action':'lookup'},token),function=True))
        assert lookup['status']=='club_not_found'
        exhibitor=str(uuid.uuid4());cart=str(uuid.uuid4())
        with record_lock:records[i]=dict(owner=owner,exhibitor=exhibitor,cart=cart,entries=len(rows),completed=False)
        test.measured('create_exhibitor',i,lambda:insert(test,'exhibitors',dict(id=exhibitor,owner_user_id=owner,display_name=f'Synthetic Burst {nonce} {i}',first_name='Synthetic',last_name=f'Burst {i}',email=email,exhibitor_number=f'B{nonce}{i}',type='open' if original_n<=test.manifest['sections'][0]['exhibitors'] else 'youth',created_for_show_id=SHOW),token,i))
        animals=[];items=[]
        for j,e in enumerate(rows):
            animal=str(uuid.uuid4());details={k:e[k] for k in ('species','breed','variety','class_name','sex')}
            details['tattoo']=f'B{nonce}{i}-{j}'
            animals.append(dict(id=animal,owner_user_id=owner,name='',**details))
            items.append(dict(id=str(uuid.uuid4()),cart_id=cart,exhibitor_id=exhibitor,animal_id=animal,section_id=e['section_id'],animal_name='',**details))
        test.measured('create_animals',i,lambda:insert(test,'animals',animals,token,i))
        test.measured('create_cart',i,lambda:insert(test,'entry_carts',dict(id=cart,show_id=SHOW,user_id=owner,status='active'),token,i))
        test.measured('add_cart_items',i,lambda:insert(test,'entry_cart_items',items,token,i))
        quote=test.measured('checkout_session',i,lambda:test.checkout_with_client_retry(cart,token,i))
        assert quote['amount_total_cents']==len(rows)*500
        if i<16:
            replay=test.measured('checkout_replay',i,lambda:test.checkout_with_client_retry(cart,token,i))
            assert replay['checkout_session_id']==quote['checkout_session_id']
        event='evt_local_'+uuid.uuid4().hex
        obj=test.providers.checkout(quote['checkout_session_id'])
        test.measured('paid_webhook',i,lambda:test.webhook(obj,event))
        if i<16:assert test.measured('payment_replay',i,lambda:test.webhook(obj,event)).get('duplicate') is True
        test.measured('persisted_registration',i,lambda:test.wait_for_registration(cart,token,i,len(rows)))
        with record_lock:records[i]['completed']=True
        return i
    email_codes=None
    thread=threading.Thread(target=monitor,daemon=True)
    try:
        test.start()
        if args.login=='email-code':
            from email_code_login import LocalEmailCodes
            email_codes=LocalEmailCodes(lab,nonce,out);email_codes.start()
        (out/'statements-before.json').write_text(json.dumps(statements()))
        thread.start();test.log('burst_ready',purchasers=peak,admins=40,superintendents=60,accounts=args.accounts,login=args.login,before_entries=before_entries,cohort_purchasers=total)
        began=time.monotonic()
        with ThreadPoolExecutor(max_workers=peak+100) as pool:
            support=[pool.submit(flow.support,p,gate,stop) for p in flow.people]
            purchasers={pool.submit(buy,i):i for i in range(total)}
            gate.wait(timeout=90);test.log('burst_started',purchasers=peak)
            try:
                for future in as_completed(purchasers):
                    try:future.result()
                    except Exception as e:
                        failures.append(dict(purchaser=purchasers[future],error=str(e)));test.log('purchase_failed',**failures[-1])
            finally:stop.set()
            for job in support:job.result()
        elapsed=time.monotonic()-began
        (out/'statements-after.json').write_text(json.dumps(statements()))
        expected=sum(len(test.by_exhibitor[n]) for n in cohort)
        counts=lab.rows(f"select count(*) entries,count(distinct e.exhibitor_id) exhibitors,count(*) filter(where e.payment_status='paid') paid from entries e join exhibitors x on x.id=e.exhibitor_id where e.show_id='{SHOW}' and x.email like 'burst-{nonce}-%@example.invalid'")[0]
        payments=lab.rows(f"select p.cart_id,p.payment_session_id,p.total_cents,p.payment_status from show_payments p join exhibitors x on x.id=p.exhibitor_id where p.show_id='{SHOW}' and x.email like 'burst-{nonce}-%@example.invalid'")
        balances=lab.rows(f"select sum(b.balance_due_cents) due from show_exhibitor_balances b join exhibitors x on x.id=b.exhibitor_id where b.show_id='{SHOW}' and x.email like 'burst-{nonce}-%@example.invalid'")[0]
        test.summary['checks']=dict(counts=counts,expected_entries=expected,completed_purchasers=sum(r['completed'] for r in records.values()),failures=failures,
            elapsed_s=round(elapsed,3),account_mode=args.accounts,login=args.login,before_entries=before_entries,purchaser_concurrency=peak,cohort_purchasers=total,admins=40,superintendents=60,
            provider_sessions=len(test.providers.sessions),paid_cents=sum(r['total_cents'] for r in payments),
            max_connections=max((s.get('connections',{}).get('total',0) for s in samples),default=0),
            max_rest_connections=max((s.get('connections',{}).get('rest',0) for s in samples),default=0),
            max_pool_waiting=max((s.get('pool',{}).get('pgrst_db_pool_waiting',0) for s in samples),default=0),
            pool_timeouts=max((s.get('pool',{}).get('pgrst_db_pool_timeouts_total',0) for s in samples),default=0)-(samples[0].get('pool',{}).get('pgrst_db_pool_timeouts_total',0) if samples else 0))
        assert not failures,failures[:3]
        assert counts==dict(entries=expected,exhibitors=total,paid=expected),counts
        assert all(r['completed'] for r in records.values())
        assert len(records)==len(payments)==len({p['cart_id'] for p in payments})==len({p['payment_session_id'] for p in payments})==len(test.providers.sessions)==total
        assert all(p['payment_status']=='paid' and p['total_cents']==next(r['entries'] for r in records.values() if r['cart']==p['cart_id'])*500 for p in payments)
        assert balances['due']==0
        assert int(lab.sql(f"select count(*) from entries where show_id='{SHOW}'"))==before_entries+expected
        assert int(lab.sql(f"select count(*) from auth.users where email like 'burst-{nonce}-%@example.invalid'"))==total
        assert not [e for e in test.events if not e['ok']],'A staff or purchaser action failed'
        test.summary.update(status='passed');test.log('burst_passed',checks=test.summary['checks'])
    except Exception as error:
        test.summary.update(status='failed',error=str(error));raise
    finally:
        stop.set()
        if thread.is_alive():thread.join(timeout=10)
        if email_codes:email_codes.close()
        save_private()
        (out/'queue-health.json').write_text(json.dumps(lab.rpc('get_stripe_payment_queue_health',{})))
        (out/'resources.json').write_text(json.dumps(samples));(out/'cohort.json').write_text(json.dumps(dict(nonce=nonce,purchasers=records)))
        test.finish()

if __name__=='__main__':main()
