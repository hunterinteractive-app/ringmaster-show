"""250 new synthetic purchasers through Auth, cart, checkout and signed payment.

No precreated accounts, no sign-in semaphore; the server Auth pool is bounded.
The show is separate from the retained event and uses only local providers.
"""
from concurrent.futures import ThreadPoolExecutor,as_completed
import argparse
import json,os,secrets,sys,threading,time,uuid
from pathlib import Path
from local import Local,ROOT,SHOW,sql_quote as q
from run import Rehearsal

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('workspace');parser.add_argument('output',type=Path);parser.add_argument('source',type=Path)
parser.add_argument('--rounds',type=int,default=1)
parser.add_argument('--verify-stall',action='store_true')
args=parser.parse_args()
if not 1<=args.rounds<=8:parser.error('Use 1–8 rounds of 250 sessions')
lab=Local(args.workspace);out=args.output;source=args.source;out.mkdir(parents=True,exist_ok=False)
for name in ('manifest.json','expected-final-entries.json'):(out/name).write_bytes((source/name).read_bytes())
test=Rehearsal(lab,out);show=str(uuid.uuid4());section=str(uuid.uuid4());nonce=secrets.token_hex(6)
lab.sql(f"""begin;
insert into shows(id,name,start_date,end_date,is_test,is_published,payment_timing_mode,coop_numbering_mode,secretary_name,secretary_email,club_name)
values('{show}','LOCAL registration repair {nonce}',current_date+7,current_date+8,true,true,'online_or_at_show','separate','Synthetic Secretary','secretary@example.invalid','Synthetic Club');
insert into show_sections(id,show_id,kind,letter,display_name,sort_order) values('{section}','{show}','open','A','Open A',1);
insert into show_section_fee_settings(section_id,fee_per_entry) values('{section}',5);
insert into show_fee_settings(show_id,currency) values('{show}','usd');
insert into show_payment_settings(show_id,stripe_enabled) values('{show}',true);
insert into show_payment_account_links(show_id,provider,stripe_account_id,charges_enabled,account_status) values('{show}','stripe','acct_local_synthetic',true,'ready');
commit;""")
(out/'probe-show.json').write_text(json.dumps(dict(show_id=show,section_id=section,nonce=nonce)))
counts=[];stop=threading.Event()
def monitor():
    while not stop.is_set():
        try:counts.append(lab.rows("select count(*) connections,count(*) filter(where usename='supabase_auth_admin') auth_connections from pg_stat_activity")[0])
        except Exception:pass
        stop.wait(.5)

def buy(i):
    email=f'rush-{nonce}-{i}@example.invalid';password=secrets.token_urlsafe(32)
    auth=test.measured('public_signup',i,lambda:lab.request('/auth/v1/signup',{'email':email,'password':password},lab.anon,timeout=90))
    token=auth['access_token'];user=auth['user']['id']
    login=test.measured('password_signin',i,lambda:lab.request('/auth/v1/token?grant_type=password',{'email':email,'password':password},lab.anon,timeout=90))
    assert login['user']['id']==user
    lookup=test.measured('account_lookup',i,lambda:lab.edge('claim-or-import-exhibitor',{'action':'lookup'},token))
    assert lookup['status']=='club_not_found',lookup
    exhibitor=str(uuid.uuid4());cart=str(uuid.uuid4());animal=str(uuid.uuid4())
    test.measured('create_exhibitor',i,lambda:lab.request('/rest/v1/exhibitors',dict(id=exhibitor,owner_user_id=user,display_name=f'Rush {i}',first_name='Synthetic',last_name=f'Rush {i}',email=email,exhibitor_number=str(i),type='open',created_for_show_id=show),token))
    details=dict(species='rabbit',tattoo=f'R{i:05d}',breed='Mini Rex',variety='Black',class_name='Senior',sex='Buck')
    test.measured('create_animal',i,lambda:lab.request('/rest/v1/animals',dict(id=animal,owner_user_id=user,name='',**details),token))
    test.measured('create_cart',i,lambda:lab.request('/rest/v1/entry_carts',dict(id=cart,show_id=show,user_id=user,status='active'),token))
    test.measured('cart_item',i,lambda:lab.request('/rest/v1/entry_cart_items',dict(id=str(uuid.uuid4()),cart_id=cart,exhibitor_id=exhibitor,animal_id=animal,section_id=section,animal_name='',**details),token))
    quote=test.measured('checkout_session',i,lambda:test.checkout_with_client_retry(cart,token,i))
    assert quote['amount_total_cents']==500,quote
    replay=test.measured('checkout_replay',i,lambda:test.checkout_with_client_retry(cart,token,i))
    assert replay['checkout_session_id']==quote['checkout_session_id']
    obj=test.providers.checkout(quote['checkout_session_id']);event='evt_local_'+uuid.uuid4().hex
    test.measured('payment',i,lambda:test.webhook(obj,event))
    replay=test.measured('payment_replay',i,lambda:test.webhook(obj,event))
    assert replay.get('duplicate') is True
    return i

thread=threading.Thread(target=monitor,daemon=True);failures=[]
try:
    test.start();thread.start();test.log('rush_started',sessions=250)
    with ThreadPoolExecutor(max_workers=250) as pool:
        for round_index in range(args.rounds):
            for future in as_completed([pool.submit(buy,i) for i in range(round_index*250,(round_index+1)*250)]):
                try:future.result()
                except Exception as e:failures.append(str(e));test.log('rush_error',error=str(e))
            test.log('rush_round_completed',round=round_index+1,failures=len(failures))
    checks=lab.rows(f"select count(*) entries,count(distinct exhibitor_id) exhibitors,count(*) filter(where payment_status='paid') paid from entries where show_id='{show}'")[0]
    checks['auth_users']=int(lab.sql(f"select count(*) from auth.users where email like 'rush-{nonce}-%@example.invalid'"))
    checks['carts']=int(lab.sql(f"select count(*) from entry_carts where show_id='{show}'"))
    checks['provider_sessions']=len(test.providers.sessions)
    test.summary['checks'].update(reconciliation=checks,failures=failures,
        max_connections=max((r['connections'] for r in counts),default=0),
        max_auth_connections=max((r['auth_connections'] for r in counts),default=0))
    assert not failures,failures[:3]
    total=250*args.rounds
    assert checks==dict(entries=total,exhibitors=total,paid=total,auth_users=total,carts=total,provider_sessions=total),checks
    assert test.summary['checks']['max_auth_connections']<=20
    if args.verify_stall:
        from local import ApiError
        person=lab.person('bounded-account-stall')
        test.providers.delay_next_club_seconds=16
        started=time.monotonic()
        try:
            lab.edge('claim-or-import-exhibitor',{'action':'lookup'},person['token'])
            raise AssertionError('Stalled lookup unexpectedly succeeded')
        except ApiError as error:
            elapsed=time.monotonic()-started
            assert error.code==503 and 11<=elapsed<15,(error.code,elapsed)
        recovered=lab.edge('claim-or-import-exhibitor',{'action':'lookup'},person['token'])
        assert recovered['status']=='club_not_found'
        test.summary['checks']['bounded_account_stall']=dict(status=503,elapsed_s=round(elapsed,3),retry_recovered=True)
    test.summary['checks']['rounds']=args.rounds
    test.summary['status']='passed'
except Exception as error:
    test.summary.update(status='failed',error=str(error))
    raise
finally:
    stop.set()
    if thread.is_alive():thread.join()
    test.finish();(out/'connections.json').write_text(json.dumps(counts))
