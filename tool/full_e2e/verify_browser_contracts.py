"""Verify caller-specific staff PINs and the combined V2 closeout scope locally."""
import sys,json,shutil
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'tool/full_e2e'))
from local import Local,SHOW,ApiError
from run import Rehearsal
from workflows import Workflows
lab=Local(sys.argv[1]);out=Path(sys.argv[2]);source=Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=True)
for name in ('manifest.json','expected-final-entries.json'):shutil.copy2(source/name,out/name)
t=Rehearsal(lab,out)
try:
    # Real caller-specific PIN regeneration/read/validation. Keep PIN values out of evidence.
    p=lab.person('pin-repair');other=lab.person('pin-other')
    lab.sql(f"insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{p['user_id']}','admin');")
    lab.rpc('regenerate_my_show_staff_approval_pin',{'p_show_id':SHOW},p['token'])
    pin=lab.rpc('get_my_show_staff_approval_pin',{'p_show_id':SHOW},p['token'])
    assert len(pin)==1 and pin[0]['user_id']==p['user_id'] and len(pin[0]['pin_code'])==6
    valid=lab.rpc('validate_show_staff_pin',{'p_show_id':SHOW,'p_pin':pin[0]['pin_code']},p['token'])
    assert valid[0]['user_id']==p['user_id']
    assert lab.rpc('get_my_show_staff_approval_pin',{'p_show_id':SHOW},other['token'])==[]
    try:
        lab.rpc('regenerate_my_show_staff_approval_pin',{'p_show_id':SHOW},other['token'])
        raise AssertionError('Nonstaff regenerated a PIN')
    except ApiError:pass
    old=pin[0]['pin_code']
    lab.rpc('regenerate_my_show_staff_approval_pin',{'p_show_id':SHOW},p['token'])
    assert lab.rpc('validate_show_staff_pin',{'p_show_id':SHOW,'p_pin':old},p['token'])==[]
    t.summary['checks']['staff_pins']=dict(own_pin_read=True,foreign_pin_hidden=True,nonstaff_regeneration_denied=True,old_pin_revoked=True)
    query=f'/rest/v1/show_email_deliveries?show_id=eq.{SHOW}&select=id&limit=1'
    assert len(lab.request(query,token=p['token']))==1,'Staff cannot read delivery history'
    assert lab.request(query,token=other['token'])==[],'Unrelated users can read delivery history'
    t.summary['checks']['delivery_history_access']=dict(staff_read=True,unrelated_user_denied=True)
    flow=Workflows(t);flow.staff()
    assert all(lab.readiness(s,flow.people[110]['token'])['ready'] for s in (1,2))
    t.start();flow.finalize_combined()
    # finalize_combined asserts the exact V2 scope and complete exhibitor total.
    dashboard=t.summary['checks']['combined_dashboard']
    (out/'dashboard.json').write_text(json.dumps(dashboard,indent=2))
    t.summary['status']='passed'
except Exception as e:t.summary.update(status='failed',error=str(e));raise
finally:t.finish()
