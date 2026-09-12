"""Retest all seven real print-generator paths on a retained synthetic event."""
import json, os
from pathlib import Path
import subprocess,sys,time
from local import Local,ROOT
from run import Rehearsal
from workflows import Workflows
lab=Local(sys.argv[1]);out=Path(sys.argv[2]);source=Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=True)
for name in ('manifest.json','expected-final-entries.json'):
    (out/name).write_bytes((source/name).read_bytes())
test=Rehearsal(lab,out)
try:
    flow=Workflows(test);flow.staff();results=[]
    modes=sys.argv[4:] or ['coop','checkin-open','checkin-youth','control-open','control-youth','remark-open','remark-youth']
    for mode in modes:
        folder=out/'print-packs'/mode;folder.mkdir(parents=True,exist_ok=True)
        env={**os.environ,'EVENT_API_URL':lab.url,'EVENT_ANON_KEY':lab.anon,
             'EVENT_STAFF_ACCESS_TOKEN':flow.people[110]['token'],'EVENT_PRINT_MODE':mode,'EVENT_PRINT_OUTPUT':str(folder.resolve())}
        started=time.monotonic()
        with (folder/'flutter.log').open('w') as log:
            result=subprocess.run(['flutter','test','--no-pub','test/local_event_print_rehearsal_test.dart','--reporter','expanded'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
        results.append(dict(mode=mode,exit_code=result.returncode,elapsed_s=time.monotonic()-started))
        test.log('print_finished',mode=mode,exit_code=result.returncode,duration_s=results[-1]['elapsed_s'])
    test.summary['checks']['prints']=results
    test.summary['status']='passed' if all(r['exit_code']==0 for r in results) else 'failed'
finally:test.finish()
if test.summary['status']!='passed':raise SystemExit(1)
