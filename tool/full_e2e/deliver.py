"""Exercise production report delivery against a synthetic local receiver."""
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time
from local import Local, SHOW
from run import Rehearsal
from workflows import Workflows


def main():
    lab=Local(sys.argv[1]);out=Path(sys.argv[2]);test=Rehearsal(lab,out)
    try:
        test.start()
        admin=lab.person('delivery-admin')
        lab.sql(f"insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{admin['user_id']}','admin'); insert into show_managers(show_id,user_id,can_manage_entries,can_manage_settings,can_finalize) values ('{SHOW}','{admin['user_id']}',true,true,true);")
        from finish_arba import save_synthetic_details
        test.summary['checks']['arba_settings']=save_synthetic_details(lab,admin)
        name=lab.rows(f"select name from shows where id='{SHOW}'")[0]['name']
        artifacts=lab.rows(f"select * from show_report_artifacts where show_id='{SHOW}' and is_current and artifact_status='generated'")
        exhibitors={r['id']:r for r in lab.rows(f"select distinct x.id,x.email,x.display_name from exhibitors x join entries e on e.exhibitor_id=x.id where e.show_id='{SHOW}'")}
        groups=defaultdict(list)
        for a in artifacts:
            if a['report_name'] in ('exhibitor_report','legs'):groups[a['metadata']['exhibitor_id']].append(a)
        sent=[];errors=[]
        # One sequential exhibitor-email workflow, matching the bulk-send UI.
        for index,(eid,x) in enumerate(sorted(exhibitors.items())):
            group=groups.get(eid,[])
            if not any(a['report_name']=='exhibitor_report' for a in group):
                errors.append(dict(exhibitor=eid,error='Missing generated exhibitor report'));continue
            body=dict(show_id=SHOW,artifact_ids=[a['id'] for a in group],to=x['email'],
                recipient_name=x['display_name'],subject=name+' - Exhibitor Reports',
                message='Synthetic local rehearsal reports.',allow_legs=True)
            try:
                result=test.measured('exhibitor_email',index,lambda:lab.edge('send-report-email',body,admin['token']))
                sent.append(dict(exhibitor=eid,result=result,artifact_ids=body['artifact_ids']))
                if index==0:
                    before=len(test.providers.emails)
                    replay=lab.edge('send-report-email',body,admin['token'])
                    test.summary['checks']['email_replay']=dict(already_sent=replay.get('already_sent'),new_messages=len(test.providers.emails)-before)
            except Exception as e:errors.append(dict(exhibitor=eid,error=str(e)))
            if (index+1)%100==0:test.log('exhibitor_delivery_progress',attempted=index+1,errors=len(errors))
            if len(errors)>=10:break
        (out/'exhibitor-delivery-results.json').write_text(json.dumps(dict(sent=sent,errors=errors),indent=2))
        club=defaultdict(list)
        for a in artifacts:
            if a['report_name'] in ('sweepstakes_report','breed_results_detail_report','details_by_breed','exh_by_breed','best_display_report'):
                m=a['metadata'];key=(m.get('breed_name',''),m.get('club_name',''),m.get('sweepstakes_email',''))
                club[key].append(a)
        requests=[]
        for (breed,club_name,email),group in sorted(club.items()):
            # State club reports are generated per section but delivered together.
            label=(club_name+' Rabbit') if not breed else breed
            requests.append(dict(artifact_ids=[a['id'] for a in group],to=email or 'club@example.invalid',
                subject=name+' - '+label+' Club Reports',message='Synthetic local rehearsal club reports.'))
        club_result=test.measured('club_batch_email',0,lambda:lab.edge('send-club-report-batch',dict(show_id=SHOW,deliveries=requests),admin['token']))
        (out/'club-delivery-results.json').write_text(json.dumps(dict(requests=requests,result=club_result),indent=2))
        test.summary['checks']['exhibitor_delivery']=dict(targets=2528,attempted=len(sent)+len(errors),responses=len(sent),errors=errors)
        test.summary['checks']['club_delivery']=club_result
        # The real UI records these only after sending. Do not pre-seed them.
        if not errors and len(sent)==2528 and not club_result.get('failed_count'):
            stamp=datetime.now(timezone.utc).isoformat()
            try:
                lab.request('/rest/v1/show_closeout_state?show_id=eq.'+SHOW,
                    dict(exhibitor_emails_sent_at=stamp,club_reports_sent_at=stamp),admin['token'],method='PATCH')
                test.summary['checks']['delivery_state']=lab.rows(f"select exhibitor_emails_sent_at,club_reports_sent_at from show_closeout_state where show_id='{SHOW}'")
                assert test.summary['checks']['delivery_state'] and all(test.summary['checks']['delivery_state'][0].values()),'Delivery dates did not persist'
            except Exception as e:test.summary['checks']['delivery_state_error']=str(e)
        # Explicit ARBA generation is its own real application action.
        arba=lab.rows(f"select a.id,a.finalize_run_id,f.scope_key from show_report_artifacts a join show_finalize_runs f on f.id=a.finalize_run_id where a.show_id='{SHOW}' and a.report_name='arba_report' and a.is_current")
        for a in arba:
            lab.rpc('requeue_closeout_artifacts',dict(p_show_id=SHOW,p_finalize_run_id=a['finalize_run_id'],p_scope_key=a['scope_key'],p_report_name='arba_report',p_artifact_id=a['id']),admin['token'])
        flow=Workflows(test);flow.start_workers()
        for _ in range(60):
            status=flow.queue()
            if not status.get('queued') and not status.get('running'):break
            time.sleep(5)
        ready=lab.rows(f"select id,artifact_status from show_report_artifacts where show_id='{SHOW}' and report_name='arba_report' and is_current")
        test.summary['checks']['arba_generation']=ready
        if len(ready)==2 and all(r['artifact_status']=='generated' for r in ready):
            test.summary['checks']['arba_delivery']=test.measured('arba_email',0,lambda:lab.edge('send-report-email',dict(show_id=SHOW,artifact_ids=[r['id'] for r in ready],to='arba@example.invalid',subject=name+' - ARBA Show Report'),admin['token']))
        test.summary['status']='delivery_coverage_finished_original_failures_retained'
    except Exception as e:
        test.summary.update(status='failed',error=str(e));raise
    finally:
        test.finish()
        (out/'delivery-summary.json').write_bytes((out/'summary.json').read_bytes())

if __name__=='__main__':main()
