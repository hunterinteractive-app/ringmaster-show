"""Probe the restored real account Edge Function using only synthetic accounts."""
import json
from pathlib import Path
import sys
import uuid
from local import Local,ROOT,ApiError,sql_quote as q
from run import Rehearsal

lab=Local(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(exist_ok=True,parents=True)
# Reuse only population descriptions; this probe never runs registration.
import shutil
for name in ('manifest.json','expected-final-entries.json'):
    shutil.copy2(Path(sys.argv[3])/name,out/name)
r=Rehearsal(lab,out);checks={}
try:
    r.start()
    person=lab.person('account-setup-probe')
    result=lab.edge('claim-or-import-exhibitor',{'action':'lookup'},person['token'])
    assert result['status']=='club_not_found',result
    checks['new_account_manual_setup_available']=True
    exhibitor=str(uuid.uuid4())
    lab.sql(f"insert into exhibitors(id,display_name,showing_name,first_name,last_name,email,phone,address_line1,city,state,zip,type,is_active,is_test,is_merged) values('{exhibitor}','Synthetic Claim','Synthetic Claim','Synthetic','Claim',{q(person['email'])},'5555550100','1 Synthetic Lane','Localtown','IN','46000','open',true,false,false);")
    result=lab.edge('claim-or-import-exhibitor',{'action':'lookup'},person['token'])
    assert result['status']=='claim_confirmation_required' and result['match']['id']==exhibitor,result
    checks['matching_account_requires_confirmation']=True
    stranger=lab.person('account-claim-stranger')
    try:
        lab.edge('claim-or-import-exhibitor',{'action':'claim','exhibitor_id':exhibitor},stranger['token'])
        raise AssertionError('Unrelated user claimed the exhibitor')
    except ApiError as e:assert e.code==403,e
    checks['foreign_claim_denied']=True
    result=lab.edge('claim-or-import-exhibitor',{'action':'claim','exhibitor_id':exhibitor},person['token'])
    assert result['status']=='claimed' and result['exhibitor_id']==exhibitor,result
    for _ in range(3):
        result=lab.edge('claim-or-import-exhibitor',{'action':'lookup'},person['token'])
        assert result['status']=='already_exists' and result['exhibitor_id']==exhibitor,result
    checks['claim_and_repeat_lookup_passed']=True
    assert int(lab.sql(f"select count(*) from exhibitors where owner_user_id='{person['user_id']}'"))==1
    checks['no_duplicate_accounts']=True
    r.summary['status']='passed'
finally:
    r.summary['checks']=checks;r.finish()
    (out/'account-setup.json').write_text(json.dumps(dict(status=r.summary['status'],checks=checks),indent=2))
print(json.dumps(dict(status=r.summary['status'],checks=checks)))
