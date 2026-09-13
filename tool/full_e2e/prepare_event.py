import hashlib,json,os,re,shutil,subprocess,sys,tomllib
from pathlib import Path
root=Path(__file__).resolve().parents[2]
import argparse
parser=argparse.ArgumentParser(description='Freeze source, build a worker and prepare a fresh local event without starting its workload.')
parser.add_argument('name');parser.add_argument('project_suffix');parser.add_argument('scale',type=int,choices=(2,4));parser.add_argument('previous_workspace');parser.add_argument('--revision',default='HEAD');parser.add_argument('--smoke',action='store_true')
args=parser.parse_args()
name,project_suffix,scale_text,previous=args.name,args.project_suffix,str(args.scale),args.previous_workspace
revision_args=[args.revision]
from event_capacity import CAPACITY, verify_capacity
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip(), 'Commit or isolate source changes before freezing the rehearsal'
assert len(revision_args)<=1
requested_revision=revision_args[0] if revision_args else 'HEAD'
assert requested_revision=='HEAD' or re.fullmatch('[a-f0-9]{40}',requested_revision)
assert re.fullmatch('[a-z0-9-]+',name) and re.fullmatch('[a-z0-9-]+',project_suffix)
scale=int(scale_text);assert scale in (2,4)
base=root/'output/full_e2e'/name;workspace=Path('/tmp')/('ringmaster-show-full-e2e-'+name)
assert not base.exists() and not workspace.exists()
base.mkdir();source=base/'source';source.mkdir()
def run(args,name,cwd=root,private=False):
 mode=0o600 if private else 0o644
 with os.fdopen(os.open(base/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,mode),'w') as log:
  subprocess.run(args,cwd=cwd,stdout=log,stderr=subprocess.STDOUT,check=True)
revision=subprocess.check_output(['git','rev-parse',requested_revision+'^{commit}'],cwd=root,text=True).strip()
with subprocess.Popen(['git','archive',revision],cwd=root,stdout=subprocess.PIPE) as archive:
 subprocess.run(['tar','-x','-C',str(source)],stdin=archive.stdout,check=True);assert archive.wait()==0
files={str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file() and not p.is_symlink()}
(base/'frozen-source.json').write_text(json.dumps(dict(revision=revision,files=files),indent=2))
# Build from the archived source; never reuse a previous run's executable.
worker=base/'closeout-renderer';build=base/'worker-build';build.mkdir()
for filename in ('pubspec.yaml','pubspec.lock','analysis_options.yaml'):
 shutil.copy2(source/'worker/closeout_renderer'/filename,build/filename)
shutil.copytree(source/'worker/closeout_renderer/bin',build/'bin')
shutil.copytree(source/'lib',build/'lib')
dart=shutil.which('dart');assert dart, 'Dart must be available on PATH'
run([dart,'pub','get'],'worker-deps.log',cwd=build)
run([dart,'compile','exe','bin/closeout_renderer.dart','-o',str(worker)],'worker-build.log',cwd=build)
(source/'output/full_e2e').mkdir(parents=True);shutil.copy2(worker,source/'output/full_e2e/closeout-renderer')
(base/'worker-provenance.json').write_text(json.dumps(dict(built_from_revision=revision,sha256=hashlib.sha256(worker.read_bytes()).hexdigest(),pubspec_lock_sha256=hashlib.sha256((build/'pubspec.lock').read_bytes()).hexdigest()),indent=2))
run(['bash',str(source/'tool/local_supabase_e2e.sh'),str(workspace)],'setup.log')
project='ringmaster-show-full-e2e-'+project_suffix
p=workspace/'supabase/config.toml';p.write_text(re.sub(r'^project_id = .*$',f'project_id = "{project}"',p.read_text(),flags=re.M))
f=dict(project_id=project,source_revision=revision,files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((workspace/'supabase/migrations').glob('*.sql'))})
for p in (base/'rehearsal-migration-manifest.json',workspace/'rehearsal-migration-manifest.json'):p.write_text(json.dumps(f,indent=2))
(workspace/'rehearsal-capacity.json').write_text(json.dumps(CAPACITY,indent=2))
(base/'expected-capacity.json').write_text(json.dumps(CAPACITY,indent=2))
old_workspace=Path(previous).resolve();assert str(old_workspace).startswith('/private/tmp/ringmaster-show-full-e2e-')
assert not (old_workspace/'supabase/.temp/project-ref').exists()
assert tomllib.loads((old_workspace/'supabase/config.toml').read_text())['project_id'].startswith('ringmaster-show-full-e2e-')
run(['supabase','stop','--workdir',str(old_workspace)],'previous-stack-stop.log')
print('Previous local volumes retained; source frozen at '+revision,flush=True)
run(['supabase','start','--workdir',str(workspace),'--exclude','logflare,vector,supavisor,studio,postgres-meta,imgproxy'],'start-private.log',private=True)
run(['python3',str(source/'tool/full_e2e/check_event_space.py'),str(workspace),str(scale)],'storage-preflight.json')
run(['python3',str(source/'tool/full_e2e/configure_capacity.py'),str(workspace),'--auth-pool',str(CAPACITY['auth_pool']),'--rest-pool',str(CAPACITY['rest_pool']),'--gateway-connections',str(CAPACITY['gateway_connections']),'--auth-request-timeout',str(CAPACITY['auth_request_timeout_seconds'])],'capacity-prepare.log')
if args.smoke:
 run(['python3',str(source/'tool/full_e2e/prepare_smoke.py'),str(workspace),str(base/'event')],'prepare.log')
else:
 run(['python3',str(source/'tool/full_e2e/prepare.py'),str(workspace),str(base/'event'),'--scale',str(scale),'--staff-scale',str(scale)],'prepare.log')
run(['/Users/zaynehunter/flutter/bin/flutter','pub','get','--directory',str(source)],'flutter-deps.log')
sys.path.insert(0,str(source/'tool/full_e2e'))
from local import Local,SHOW
from event import specification
lab=Local(str(workspace));p=specification(base/'event')
counts=lab.rows(f"select (select count(*) from entries where show_id='{SHOW}') as entries,(select count(*) from exhibitors where id::text like '95200000-%') as convention_exhibitors,(select count(*) from show_payments where show_id='{SHOW}') as payments")
assert counts==[dict(entries=0,convention_exhibitors=0,payments=0)],counts
if not args.smoke:assert (p['entries'],p['exhibitors'],p['peak_concurrency_assumption'],p['judge_sessions'],p['checkin_sessions'],p['admins'],p['superintendents'])==(25711*scale,2528*scale,250*scale,110*scale,30*scale,10*scale,15*scale)
assert all(hashlib.sha256((source/path).read_bytes()).hexdigest()==h for path,h in files.items())
verify_capacity(json.loads((base/'capacity-prepare.log').read_text().splitlines()[-1]),CAPACITY)
assert lab.rows("select active from cron.job where jobname='process-stripe-payment-events'")==[dict(active=True)]
assert lab.rpc('get_stripe_payment_queue_health',{})['pending']==0
(base/'start-checks.json').write_text(json.dumps(dict(status='passed',fixture='smoke' if args.smoke else 'full',workspace=str(workspace),project_id=project,event_counts=counts,source_revision=revision,source_files_verified=len(files),profile_entries=p['entries'],profile_exhibitors=p['exhibitors'],purchaser_peak=p['peak_concurrency_assumption'],baseline_note='Three unrelated local baseline seed exhibitors are excluded.'),indent=2))
shutil.copy2(__file__,base/'prepare-command.py')
print('Fresh event ready:',p['entries'],'entries;',p['exhibitors'],'exhibitors;',p['peak_concurrency_assumption'],'purchasers',flush=True)
