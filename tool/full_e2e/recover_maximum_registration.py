"""Recover only incomplete original synthetic purchases in an isolated max-run clone.

Reuses existing accounts, animals, carts and saved payment quotes. Simulates
redelivery of local provider notifications; never contacts real payment services.
The original failed database and evidence remain untouched.
"""
import argparse,hashlib,json,secrets,threading,uuid
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor,as_completed
from pathlib import Path
from local import Local,SHOW,uid
from registration_retry import insert
from run import Rehearsal


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('workspace');p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    args=p.parse_args();lab=Local(args.workspace)
    assert lab.project=='ringmaster-show-full-e2e-pc-0913'
    out=args.output;out.mkdir(parents=True,exist_ok=False)
    for name in ('manifest.json','expected-entries.json'):(out/name).write_bytes((args.source/name).read_bytes())
    test=Rehearsal(lab,out)
    base=f"show_id='{SHOW}' and exhibitor_id::text like '95200000-%'"
    existing={int(r['exhibitor_id'][-12:]):r['entries'] for r in lab.rows(f'select exhibitor_id,count(*) entries from entries where {base} group by exhibitor_id')}
    assert all(count==len(test.by_exhibitor[n]) for n,count in existing.items()),'Partial entry set needs individual reconciliation'
    missing=sorted(set(test.by_exhibitor)-set(existing));assert missing
    complete=','.join("'"+uid('952',n)+"'" for n in existing)
    def hashes():
        return {table:lab.sql(f"select md5(string_agg(row_to_json(t)::text,'|' order by id)) from (select * from {table} where show_id='{SHOW}' and exhibitor_id in ({complete})) t").strip() for table in ('entries','show_payments')}
    before=hashes();(out/'completed-before.json').write_text(json.dumps(before))
    users=defaultdict(list)
    for r in lab.rows("select id,email from auth.users where email ~ '^exhibitor-[0-9]+-[a-f0-9]+@example.invalid$'"):
        users[int(r['email'].split('-')[1])].append(r)
    assert all(len(users[n])<=1 for n in missing),'Ambiguous existing accounts'
    records=[];failures=[];lock=threading.Lock()
    def recover(n):
        rows=test.by_exhibitor[n];accounts=users[n]
        if accounts:
            account=accounts[0]
            link=lab.request('/auth/v1/admin/generate_link',dict(type='magiclink',email=account['email']))
            login=lab.request('/auth/v1/verify',dict(type='magiclink',token_hash=link['hashed_token']))
            person=dict(user_id=login['user']['id'],email=account['email'],token=login['access_token'])
            assert person['user_id']==account['id']
        else:person=lab.person(f'exhibitor-{n}')
        token=person['token'];owner=person['user_id'];exhibitor=uid('952',n)
        x=dict(id=exhibitor,owner_user_id=owner,display_name=f'Synthetic Exhibitor {n}',first_name='Synthetic',last_name=f'Exhibitor {n:04d}',exhibitor_number=str(n),email=person['email'],city='Localtown',state='IN',zip='46000',arba_number=f'LOCAL-{n}',address_line1='1 Synthetic Lane',type='open' if n<=test.manifest['sections'][0]['exhibitors'] else 'youth',created_for_show_id=SHOW)
        insert(test,'exhibitors',x,token,n)
        animals=[dict(id=uid('953',e['n']),owner_user_id=owner,species=e['species'],tattoo=e['tattoo'],name=e['animal_name'],breed=e['breed'],variety=e['variety'],class_name=e['class_name'],sex=e['sex']) for e in rows]
        insert(test,'animals',animals,token,n)
        carts=lab.rows(f"select id from entry_carts where show_id='{SHOW}' and user_id='{owner}' and status='active'")
        assert len(carts)<=1
        cart=carts[0]['id'] if carts else str(uuid.uuid4())
        insert(test,'entry_carts',dict(id=cart,show_id=SHOW,user_id=owner,status='active'),token,n)
        items=[dict(id=uid('959',e['n']),cart_id=cart,exhibitor_id=exhibitor,animal_id=uid('953',e['n']),**{k:e[k] for k in ('section_id','species','tattoo','animal_name','breed','variety','class_name','sex')}) for e in rows]
        insert(test,'entry_cart_items',items,token,n)
        attempts=lab.rows(f"select s.* from show_payment_sessions s join entry_carts c on c.active_payment_session_id=s.id where c.id='{cart}' and s.provider='stripe' and s.provider_session_id is not null")
        reused_attempt=bool(attempts)
        if attempts:
            a=attempts[0];assert a['provider_session_id'].startswith('cs_test_local_')
            intents=lab.rows(f"select provider_payment_id from show_payment_events where payment_session_id='{a['id']}' and provider_payment_id is not null order by received_at limit 1")
            intent=a.get('provider_payment_id') or (intents[0]['provider_payment_id'] if intents else 'pi_local_'+uuid.uuid4().hex)
            obj=dict(id=a['provider_session_id'],object='checkout.session',metadata=dict(cart_id=cart,payment_session_id=a['id'],provider='stripe',quote_hash=a['quote_hash']),amount_total=a['expected_amount_cents'],currency=a['expected_currency'],payment_status='paid',payment_intent=intent)
        else:
            quote=test.checkout_with_client_retry(cart,token,n)
            obj=test.providers.checkout(quote['checkout_session_id'])
        assert obj['amount_total']==len(rows)*500
        event='evt_local_recovery_'+uuid.uuid4().hex
        test.webhook(obj,event);test.wait_for_registration(cart,token,n,len(rows))
        record=dict(exhibitor=n,entries=len(rows),account_reused=bool(accounts),cart_reused=bool(carts),attempt_reused=reused_attempt)
        with lock:
            records.append(record)
            with (out/'recovered.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
            if len(records)%100==0:test.log('recovery_progress',completed=len(records),total=len(missing))
    try:
        test.start();test.log('controlled_recovery_started',incomplete=len(missing),concurrency=12)
        with ThreadPoolExecutor(max_workers=12) as pool:
            jobs={pool.submit(lambda n=n:test.measured('recover_registration',n,lambda:recover(n))):n for n in missing}
            for job in as_completed(jobs):
                try:job.result()
                except Exception as e:failures.append(dict(exhibitor=jobs[job],error=str(e)));test.log('recovery_failed',**failures[-1])
        actual=lab.rows(f"select animal_id,exhibitor_id,section_id,species,tattoo,animal_name,breed,variety,class_name,sex,payment_status from entries where {base}")
        by_n={int(r['animal_id'][-12:]):r for r in actual}
        assert len(by_n)==len(actual)==len(test.entries),(len(actual),len(test.entries),failures[:3])
        for e in test.entries:
            wanted=dict(animal_id=uid('953',e['n']),exhibitor_id=uid('952',e['exhibitor']),payment_status='paid',**{k:e[k] for k in ('section_id','species','tattoo','animal_name','breed','variety','class_name','sex')})
            assert by_n[e['n']]==wanted,e['n']
        paid=lab.rows(f"select exhibitor_id,cart_id,payment_session_id,total_cents from show_payments where {base} and payment_status='paid'")
        assert len(paid)==len(test.by_exhibitor)==len({p['cart_id'] for p in paid})==len({p['payment_session_id'] for p in paid})
        assert all(p['total_cents']==len(test.by_exhibitor[int(p['exhibitor_id'][-12:])])*500 for p in paid)
        after=hashes();assert after==before,'Previously complete rows changed'
        assert not failures,failures[:3]
        test.summary.update(status='passed',checks=dict(recovered_purchasers=len(records),recovered_entries=sum(r['entries'] for r in records),entries=len(actual),paid_purchasers=len(paid),paid_cents=sum(p['total_cents'] for p in paid),accounts_reused=sum(r['account_reused'] for r in records),carts_reused=sum(r['cart_reused'] for r in records),attempts_reused=sum(r['attempt_reused'] for r in records),previous_completed_rows_unchanged=True,original_failed_run_unchanged=True,exact_entry_fields=True))
        test.log('recovery_passed',checks=test.summary['checks'])
    except Exception as e:test.summary.update(status='failed',error=str(e),failures=failures);raise
    finally:test.finish()
if __name__=='__main__':main()
