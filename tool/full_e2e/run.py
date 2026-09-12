"""Run the real local APIs from cart creation through closeout and capture."""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import hmac
import json
import os
import random
import secrets
from pathlib import Path
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from local import Local, ApiError, ROOT, SHOW, uid, sql_quote
from providers import Providers, WEBHOOK_SECRET, prepare_functions


class Rehearsal:
    def __init__(self, lab, output):
        self.lab, self.output = lab, output
        expected=output/'expected-final-entries.json'
        if not expected.exists(): expected=output/'expected-entries.json'
        self.entries = json.loads(expected.read_text())
        self.manifest = json.loads((output/'manifest.json').read_text())
        self.by_exhibitor=defaultdict(list)
        for e in self.entries: self.by_exhibitor[e['exhibitor']].append(e)
        self.lock=threading.Lock(); self.events=[]; self.children=[]; self.logs=[]
        self.started=time.monotonic(); self.stop=threading.Event()
        self.providers=None
        self.summary={'status':'running','checks':{},'phases':{},'limitations':[
            'Local API concurrency, not 135 rendered browsers or hosted capacity.',
            'Stripe and Resend protocol responses are emulated locally; external provider behavior is not certified.',
            'Historical local contracts were restored selectively; complete production schema parity is not claimed.',
            'Exact breed totals; synthetic ownership, placements and winners; Open class sizes are proportional.']}

    def log(self, event, **fields):
        print(json.dumps(dict(event=event,elapsed_s=round(time.monotonic()-self.started,2),**fields)),flush=True)

    def measured(self, kind, session, call):
        event=dict(kind=kind,session=session,at_s=round(time.monotonic()-self.started,3)); start=time.monotonic()
        try:
            value=call(); event['ok']=True; return value
        except Exception as e:
            event.update(ok=False,error=str(e)[:2000]); raise
        finally:
            event['duration_ms']=round((time.monotonic()-start)*1000,2)
            with self.lock:
                self.events.append(event)
                with (self.output/'events.jsonl').open('a') as f: f.write(json.dumps(event)+'\n')

    def start(self):
        from configure_capacity import configure
        (self.output/'capacity-config.json').write_text(json.dumps(configure(self.lab),indent=2))
        self.providers=Providers(self.output)
        self.providers.start()
        envfile=prepare_functions(self.lab,self.output)
        log_path=self.output/'edge-functions.log'
        log_offset=log_path.stat().st_size if log_path.exists() else 0
        log=log_path.open('a');self.logs.append(log)
        # No live provider credentials inherited from the shell.
        env={k:v for k,v in os.environ.items() if not any(s in k.upper() for s in ('STRIPE','RESEND','SUPABASE','SQUARE','PAYPAL','SMTP','CLUB'))}
        child=subprocess.Popen(['supabase','functions','serve','--workdir',str(self.lab.workspace),'--env-file',str(envfile)],stdout=log,stderr=subprocess.STDOUT,env=env)
        self.children.append(child)
        for _ in range(60):
            if child.poll() is not None: raise RuntimeError('Local Edge runtime exited; inspect edge-functions.log')
            # An old runtime may still answer HTTP while the new CLI replaces
            # its container. Wait for THIS process to announce readiness first.
            with log_path.open() as current_log:
                current_log.seek(log_offset)
                started='Serving functions on' in current_log.read()
            if not started:
                self.stop.wait(1)
                continue
            try:
                # A bad method must get the real function's 405, proving it loaded.
                self.lab.request('/functions/v1/stripe-webhook',method='GET',timeout=3)
            except ApiError as e:
                if e.code==405: break
            except Exception: pass
            self.stop.wait(1)
        else: raise RuntimeError('Local signed webhook did not become ready')

    def webhook(self, obj, event_id):
        event=dict(id=event_id,object='event',type='checkout.session.completed',livemode=False,
                   account='acct_local_synthetic',created=int(time.time()),data={'object':obj})
        raw=json.dumps(event,separators=(',',':')).encode(); stamp=str(int(time.time()))
        signature=hmac.new(WEBHOOK_SECRET.encode(),stamp.encode()+b'.'+raw,hashlib.sha256).hexdigest()
        req=urllib.request.Request(self.lab.url+'/functions/v1/stripe-webhook',raw,
            {'Content-Type':'application/json','stripe-signature':f't={stamp},v1={signature}'})
        # Stripe retries delivery failures with the same event ID. Exercise
        # that behavior at the synthetic provider boundary, retaining every
        # failed HTTP attempt in the evidence. Never retry a rejected signature.
        for attempt in range(1,4):
            try:
                with urllib.request.urlopen(req,timeout=30) as r: return json.loads(r.read())
            except urllib.error.HTTPError as e:
                body=e.read().decode()
                if e.code<500 or attempt==3:raise ApiError(e.code,body) from None
                self.log('webhook_delivery_retry',event_id=event_id,attempt=attempt,status=e.code)
            except (urllib.error.URLError,TimeoutError):
                if attempt==3:raise
                self.log('webhook_delivery_retry',event_id=event_id,attempt=attempt,status='transport')
            self.stop.wait(.5*attempt)

    def register(self,n):
        p=getattr(self,'registration_people',{}).get(n)
        if p is None:
            email=f'exhibitor-{n}-{secrets.token_hex(6)}@example.invalid'
            password=secrets.token_urlsafe(32)
            auth=self.measured('public_signup',n,lambda:self.lab.request('/auth/v1/signup',
                {'email':email,'password':password},self.lab.anon,timeout=90))
            login=self.measured('password_signin',n,lambda:self.lab.request('/auth/v1/token?grant_type=password',
                {'email':email,'password':password},self.lab.anon,timeout=90))
            assert auth['user']['id']==login['user']['id']
            p=dict(user_id=login['user']['id'],token=login['access_token'],email=email)
        token=p['token']; rows=self.by_exhibitor[n]
        if getattr(self, 'verify_account_lookup', False):
            lookup=self.measured('account_lookup',n,lambda:self.lab.edge('claim-or-import-exhibitor',{'action':'lookup'},token))
            assert lookup['status']=='club_not_found',lookup
        exhibitor=dict(id=uid('952',n),owner_user_id=p['user_id'],display_name=f'Synthetic Exhibitor {n}',
            first_name='Synthetic',last_name=f'Exhibitor {n:04d}',exhibitor_number=str(n),
            email=p['email'],city='Localtown',state='IN',zip='46000',arba_number=f'LOCAL-{n}',
            address_line1='1 Synthetic Lane',type='open' if n<=1855 else 'youth',created_for_show_id=SHOW)
        self.measured('create_exhibitor',n,lambda:self.lab.request('/rest/v1/exhibitors',exhibitor,token))
        animals=[dict(id=uid('953',e['n']),owner_user_id=p['user_id'],species=e['species'],tattoo=e['tattoo'],
            name=e['animal_name'],breed=e['breed'],variety=e['variety'],class_name=e['class_name'],sex=e['sex']) for e in rows]
        self.measured('create_animals',n,lambda:self.lab.request('/rest/v1/animals',animals,token))
        cart=str(uuid.uuid4())
        self.measured('create_cart',n,lambda:self.lab.request('/rest/v1/entry_carts',dict(id=cart,show_id=SHOW,user_id=p['user_id'],status='active'),token))
        items=[dict(id=uid('959',e['n']),cart_id=cart,exhibitor_id=exhibitor['id'],animal_id=uid('953',e['n']),
            **{k:e[k] for k in ('section_id','species','tattoo','animal_name','breed','variety','class_name','sex')}) for e in rows]
        self.measured('add_cart_items',n,lambda:self.lab.request('/rest/v1/entry_cart_items',items,token))
        quote=self.measured('checkout_session',n,lambda:self.checkout_with_client_retry(cart,token,n))
        assert quote['show_balance_total_cents']==len(rows)*500, quote
        assert quote['amount_total_cents']==len(rows)*500, quote # fees absorbed for this fixture
        if n<=16:
            replay=self.measured('checkout_retry',n,lambda:self.checkout_with_client_retry(cart,token,n))
            assert replay['checkout_session_id']==quote['checkout_session_id']
        obj=self.providers.checkout(quote['checkout_session_id']); event='evt_local_'+str(uuid.uuid4())
        self.measured('paid_webhook',n,lambda:self.webhook(obj,event))
        if n<=16:
            result=self.measured('payment_webhook_retry',n,lambda:self.webhook(obj,event))
            assert result.get('duplicate') is True, result
        return n

    def checkout_with_client_retry(self,cart,token,session):
        # Match StripeConnectService.startCheckout + retryTransient exactly:
        # three attempts, only the four transient function statuses, same cart.
        # Keep every failed attempt visible even when the user action recovers.
        for attempt in range(1,4):
            try:
                return self.lab.edge('stripe-create-checkout-session',{'cart_id':cart},token)
            except ApiError as error:
                retry=error.code in (500,502,503,504) and attempt<3
                record=dict(session=session,cart_id=cart,attempt=attempt,status=error.code,retry=retry)
                with self.lock:
                    with (self.output/'checkout-http-failures.jsonl').open('a') as f:
                        f.write(json.dumps(record)+'\n')
                self.log('checkout_http_failure',**record)
                if not retry:raise
                self.stop.wait(((250 << (attempt-1))+random.randrange(250))/1000)

    def registration(self, limit):
        existing={int(r['exhibitor_id'].split('-')[-1]):int(r['n']) for r in self.lab.rows(f"select exhibitor_id,count(*) n from public.entries where show_id='{SHOW}' group by exhibitor_id")}
        for n,count in existing.items():
            assert count==len(self.by_exhibitor[n]), 'Incomplete prior registration'
        todo=[n for n in range(1,limit+1) if n not in existing]
        self.log('registration_start',remaining=len(todo),concurrency=12)
        failed=[];done=0
        with ThreadPoolExecutor(max_workers=12) as pool:
            pending={pool.submit(self.register,n):n for n in todo}
            for future in as_completed(pending):
                n=pending[future]
                try: future.result();done+=1
                except Exception as e:
                    failed.append(dict(exhibitor=n,error=str(e)))
                    self.log('registration_error',exhibitor=n,error=str(e))
                    # Stop new work on a systemic failure; never fabricate entries.
                    if len(failed)>=3:
                        for f in pending: f.cancel()
                        break
                if done%100==0 and done: self.log('registration_progress',completed=done)
        self.summary['phases']['registration']=dict(completed=done,existing=len(existing),failures=failed)
        if failed: raise RuntimeError('Registration phase failed; dependent phases were not started')
        rows=self.lab.rows(f"select count(*) entries,count(distinct exhibitor_id) exhibitors,count(*) filter(where payment_status='paid') paid_entries from public.entries where show_id='{SHOW}'")[0]
        self.summary['checks']['registration']=rows
        assert rows['entries']==sum(len(self.by_exhibitor[n]) for n in range(1,limit+1))
        self.log('registration_complete',**rows)

    def finish(self):
        self.stop.set()
        for child in self.children:
            if child.poll() is None: child.terminate()
        for child in self.children:
            try: child.wait(timeout=20)
            except subprocess.TimeoutExpired: child.kill();child.wait(timeout=5)
        for log in self.logs: log.close()
        if self.providers is not None: self.providers.stop()
        metrics={}
        for kind in sorted({e['kind'] for e in self.events}):
            rows=[e for e in self.events if e['kind']==kind]; times=sorted(e['duration_ms'] for e in rows)
            metrics[kind]=dict(count=len(rows),errors=sum(not e['ok'] for e in rows),p50_ms=times[len(times)//2],p95_ms=times[min(len(times)-1,int(len(times)*.95))],max_ms=max(times))
        self.summary['metrics']=metrics
        self.summary['elapsed_s']=round(time.monotonic()-self.started,2)
        (self.output/'summary.json').write_text(json.dumps(self.summary,indent=2))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('workspace');p.add_argument('output',type=Path)
    p.add_argument('--resume-after-checkin',action='store_true')
    p.add_argument('--registration-limit',type=int,default=2528);p.add_argument('--registration-only',action='store_true')
    args=p.parse_args()
    if not 1<=args.registration_limit<=2528: p.error('registration limit must be 1–2528')
    if not args.registration_only and args.registration_limit != 2528:
        p.error('Partial registration requires --registration-only')
    test=Rehearsal(Local(args.workspace),args.output)
    try:
        test.start();test.registration(args.registration_limit)
        test.summary['status']='registration_passed'
        if not args.registration_only:
            from workflows import Workflows
            Workflows(test).run(resume_after_checkin=args.resume_after_checkin)
            test.summary['status']='failed' if any(not e['ok'] for e in test.events) else 'closeout_passed_pending_reconciliation'
    except Exception as e:
        test.summary.update(status='failed',error=str(e));test.log('run_failed',error=str(e));raise
    finally: test.finish()
    if test.summary['status']=='failed':raise SystemExit(1)

if __name__=='__main__': main()
