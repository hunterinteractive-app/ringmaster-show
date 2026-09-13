import json, subprocess, time, sys
from pathlib import Path
base=Path(sys.argv[1]).resolve()
assert str(base).startswith('/Users/zaynehunter/Dev/RingMasterShow/ringmaster_show/output/full_e2e/')
from event_capacity import verify_capacity
source=base/'source';event=base/'event';workspace=json.loads((base/'start-checks.json').read_text())['workspace']
assert json.loads((base/'start-checks.json').read_text())['status']=='passed'
fixture=json.loads((base/'start-checks.json').read_text())['fixture']
assert fixture in ('full','smoke')
assert not (base/'supervisor-state.json').exists(), 'Preserve earlier event evidence'
expected_capacity=json.loads((base/'expected-capacity.json').read_text())
files=json.loads((base/'frozen-source.json').read_text())['files']
import hashlib
assert all(hashlib.sha256((source/p).read_bytes()).hexdigest()==h for p,h in files.items())
assert hashlib.sha256((source/'output/full_e2e/closeout-renderer').read_bytes()).hexdigest()==json.loads((base/'worker-provenance.json').read_text())['sha256']
python=sys.executable
pdfpython='/Users/zaynehunter/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
steps=[]
def event_step(name): steps.append((name,[python,str(source/'tool/full_e2e/event.py'),workspace,str(event),name]))
def audit_print(name): steps.append((name+'-audit',[pdfpython,str(source/'tool/full_e2e/audit_event_prints.py'),str(event),name]))
for name in ('registration','preprint','checkin','judgeprint','judging'):
 event_step(name)
 if name in ('preprint','judgeprint'):audit_print(name)
if fixture=='full':steps.append(('navigation',[python,str(source/'tool/full_e2e/repeat_navigation.py'),workspace,str(event)]))
steps.append(('judging-scopes',[python,str(source/'tool/full_e2e/verify_judging_scopes.py'),workspace,str(event)]))
event_step('closeout')
steps.append(('reconciliation',[python,str(source/'tool/full_e2e/reconcile.py'),workspace,str(event)]))
state=dict(status='running',started_at=time.time(),steps=[])
def save(): (base/'supervisor-state.json').write_text(json.dumps(state,indent=2))
for name,args in steps:
 record=dict(name=name,started_at=time.time(),status='running');state['steps'].append(record);save()
 print('Starting '+name,flush=True)
 try:
  with (base/(name+'.log')).open('x') as log:
   result=subprocess.run(args,cwd=source,stdout=log,stderr=subprocess.STDOUT)
  record.update(exit_code=result.returncode,finished_at=time.time(),status='passed' if result.returncode==0 else 'failed')
  if result.returncode:state['status']='failed';save();raise SystemExit(result.returncode)
  if name=='registration':
   verify_capacity(json.loads((event/'capacity-config.json').read_text()),expected_capacity)
  save();print('Passed '+name,flush=True)
 except Exception as error:
  record.update(status='failed',error=str(error));state['status']='failed';save();raise
state.update(status='passed_through_reconciliation',finished_at=time.time());save()
