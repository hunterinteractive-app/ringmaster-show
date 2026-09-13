"""Resume a retained local failed registration day without replacing identities.

Uses the application's compiled Dart write helper under each original owner's
token. Original evidence remains immutable; recovery has a separate output.
"""
import argparse
import hashlib
import json
from pathlib import Path
import secrets
import subprocess
import uuid
from local import Local, SHOW, uid
from run import Rehearsal
from registration_retry import retry

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace');parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path);parser.add_argument('--dart-client',required=True)
    args=parser.parse_args();lab=Local(args.workspace);out=args.output
    out.mkdir(parents=True,exist_ok=False)
    for name in ('manifest.json','expected-entries.json'):(out/name).write_bytes((args.source/name).read_bytes())
    failures=json.loads((args.source/'registration-day-30.json').read_text())['failures']
    missing=sorted({r['exhibitor'] for r in failures});assert len(missing)==7
    test=Rehearsal(lab,out);records=[];people={}
    completed_filter=','.join("'"+uid('952',n)+"'" for n in missing)
    def unchanged_hash():
        data={table:lab.rows(f"select * from {table} where show_id='{SHOW}' and exhibitor_id not in ({completed_filter}) order by id") for table in ('entries','show_payments')}
        return {k:hashlib.sha256(json.dumps(v,sort_keys=True).encode()).hexdigest() for k,v in data.items()}
    before=unchanged_hash();(out/'existing-completed-hashes.json').write_text(json.dumps(before,indent=2))
    def dart(token,batches,lose=False,success=True):
        payload=dict(url=lab.url,anon=lab.anon,token=token,batches=batches,lose_response=lose)
        result=subprocess.run([args.dart_client],input=json.dumps(payload),text=True,capture_output=True,timeout=120)
        if not success:
            assert result.returncode and ('42501' in result.stderr or '23505' in result.stderr),result.stderr[-1000:]
            return dict(denied=True)
        if result.returncode:raise RuntimeError(result.stderr[-2000:])
        return json.loads(result.stdout)
    try:
        test.start()
        for n in missing:
            rows=test.by_exhibitor[n]
            accounts=lab.rows(f"select id,email from auth.users where email like 'exhibitor-{n}-%@example.invalid'")
            assert len(accounts)==1,accounts
            account=accounts[0];password=secrets.token_urlsafe(32)
            # Rotate only this synthetic local identity, then use actual password Auth.
            lab.request('/auth/v1/admin/users/'+account['id'],{'password':password},method='PUT')
            login=lab.request('/auth/v1/token?grant_type=password',{'email':account['email'],'password':password},lab.anon)
            assert login['user']['id']==account['id'];token=login['access_token'];people[n]=token
            existing_entries=lab.rows(f"select id from entries where show_id='{SHOW}' and exhibitor_id='{uid('952',n)}'")
            assert len(existing_entries) in (0,len(rows))
            if existing_entries:
                records.append(dict(exhibitor=n,status='already_completed',entries=len(rows)));continue
            lookup=retry(test,'account_lookup',n,lambda:lab.edge('claim-or-import-exhibitor',{'action':'lookup'},token),function=True)
            assert lookup['status'] in ('club_not_found','already_exists'),lookup
            exhibitor=dict(id=uid('952',n),owner_user_id=account['id'],display_name=f'Synthetic Exhibitor {n}',
                first_name='Synthetic',last_name=f'Exhibitor {n:04d}',exhibitor_number=str(n),
                email=account['email'],city='Localtown',state='IN',zip='46000',arba_number=f'LOCAL-{n}',
                address_line1='1 Synthetic Lane',type='open' if n<=test.manifest['sections'][0]['exhibitors'] else 'youth',created_for_show_id=SHOW)
            animals=[dict(id=uid('953',e['n']),owner_user_id=account['id'],species=e['species'],tattoo=e['tattoo'],
                name=e['animal_name'],breed=e['breed'],variety=e['variety'],class_name=e['class_name'],sex=e['sex']) for e in rows]
            carts=lab.rows(f"select id from entry_carts where show_id='{SHOW}' and user_id='{account['id']}' and status='active'")
            assert len(carts)<=1;c=carts[0]['id'] if carts else str(uuid.uuid4())
            cart=dict(id=c,show_id=SHOW,user_id=account['id'],status='active')
            items=[dict(id=uid('959',e['n']),cart_id=c,exhibitor_id=exhibitor['id'],animal_id=uid('953',e['n']),
                **{k:e[k] for k in ('section_id','species','tattoo','animal_name','breed','variety','class_name','sex')}) for e in rows]
            batches=[dict(table=t,rows=r) for t,r in [('exhibitors',[exhibitor]),('animals',animals),('entry_carts',[cart]),('entry_cart_items',items)]]
            saved=test.measured('dart_registration_recovery',n,lambda:dart(token,batches,lose=n==missing[0]))
            replay=test.measured('dart_registration_replay',n,lambda:dart(token,batches))
            assert all(sorted(a['ids'])==sorted(b['ids']) for a,b in zip(saved['results'],replay['results']))
            if n!=missing[0]:
                assert lab.request('/rest/v1/animals?select=id&id=eq.'+animals[0]['id'],token=people[missing[0]])==[]
                dart(people[missing[0]],[dict(table='animals',rows=animals)],success=False)
            quote=test.measured('resumed_checkout',n,lambda:test.checkout_with_client_retry(c,token,n))
            assert quote['amount_total_cents']==len(rows)*500,quote
            obj=test.providers.checkout(quote['checkout_session_id']);event='evt_local_'+uuid.uuid4().hex
            test.measured('resumed_payment',n,lambda:test.webhook(obj,event))
            assert test.webhook(obj,event).get('duplicate') is True
            test.wait_for_registration(c,token,n,len(rows))
            record=dict(exhibitor=n,entries=len(rows),reused_cart=bool(carts),cart_id=c,
                owner_user_id=account['id'],write_replay_verified=True,lost_response_injected=n==missing[0],dart=saved)
            records.append(record);(out/'recovered.json').write_text(json.dumps(records,indent=2))
            test.log('registration_recovered',exhibitor=n,entries=len(rows),reused_cart=bool(carts))
        actual=lab.rows(f"select animal_id,exhibitor_id,section_id,species,tattoo,animal_name,breed,variety,class_name,sex,payment_status from entries where show_id='{SHOW}'")
        by_n={int(r['animal_id'][-12:]):r for r in actual};assert len(by_n)==len(actual)==len(test.entries)
        for e in test.entries:
            expected=dict(animal_id=uid('953',e['n']),exhibitor_id=uid('952',e['exhibitor']),payment_status='paid',**{k:e[k] for k in ('section_id','species','tattoo','animal_name','breed','variety','class_name','sex')})
            assert by_n[e['n']]==expected, e['n']
        paid=lab.rows(f"select exhibitor_id,cart_id,payment_session_id,total_cents from show_payments where show_id='{SHOW}' and payment_status='paid'")
        assert len(paid)==len(test.by_exhibitor)==len({p['cart_id'] for p in paid})==len({p['payment_session_id'] for p in paid})
        assert all(p['total_cents']==len(test.by_exhibitor[int(p['exhibitor_id'][-12:])])*500 for p in paid)
        assert unchanged_hash()==before,'Previously completed purchases changed'
        balances=lab.rows(f"select count(*) n,sum(balance_due_cents) due,sum(paid_online_cents) paid from show_exhibitor_balances where show_id='{SHOW}'")[0]
        assert balances==dict(n=len(paid),due=0,paid=len(actual)*500),balances
        assert int(lab.sql(f"select count(*) from auth.users where email ~ '^exhibitor-[0-9]+-[a-f0-9]+@example.invalid$'"))==len(paid)
        assert int(lab.sql(f"select count(*) from show_task_queue where show_id='{SHOW}'"))==0
        test.summary.update(status='passed',checks=dict(recovered_registrations=len(missing),recovered_entries=sum(len(test.by_exhibitor[n]) for n in missing),
            entries=len(actual),paid_purchasers=len(paid),paid_cents=sum(p['total_cents'] for p in paid),
            exact_entry_fields=True,one_payment_per_cart_and_session=True,previous_completed_rows_unchanged=True,
            original_accounts_reused=True,dart_write_replay=True,cross_owner_rls_denied=True,original_run_still_failed=True))
        test.log('recovery_passed',**test.summary['checks'])
    except Exception as error:
        test.summary.update(status='failed',error=str(error));raise
    finally:test.finish()

if __name__=='__main__':main()
