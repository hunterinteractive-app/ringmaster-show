"""Start the pinned local convention demo. First setup requires internet."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
STATE=ROOT/'output/convention-demo'
RUNTIME=Path('/tmp/ringmaster-convention-demo')
PROJECT='ringmaster-show-full-e2e-convention'
ENV=dict(os.environ,DEVELOPER_DIR='/Library/Developer/CommandLineTools')

def run(*args,**kw):return subprocess.run(args,check=True,env=ENV,**kw)

def main():
    try:
        with urllib.request.urlopen('http://127.0.0.1:8787/booth',timeout=2) as r:
            if b'RingMaster Convention Demo' in r.read():
                run('open','http://127.0.0.1:8787/booth');return
    except OSError:pass
    STATE.mkdir(parents=True,exist_ok=True)
    if subprocess.run(['docker','info'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
        run('open','-a','Docker')
        for _ in range(90):
            if subprocess.run(['docker','info'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
            time.sleep(1)
        else:raise RuntimeError('Docker did not start. Open Docker Desktop, then try again.')
    if not RUNTIME.exists():
        if (STATE/'runtime').exists():shutil.copytree(STATE/'runtime',RUNTIME)
        else:
            run('bash',str(ROOT/'tool/local_supabase_e2e.sh'),str(RUNTIME))
            config=RUNTIME/'supabase/config.toml'
            import re
            text=re.sub(r'^project_id = .*$', f'project_id = "{PROJECT}"', config.read_text(), flags=re.MULTILINE)
            for port in (54321,54322,54323,54324,54327,54328,54329):text=text.replace(str(port),str(port+1000))
            text=text.replace('8083','8183')
            config.write_text(text)
    if (RUNTIME/'supabase/.temp/project-ref').exists():raise RuntimeError('Linked database forbidden')
    import tomllib
    if tomllib.loads((RUNTIME/'supabase/config.toml').read_text())['project_id']!=PROJECT:raise RuntimeError('Wrong local project')
    run('supabase','start','--workdir',str(RUNTIME),'--exclude','logflare,vector,supavisor,studio,postgres-meta,imgproxy')
    shutil.copytree(RUNTIME,STATE/'runtime',dirs_exist_ok=True,ignore=shutil.ignore_patterns('.temp','local-provider.env'))
    fixture=STATE/'fixture'
    if not (fixture/'manifest.json').exists():run(sys.executable,str(ROOT/'tool/full_e2e/prepare_smoke.py'),str(RUNTIME),str(fixture))
    if not (STATE/'built.json').exists() or not (ROOT/'build/web/index.html').exists() or not (STATE/'closeout-renderer').exists():
        run(sys.executable,str(ROOT/'tool/convention_demo/build.py'))
    log=(STATE/'server.log').open('a')
    proc=subprocess.Popen([sys.executable,str(ROOT/'tool/convention_demo/serve.py'),str(RUNTIME),str(fixture)],cwd=ROOT,env=ENV,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    (STATE/'server.pid').write_text(str(proc.pid))
    print('Starting the convention demo. First-time sample data setup can take a few minutes.')
    for _ in range(300):
        if proc.poll() is not None:raise RuntimeError('Demo startup failed. See '+str(STATE/'server.log'))
        try:
            with urllib.request.urlopen('http://127.0.0.1:8787/booth',timeout=2) as r:
                if r.status==200:
                    run('open','http://127.0.0.1:8787/booth');print('Demo ready. You can close this Terminal window.');return
        except OSError:pass
        time.sleep(1)
    raise RuntimeError('Startup is taking longer than expected; inspect '+str(STATE/'server.log'))

if __name__=='__main__':main()
