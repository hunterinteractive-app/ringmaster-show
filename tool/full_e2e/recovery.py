"""Interrupt an owned worker and require its peer to finish without requeue."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time
from local import Local,ROOT,SHOW,ApiError


def verify(workspace,output,pid,worker,binary=None,wait_seconds=180):
    lab=Local(workspace);out=Path(output)
    assert worker.startswith('local-full-e2e-')
    binary=Path(binary or ROOT/'output/full_e2e/closeout-renderer').resolve()
    if not binary.is_relative_to(ROOT/'output'):
        raise RuntimeError('Worker must be a local rehearsal executable')
    expected=str(binary)+' --continuous'
    command=subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True).strip()
    if command!=expected: raise RuntimeError('PID is not an owned full E2E worker')
    claimed=lab.rows(f"select q.id,q.report_artifact_id,q.attempt_count,a.generation from show_task_queue q join show_report_artifacts a on a.id=q.report_artifact_id where q.show_id='{SHOW}' and q.worker_id='{worker}' and q.task_status='running'")
    if not claimed: raise RuntimeError('Selected worker has no interrupted task to test')
    (out/'worker-interruption-start.json').write_text(json.dumps(dict(pid=pid,worker=worker,claimed=claimed),indent=2))
    os.kill(pid,signal.SIGKILL)
    time.sleep(.3)
    state=subprocess.run(['ps','-p',str(pid),'-o','state='],capture_output=True,text=True).stdout.strip()
    if state and not state.startswith('Z'):
        raise RuntimeError('Worker has not exited; refusing to alter leases')
    # Advance ONLY the dead worker's leases. A surviving real worker must invoke
    # the recovery RPC itself through its normal polling loop, then render/upload.
    lab.sql(f"update show_task_queue set lease_expires_at=now()-interval '1 second',heartbeat_at=now()-interval '11 minutes' where show_id='{SHOW}' and worker_id='{worker}' and task_status='running';")
    ids=','.join("'"+r['id']+"'" for r in claimed)
    start=time.monotonic();final=[]
    while time.monotonic()-start<wait_seconds:
        final=lab.rows(f"select q.id,q.task_status::text status,q.attempt_count,q.worker_id,a.generation,a.artifact_status::text artifact_status from show_task_queue q join show_report_artifacts a on a.id=q.report_artifact_id where q.id in ({ids})")
        if len(final)==len(claimed) and all(r['status']=='completed' and r['artifact_status']=='generated' for r in final):break
        if any(r['status']=='failed' for r in final):break
        time.sleep(1)
    result=dict(status='failed',stopped_worker=worker,interrupted_tasks=claimed,final=final,
                lease_expiry_advanced_locally=True,manual_requeue_used=False,
                recovery_rpc_invoked_by_test=False,elapsed_s=round(time.monotonic()-start,2))
    try:
        assert len(final)==len(claimed) and all(r['status']=='completed' and r['artifact_status']=='generated' for r in final),final
        before={r['id']:r for r in claimed}
        assert all(r['generation']==before[r['id']]['generation'] and r['attempt_count']==before[r['id']]['attempt_count']+1 and r['worker_id']!=worker for r in final),final
        row=lab.rows(f"select q.id p_task_id,q.worker_id p_worker_id,a.storage_bucket p_storage_bucket,a.storage_path p_storage_path,a.file_name p_file_name,a.mime_type p_mime_type,a.file_size_bytes p_file_size_bytes,a.file_hash_sha256 p_file_hash_sha256 from show_task_queue q join show_report_artifacts a on a.id=q.report_artifact_id where q.id='{claimed[0]['id']}'")[0]
        lab.rpc('complete_report_render_task',row)
        try:lab.rpc('complete_report_render_task',dict(row,p_file_hash_sha256='0'*64));rejected=False
        except ApiError:rejected=True
        assert rejected
        result.update(status='passed',completion_replay_passed=True,changed_checksum_rejected=True)
    finally:
        (out/'worker-recovery.json').write_text(json.dumps(result,indent=2))
        print(json.dumps(result),flush=True)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('workspace');p.add_argument('output');p.add_argument('pid',type=int);p.add_argument('worker');p.add_argument('--binary');a=p.parse_args()
    verify(a.workspace,a.output,a.pid,a.worker,a.binary)
