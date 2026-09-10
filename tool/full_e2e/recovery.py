"""Interrupt one owned worker and exercise the real stale-lease recovery RPC."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from local import Local,ROOT,SHOW,ApiError

lab=Local(sys.argv[1]);out=Path(sys.argv[2]);pid=int(sys.argv[3]);worker=sys.argv[4]
assert worker.startswith('local-full-e2e-')
expected=str(ROOT/'output/full_e2e/closeout-renderer')+' --continuous'
command=subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True).strip()
if command!=expected: raise RuntimeError('PID is not an owned full E2E worker')
claimed=lab.rows(f"select id,report_artifact_id,attempt_count from show_task_queue where show_id='{SHOW}' and worker_id='{worker}' and task_status='running'")
if not claimed: raise RuntimeError('Selected worker has no interrupted task to test')
(out/'worker-interruption-start.json').write_text(json.dumps(dict(pid=pid,worker=worker,claimed=claimed),indent=2))
os.kill(pid,signal.SIGKILL)
time.sleep(.3)
state=subprocess.run(['ps','-p',str(pid),'-o','state='],capture_output=True,text=True).stdout.strip()
if state and not state.startswith('Z'):
    raise RuntimeError('Worker has not exited; refusing to alter leases')
# Advance ONLY leases belonging to the worker just proven stopped. This tests
# the normal SQL recovery path without waiting the default ten-minute lease.
lab.sql(f"update show_task_queue set lease_expires_at=now()-interval '1 second',heartbeat_at=now()-interval '11 minutes' where show_id='{SHOW}' and worker_id='{worker}' and task_status='running';")
recovered=lab.rpc('recover_stale_report_render_tasks',{'p_limit':50})
row=lab.rows(f"select q.id p_task_id,q.worker_id p_worker_id,a.storage_bucket p_storage_bucket,a.storage_path p_storage_path,a.file_name p_file_name,a.mime_type p_mime_type,a.file_size_bytes p_file_size_bytes,a.file_hash_sha256 p_file_hash_sha256 from show_task_queue q join show_report_artifacts a on a.id=q.report_artifact_id where q.show_id='{SHOW}' and q.task_status='completed' order by q.id limit 1")[0]
lab.rpc('complete_report_render_task',row)
try:
    lab.rpc('complete_report_render_task',dict(row,p_file_hash_sha256='0'*64));rejected=False
except ApiError: rejected=True
result=dict(stopped_worker=worker,interrupted_tasks=claimed,lease_expiry_advanced_locally=True,
            recovered=recovered,completion_replay_passed=True,changed_checksum_rejected=rejected)
(out/'worker-recovery.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
