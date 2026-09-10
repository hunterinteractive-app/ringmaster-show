"""Check completion replay and recover only stopped local rehearsal workers."""
import json
import subprocess
import sys
from lab import ApiError, Lab, ROOT, SHOW

lab = Lab(sys.argv[1])
command = str(ROOT / 'output/closeout_rehearsal/closeout-renderer') + ' --continuous'
processes = subprocess.check_output(['ps','-axo','command='], text=True).splitlines()
if command in (p.strip() for p in processes):
    raise RuntimeError('Stop all rehearsal workers before advancing lease expiry')
row = json.loads(lab.sql(f"""select row_to_json(r) from (
  select q.id as p_task_id,q.worker_id as p_worker_id,
    a.storage_bucket as p_storage_bucket,a.storage_path as p_storage_path,
    a.file_name as p_file_name,a.mime_type as p_mime_type,
    a.file_size_bytes as p_file_size_bytes,a.file_hash_sha256 as p_file_hash_sha256
  from public.show_task_queue q join public.show_report_artifacts a on a.id=q.report_artifact_id
  where q.show_id='{SHOW}' and q.task_status='completed' order by q.id limit 1
) r;"""))
completed_before = int(lab.sql(f"select count(*) from public.show_task_queue where show_id='{SHOW}' and task_status='completed';"))
lab.rpc('complete_report_render_task',row)
result={'exact_completion_replay_succeeded':True}
try:
    lab.rpc('complete_report_render_task',dict(row,p_file_hash_sha256='0'*64))
    result['changed_checksum_rejected']=False
except ApiError:
    result['changed_checksum_rejected']=True
running=int(lab.sql(f"select count(*) from public.show_task_queue where show_id='{SHOW}' and task_status='running';"))
lab.sql(f"update public.show_task_queue set lease_expires_at=now()-interval '1 second',heartbeat_at=now()-interval '11 minutes' where show_id='{SHOW}' and task_status='running';")
result['lease_expiry_advanced_locally']=True
result['interrupted_tasks']=running
result['recovered_tasks']=lab.rpc('recover_stale_report_render_tasks',{'p_limit':50})
result['no_running_tasks_remain']=int(lab.sql(f"select count(*) from public.show_task_queue where show_id='{SHOW}' and task_status='running';"))==0
result['completed_tasks_preserved']=int(lab.sql(f"select count(*) from public.show_task_queue where show_id='{SHOW}' and task_status='completed';"))==completed_before
result['no_duplicate_artifact_tasks']=int(lab.sql(f"select count(*) from (select report_artifact_id from public.show_task_queue where show_id='{SHOW}' group by report_artifact_id having count(*)>1) q;"))==0
(ROOT/'output/closeout_rehearsal/recovery.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
