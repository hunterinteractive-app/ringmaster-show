"""Complete the synthetic ARBA settings and retry after recording fixture gaps."""
from datetime import datetime,timezone
import json
from pathlib import Path
import sys
import time
from local import Local,SHOW
from run import Rehearsal
from workflows import Workflows
from restore_closeout_access import restore

def save_synthetic_details(lab,p):
    fields=dict(show_id=SHOW,secretary_name='Synthetic Secretary',secretary_address='1 Synthetic Lane, Localtown IN 46000',
        secretary_email='secretary@example.invalid',secretary_phone='317-555-0100',
        superintendent_name='Synthetic Superintendent',superintendent_arba_number='LOCAL-SUPER',
        sweepstakes_issue=False,sweepstakes_club=None,official_protest=False,arba_report_filed=None)
    existing=lab.rows(f"select show_id from show_arba_report_details where show_id='{SHOW}'")
    if existing:lab.request('/rest/v1/show_arba_report_details?show_id=eq.'+SHOW,fields,p['token'],method='PATCH')
    else:lab.request('/rest/v1/show_arba_report_details',fields,p['token'])
    saved=lab.rows(f"select * from show_arba_report_details where show_id='{SHOW}'")[0]
    assert all(saved[k]==v for k,v in fields.items()),'ARBA settings write did not persist'
    return fields

def main():
    lab=Local(sys.argv[1]);out=Path(sys.argv[2]);test=Rehearsal(lab,out)
    try:
        restore(lab);test.start();p=lab.person('arba-admin')
        lab.sql(f"insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{p['user_id']}','admin'); insert into show_managers(show_id,user_id,can_manage_entries,can_manage_settings,can_finalize) values ('{SHOW}','{p['user_id']}',true,true,true);")
        # Administrative form writes, with the same authenticated Data API.
        fields=save_synthetic_details(lab,p)
        delivered=lab.rows(f"select report_name,count(distinct artifact_id) n from show_email_deliveries where show_id='{SHOW}' and delivery_status='sent' group by 1")
        assert next(r['n'] for r in delivered if r['report_name']=='exhibitor_report')==2528
        stamp=datetime.now(timezone.utc).isoformat()
        lab.request('/rest/v1/show_closeout_state?show_id=eq.'+SHOW,dict(exhibitor_emails_sent_at=stamp,club_reports_sent_at=stamp),p['token'],method='PATCH')
        dates=lab.rows(f"select exhibitor_emails_sent_at,club_reports_sent_at from show_closeout_state where show_id='{SHOW}'")[0]
        assert all(dates.values()),'Delivery dates did not persist'
        test.summary['checks']['saved_settings']=fields;test.summary['checks']['saved_delivery_dates']=dates
        rows=lab.rows(f"select a.id,a.finalize_run_id,f.scope_key from show_report_artifacts a join show_finalize_runs f on f.id=a.finalize_run_id where a.show_id='{SHOW}' and a.report_name='arba_report' and a.is_current")
        for a in rows:lab.rpc('requeue_closeout_artifacts',dict(p_show_id=SHOW,p_finalize_run_id=a['finalize_run_id'],p_scope_key=a['scope_key'],p_report_name='arba_report',p_artifact_id=a['id']),p['token'])
        flow=Workflows(test);flow.start_workers()
        for _ in range(60):
            status=flow.queue()
            if not status.get('queued') and not status.get('running'):break
            time.sleep(5)
        ready=lab.rows(f"select id,artifact_status from show_report_artifacts where show_id='{SHOW}' and report_name='arba_report' and is_current")
        test.summary['checks']['arba_generation']=ready
        assert len(ready)==2 and all(r['artifact_status']=='generated' for r in ready),ready
        test.summary['checks']['arba_delivery']=test.measured('arba_email',0,lambda:lab.edge('send-report-email',dict(show_id=SHOW,artifact_ids=[r['id'] for r in ready],to='arba@example.invalid',subject='LOCAL E2E Convention 25711 - ARBA Show Report'),p['token']))
        test.summary['status']='arba_passed_after_fixture_completion'
    except Exception as e:test.summary.update(status='failed',error=str(e));raise
    finally:
        test.finish();(out/'arba-final-summary.json').write_bytes((out/'summary.json').read_bytes())

if __name__=='__main__':main()
