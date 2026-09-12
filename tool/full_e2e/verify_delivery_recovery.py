"""Retest real report sending, including provider acceptance followed by a stall."""
from collections import defaultdict
import hashlib,json,secrets,sys,time
from pathlib import Path
from local import Local,SHOW,selected_finalize_run
from run import Rehearsal

lab=Local(sys.argv[1]);out=Path(sys.argv[2]);source=Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=True)
for name in ('manifest.json','expected-final-entries.json'):(out/name).write_bytes((source/name).read_bytes())
test=Rehearsal(lab,out);nonce=secrets.token_hex(6)
run_id=selected_finalize_run(sys.argv[4:])
run_filter=f" and finalize_run_id='{run_id}'" if run_id else ''
test.summary['finalize_run_id']=run_id
try:
    test.start();person=lab.person('delivery-repair')
    lab.sql(f"insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{person['user_id']}','admin');")
    artifacts=lab.rows(f"select id,file_hash_sha256,metadata,report_name from show_report_artifacts where show_id='{SHOW}' and is_current and artifact_status='generated' and report_name in ('exhibitor_report','legs'){run_filter}")
    groups=defaultdict(list)
    for a in artifacts:groups[a['metadata']['exhibitor_id']].append(a)
    exhibitors={r['id']:r for r in lab.rows(f"select distinct x.id,x.email from exhibitors x join entries e on e.exhibitor_id=x.id where e.show_id='{SHOW}'")}
    selected=sorted(groups)[:250]
    test.providers.delay_next_resend_seconds=16
    sent=[]
    for index,eid in enumerate(selected):
        group=groups[eid];email=exhibitors[eid]['email']
        body=dict(show_id=SHOW,artifact_ids=[a['id'] for a in group],to=email,
            subject=f'LOCAL repair verification {nonce}',allow_legs=True)
        before=len(test.providers.emails);started=time.monotonic()
        result=test.measured('email_with_stall' if index==0 else 'email',index,
            lambda:lab.edge('send-report-email',body,person['token']))
        elapsed=time.monotonic()-started
        assert result['ok'] and not result.get('already_sent'),result
        assert len(test.providers.emails)==before+1,'A retried send duplicated the message'
        message=test.providers.emails[-1]
        assert message['id']==result['provider_message_id']
        assert message['to']==[email]
        allowed={a['file_hash_sha256'] for a in group}
        assert all(a['sha256'] in allowed for a in message['attachments'])
        exhibitor_hash=next(a['file_hash_sha256'] for a in group if a['report_name']=='exhibitor_report')
        assert exhibitor_hash in {a['sha256'] for a in message['attachments']}
        if index==0:
            assert 15<=elapsed<25,elapsed
            repeat=lab.edge('send-report-email',body,person['token'])
            assert repeat.get('already_sent') and len(test.providers.emails)==before+1
            test.summary['checks']['accepted_then_stalled_send']=dict(elapsed_s=elapsed,messages=1,replay_already_sent=True)
        sent.append(result['provider_message_id'])
        if (index+1)%50==0:test.log('delivery_progress',completed=index+1)
    logged=lab.rows(f"select count(distinct provider_message_id) messages from show_email_deliveries where show_id='{SHOW}' and subject='LOCAL repair verification {nonce}'")[0]['messages']
    assert logged==len(selected)==len(test.providers.emails)==len(set(sent))==250
    test.summary['checks']['complete_deliveries']=logged
    test.summary['status']='passed'
except Exception as e:test.summary.update(status='failed',error=str(e));raise
finally:test.finish()
