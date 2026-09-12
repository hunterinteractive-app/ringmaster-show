"""500 new purchasers against the retained populated local show, with 50 staff.

Every purchaser registers, signs in, creates ~10 animals, and pays through the
real local APIs. No pre-authentication or purchaser semaphore. This adds a new
diagnostic cohort to the retained fixture; full-event runs use fresh databases.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
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
    p.add_argument('--rest-pool',type=int,choices=(10,20,30),required=True)
    args=p.parse_args();lab=Local(args.workspace);out=args.output;out.mkdir(parents=True,exist_ok=False)
    for name in ('manifest.json','expected-entries.json'):(out/name).write_bytes((args.source/name).read_bytes())
    (lab.workspace/'rehearsal-capacity.json').write_text(json.dumps(dict(rest_pool=args.rest_pool)))
    test=Rehearsal(lab,out)
    class SupportFlow(Workflows):
        def __init__(self):self.t=test;self.lab=lab;self.people=[]
    flow=SupportFlow()
    cohort=json.loads((args.source/'event-profile.json').read_text())['registration_days'][-1]['exhibitors'][:500]
    assert len(cohort)==500
    nonce=secrets.token_hex(6);people=json.loads((args.source/'.event-staff.json').read_text())
    flow.people=[person for person in people if person['role'] in ('admin','superintendent')]
    assert len(flow.people)==50 and sum(p['role']=='admin' for p in flow.people)==20
    with ThreadPoolExecutor(max_workers=10) as pool:list(pool.map(lab.session_token,flow.people))
    samples=[];failures=[];stop=threading.Event();gate=threading.Barrier(551)
    records={};record_lock=threading.Lock();before_entries=int(lab.sql(f"select count(*) from entries where show_id='{SHOW}'"))
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
        gate.wait(timeout=90)
        original_n=cohort[i];rows=test.by_exhibitor[original_n]
        email=f'burst500-{nonce}-{i}@example.invalid';password=secrets.token_urlsafe(32)
        auth=test.measured('public_signup',i,lambda:lab.request('/auth/v1/signup',{'email':email,'password':password},lab.anon,timeout=90))
        login=test.measured('password_signin',i,lambda:lab.request('/auth/v1/token?grant_type=password',{'email':email,'password':password},lab.anon,timeout=90))
        token=login['access_token'];owner=login['user']['id'];assert auth['user']['id']==owner
        lookup=test.measured('account_lookup',i,lambda:retry(test,'account_lookup',i,lambda:lab.edge('claim-or-import-exhibitor',{'action':'lookup'},token),function=True))
        assert lookup['status']=='club_not_found'
        exhibitor=str(uuid.uuid4());cart=str(uuid.uuid4())
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
        with record_lock:records[i]=dict(owner=owner,exhibitor=exhibitor,cart=cart,entries=len(rows))
        return i
    thread=threading.Thread(target=monitor,daemon=True)
    try:
        test.start();(out/'statements-before.json').write_text(json.dumps(statements()))
        thread.start();test.log('burst_ready',purchasers=500,admins=20,superintendents=30,rest_pool=args.rest_pool)
        began=time.monotonic()
        with ThreadPoolExecutor(max_workers=550) as pool:
            support=[pool.submit(flow.support,p,gate,stop) for p in flow.people]
            purchasers={pool.submit(buy,i):i for i in range(500)}
            gate.wait(timeout=90);test.log('burst_started',purchasers=500)
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
        counts=lab.rows(f"select count(*) entries,count(distinct e.exhibitor_id) exhibitors,count(*) filter(where e.payment_status='paid') paid from entries e join exhibitors x on x.id=e.exhibitor_id where e.show_id='{SHOW}' and x.email like 'burst500-{nonce}-%@example.invalid'")[0]
        payments=lab.rows(f"select p.cart_id,p.payment_session_id,p.total_cents,p.payment_status from show_payments p join exhibitors x on x.id=p.exhibitor_id where p.show_id='{SHOW}' and x.email like 'burst500-{nonce}-%@example.invalid'")
        balances=lab.rows(f"select sum(b.balance_due_cents) due from show_exhibitor_balances b join exhibitors x on x.id=b.exhibitor_id where b.show_id='{SHOW}' and x.email like 'burst500-{nonce}-%@example.invalid'")[0]
        test.summary['checks']=dict(counts=counts,expected_entries=expected,completed_purchasers=len(records),failures=failures,
            elapsed_s=round(elapsed,3),rest_pool=args.rest_pool,purchaser_concurrency=500,admins=20,superintendents=30,
            provider_sessions=len(test.providers.sessions),paid_cents=sum(r['total_cents'] for r in payments),
            max_connections=max((s.get('connections',{}).get('total',0) for s in samples),default=0),
            max_rest_connections=max((s.get('connections',{}).get('rest',0) for s in samples),default=0),
            max_pool_waiting=max((s.get('pool',{}).get('pgrst_db_pool_waiting',0) for s in samples),default=0),
            pool_timeouts=max((s.get('pool',{}).get('pgrst_db_pool_timeouts_total',0) for s in samples),default=0))
        assert not failures,failures[:3]
        assert counts==dict(entries=expected,exhibitors=500,paid=expected),counts
        assert len(records)==len(payments)==len({p['cart_id'] for p in payments})==len({p['payment_session_id'] for p in payments})==len(test.providers.sessions)==500
        assert all(p['payment_status']=='paid' and p['total_cents']==next(r['entries'] for r in records.values() if r['cart']==p['cart_id'])*500 for p in payments)
        assert balances['due']==0
        assert int(lab.sql(f"select count(*) from entries where show_id='{SHOW}'"))==before_entries+expected
        assert int(lab.sql(f"select count(*) from auth.users where email like 'burst500-{nonce}-%@example.invalid'"))==500
        assert not [e for e in test.events if not e['ok']],'A staff or purchaser action failed'
        test.summary.update(status='passed');test.log('burst_passed',checks=test.summary['checks'])
    except Exception as error:
        test.summary.update(status='failed',error=str(error));raise
    finally:
        stop.set()
        if thread.is_alive():thread.join(timeout=10)
        (out/'resources.json').write_text(json.dumps(samples));(out/'cohort.json').write_text(json.dumps(dict(nonce=nonce,purchasers=records)))
        test.finish()

if __name__=='__main__':main()
