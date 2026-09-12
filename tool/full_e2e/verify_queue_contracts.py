"""Transactional checks for missing retry identities and exhausted lease budgets."""
import json
from pathlib import Path
import sys
from local import Local,SHOW
l=Local(sys.argv[1]);out=Path(sys.argv[2])
a=l.rows(f"select a.id,a.finalize_run_id,f.scope_key from show_report_artifacts a join show_finalize_runs f on f.id=a.finalize_run_id where a.show_id='{SHOW}' and a.report_name='breed_results_detail_report' and a.is_current order by a.id limit 1")[0]
script=f"""begin;
set request.jwt.claims='{{"role":"service_role"}}';
create temporary table original_generations as select id,generation from show_report_artifacts;
do $$begin
  begin
    perform requeue_closeout_artifacts('{SHOW}','{a['finalize_run_id']}','{a['scope_key']}','breed_results_detail_report','ffffffff-ffff-4fff-8fff-ffffffffffff');
    raise exception 'Invalid retry unexpectedly succeeded' using errcode='P0002';
  exception when sqlstate 'P0001' then null;
  end;
  if exists(select id,generation from show_report_artifacts except select * from original_generations) then
    raise exception 'Invalid retry changed another artifact';
  end if;
end;$$;
update show_task_queue set task_status='running',attempt_count=max_attempts,worker_id='local-full-e2e-budget-test',
  lease_expires_at=now()-interval '1 second' where report_artifact_id='{a['id']}';
select recover_stale_report_render_tasks(100);
do $$begin
  if not exists(select 1 from show_task_queue q join show_report_artifacts a on a.id=q.report_artifact_id
    where a.id='{a['id']}' and q.task_status='failed' and q.attempt_count=q.max_attempts
    and a.artifact_status='failed' and a.metadata->>'error_category'='worker_lease_expired') then
    raise exception 'Exhausted interrupted job was not left for review';
  end if;
end;$$;
rollback;"""
l.sql(script)
result=dict(status='passed',invalid_retry_changed_nothing=True,exhausted_recovery_remains_failed=True,transactions_rolled_back=True)
(out/'queue-contracts.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
