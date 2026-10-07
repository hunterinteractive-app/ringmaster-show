"""One-time online preparation; subsequent launches use the bundled outputs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
STATE=ROOT/'output/convention-demo'
ENV=dict(os.environ,DEVELOPER_DIR='/Library/Developer/CommandLineTools')
def run(*args,**kw):subprocess.run(args,check=True,env=ENV,**kw)
def main():
    STATE.mkdir(parents=True,exist_ok=True)
    venv=STATE/'python'
    if not (venv/'bin/python').exists():run(sys.executable,'-m','venv',str(venv))
    run(str(venv/'bin/python'),'-m','pip','install','-r',str(ROOT/'worker/closeout_renderer/python/requirements.txt'))
    build=STATE/'worker-build';build.mkdir(exist_ok=True)
    for f in ('pubspec.yaml','pubspec.lock','analysis_options.yaml'):shutil.copy2(ROOT/'worker/closeout_renderer'/f,build/f)
    shutil.copytree(ROOT/'worker/closeout_renderer/bin',build/'bin',dirs_exist_ok=True)
    shutil.copytree(ROOT/'lib',build/'lib',dirs_exist_ok=True)
    p=build/'bin/closeout_renderer.dart';s=p.read_text().replace('/app/venv/bin/python',str(venv/'bin/python')).replace('/app/print_pack.py',str(ROOT/'worker/closeout_renderer/python/print_pack.py'));p.write_text(s)
    run('dart','pub','get',cwd=build)
    run('dart','compile','exe','bin/closeout_renderer.dart','-o',str(STATE/'closeout-renderer'),cwd=build)
    status=json.loads(subprocess.check_output(['supabase','status','--workdir','/tmp/ringmaster-convention-demo','-o','json'],stderr=subprocess.DEVNULL))
    if status['API_URL']!='http://127.0.0.1:55321':raise RuntimeError('Unexpected demo API')
    run('flutter','build','web','--release','--no-web-resources-cdn','--pwa-strategy=none','--dart-define=CONVENTION_DEMO=true','--dart-define=SUPABASE_URL='+status['API_URL'],'--dart-define=SUPABASE_ANON_KEY='+status['ANON_KEY'],cwd=ROOT)
    (STATE/'built.json').write_text(json.dumps({'api':status['API_URL'],'convention_demo':True}))
if __name__=='__main__':main()
