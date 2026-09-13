"""Local signed callbacks, concurrent workers, transactional failure and crash recovery."""
import json,sys,time,subprocess,uuid
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from local import Local,SHOW,ApiError
from run import Rehearsal

lab=Local(sys.argv[1]);fixture=Path(sys.argv[2]);out=Path(sys.argv[3]);out.mkdir(exist_ok=False)
for name in ('manifest.json','expected-entries.json'):(out/name).write_bytes((fixture/name).read_bytes())
test=Rehearsal(lab,out);webhook=test.webhook;captured=[];checks={}
assert lab.project=='ringmaster-show-full-e2e-pf-0913'
def pause(value):lab.sql(f"select cron.alter_job(jobid,active=>{'false' if value else 'true'}) from cron.job where jobname='process-stripe-payment-events'")
def capture(obj,event):
    response=webhook(obj,event);assert response['received'] and response['queued'] and not response['processed'],response
    captured.append((obj,event));return response

def counts(cart):return lab.rows(f"select (select count(*) from entries where source_cart_id='{cart}') entries,(select count(*) from show_payments where cart_id='{cart}' and payment_status='paid') payments")[0]
def state(event):return lab.rows(f"select state,attempts,last_error from payment_processing_private.stripe_events where event_id='{event}'")[0]
def process():return lab.rpc('process_pending_stripe_payment_events',{'p_limit':25})
def entry_blocker(body):
    lab.sql("create or replace function payment_processing_private.synthetic_entry_fault() returns trigger language plpgsql as $f$ begin "+body+" return new; end $f$; create trigger synthetic_payment_queue_fault before insert on entries for each row execute function payment_processing_private.synthetic_entry_fault();")
def clear_blocker():lab.sql('drop trigger if exists synthetic_payment_queue_fault on entries; drop function if exists payment_processing_private.synthetic_entry_fault();')
try:
    pause(True);test.start();test.webhook=capture
    for name in ('enqueue_stripe_payment_event','process_pending_stripe_payment_events','get_stripe_payment_queue_health'):
        params={'p_event_id':'denied','p_event_type':'test','p_payload':{}} if name=='enqueue_stripe_payment_event' else {}
        try:lab.rpc(name,params,lab.anon)
        except ApiError as error:assert error.code in (401,403),error
        else:raise AssertionError('Anonymous queue access allowed')
    checks['anonymous_access_denied']=True
    test.register(18,wait_for_completion=False);obj,event=captured[-1];cart=obj['metadata']['cart_id']
    assert counts(cart)==dict(entries=0,payments=0)
    with ThreadPoolExecutor(max_workers=8) as pool:replies=list(pool.map(lambda _:webhook(obj,event),range(8)))
    assert all(r['duplicate'] and r['queued'] and not r['processed'] for r in replies)
    changed={**obj,'amount_total':obj['amount_total']+1}
    try:webhook(changed,event)
    except ApiError as error:assert error.code==503,error
    else:raise AssertionError('Changed duplicate payload accepted')
    entry_blocker("raise exception 'Synthetic transaction failure';")
    assert process()==dict(completed=0,failed=1)
    assert counts(cart)==dict(entries=0,payments=0) and state(event)['attempts']==1
    clear_blocker();lab.sql(f"update payment_processing_private.stripe_events set next_attempt_at=now() where event_id='{event}'")
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(lambda _:process(),range(2)))
    assert sum(r['completed'] for r in results)==1
    assert counts(cart)==dict(entries=len(test.by_exhibitor[18]),payments=1)
    replay=webhook(obj,event);assert replay['duplicate'] and replay['processed'] and not replay['queued']
    checks.update(durable_before_completion=True,concurrent_delivery_replays=8,payload_change_rejected=True,transaction_failure_rolled_back=True,concurrent_workers_exactly_once=True)
    test.register(19,wait_for_completion=False);obj,event=captured[-1];cart=obj['metadata']['cart_id']
    entry_blocker('perform pg_sleep(15);')
    worker=subprocess.Popen(['docker','exec',lab.container,'psql','-U','postgres','-d','postgres','-At','-c',"set application_name='payment-worker-interruption-probe'; select payment_processing_private.process_stripe_events(1)"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    deadline=time.monotonic()+15;pid=None
    while time.monotonic()<deadline:
        rows=lab.rows("select pid from pg_stat_activity where application_name='payment-worker-interruption-probe' and wait_event='PgSleep'")
        if rows:pid=rows[0]['pid'];break
        time.sleep(.1)
    assert pid,'Worker did not reach the injected interruption point'
    lab.sql(f'select pg_terminate_backend({pid})');worker.communicate(timeout=10);assert worker.returncode
    clear_blocker();assert counts(cart)==dict(entries=0,payments=0);assert state(event)['state']=='pending' and state(event)['attempts']==0
    # The scheduler, without a manual worker call, must recover committed work.
    pause(False);deadline=time.monotonic()+15
    while time.monotonic()<deadline and state(event)['state']!='completed':time.sleep(.2)
    assert state(event)['state']=='completed'
    assert counts(cart)==dict(entries=len(test.by_exhibitor[19]),payments=1)
    checks.update(worker_interruption_rolled_back=True,cron_recovered_without_callback_redelivery=True)
    pause(True);test.register(20,wait_for_completion=False);obj,event=captured[-1];cart=obj['metadata']['cart_id']
    # A separately signed but wrong amount must never finalize its cart.
    lab.sql(f"delete from payment_processing_private.stripe_events where event_id='{event}'; delete from show_payment_events where provider='stripe' and event_id='{event}'")
    wrong={**obj,'amount_total':obj['amount_total']+1};webhook(wrong,event)
    assert process()==dict(completed=0,failed=1);assert state(event)['state']=='blocked'
    assert counts(cart)==dict(entries=0,payments=0)
    health=lab.rpc('get_stripe_payment_queue_health',{});assert health['blocked']==1
    checks.update(wrong_amount_blocked=True,blocked_item_visible=True)
    # Remove only this deliberately invalid synthetic notification. Save the
    # evidence first, then deliver the authentic fixture amount as a new event.
    (out/'blocked-event.json').write_text(json.dumps(dict(event=event,state=state(event),health=health),indent=2))
    lab.sql(f"delete from payment_processing_private.stripe_events where event_id='{event}'; delete from show_payment_events where provider='stripe' and event_id='{event}'")
    webhook(obj,'evt_local_'+uuid.uuid4().hex);process()
    assert counts(cart)==dict(entries=len(test.by_exhibitor[20]),payments=1)
    checks['all_test_carts_exactly_one_paid_record']=True
    test.summary.update(status='passed',checks=checks)
finally:
    clear_blocker();pause(False);test.finish()
print(json.dumps(checks))
