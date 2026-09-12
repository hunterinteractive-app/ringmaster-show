"""Exercise one exact breed-artifact retry and automatic worker takeover locally."""
from pathlib import Path
import json
import subprocess
import sys
import time
from local import Local,ROOT,SHOW
from recovery import verify

lab=Local(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(exist_ok=True,parents=True)
binary=Path(sys.argv[3]).resolve()
assert binary.is_relative_to(ROOT/'output') and binary.is_file()
assert int(lab.sql("select count(*) from show_task_queue where task_status in ('queued','running') or (task_status='failed' and attempt_count<max_attempts)"))==0,'Use an idle local queue'
a=lab.rows(f"select a.id,a.generation,a.finalize_run_id,f.scope_key from show_report_artifacts a join show_finalize_runs f on f.id=a.finalize_run_id where a.show_id='{SHOW}' and a.is_current and a.report_name='breed_results_detail_report' and a.metadata->>'breed_name'='American' order by a.id limit 1")[0]
before=lab.rows(f"select id,generation from show_report_artifacts where show_id='{SHOW}' and id<>'{a['id']}' order by id")
result=lab.rpc('requeue_closeout_artifacts',dict(p_show_id=SHOW,p_finalize_run_id=a['finalize_run_id'],p_scope_key=a['scope_key'],p_report_name='breed_results_detail_report',p_artifact_id=a['id']))
assert result['queued_count']==1 and result['artifact_id']==a['id'],result
assert before==lab.rows(f"select id,generation from show_report_artifacts where show_id='{SHOW}' and id<>'{a['id']}' order by id")
(out/'single-artifact-retry.json').write_text(json.dumps(dict(status='passed',artifact_id=a['id'],result=result,other_generations_unchanged=True),indent=2))
children=[];logs=[]
try:
    for n in (0,):
        worker='local-full-e2e-recovery-'+str(n);env=lab.worker_env(worker);env.update(TASK_BATCH_SIZE='1',MAX_CONCURRENT_RENDERS='1')
        log=(out/f'worker-{n}.log').open('w');logs.append(log)
        child=subprocess.Popen([str(binary),'--continuous'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT);children.append(child)
    for _ in range(200):
        active=lab.rows(f"select id from show_task_queue where report_artifact_id='{a['id']}' and worker_id='local-full-e2e-recovery-0' and task_status='running'")
        if active:break
        time.sleep(.05)
    else:raise RuntimeError('Worker did not claim the requested report')
    # Start the peer before killing the first process; it has no queued work.
    env=lab.worker_env('local-full-e2e-recovery-1');env.update(TASK_BATCH_SIZE='1',MAX_CONCURRENT_RENDERS='1')
    log=(out/'worker-1.log').open('w');logs.append(log)
    children.append(subprocess.Popen([str(binary),'--continuous'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT))
    verify(sys.argv[1],out,children[0].pid,'local-full-e2e-recovery-0',binary)
finally:
    for child in children:
        if child.poll() is None:child.terminate()
    for child in children:
        try:child.wait(timeout=10)
        except subprocess.TimeoutExpired:child.kill();child.wait()
    for log in logs:log.close()
