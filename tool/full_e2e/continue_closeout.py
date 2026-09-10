"""Continue independent closeout coverage after preserving an initial failure.

Retries only fixture-contract, changing-snapshot and interrupted-lease failures.
Permanent report errors remain recorded. A drained queue is not a passing run.
"""
import json
from pathlib import Path
import sys
import time
from local import Local, SHOW
from run import Rehearsal
from workflows import Workflows


def main():
    lab=Local(sys.argv[1]);out=Path(sys.argv[2]);test=Rehearsal(lab,out)
    try:
        flow=Workflows(test);flow.staff()
        rows=lab.rows(f"select q.*,a.report_name,a.finalize_run_id,f.scope_key from show_task_queue q join show_report_artifacts a on a.id=q.report_artifact_id join show_finalize_runs f on f.id=a.finalize_run_id where q.show_id='{SHOW}' and q.task_status='failed'")
        evidence=out/f'before-continuation-failures-{int(time.time())}.json'
        evidence.write_text(json.dumps(rows,indent=2))
        selected=[r for r in rows if any(s in (r['last_error'] or '') for s in (
            'record ->> unknown','Results changed during the report read','renderer lease expired'))]
        results=[];fallback=set()
        for r in selected:
            params=dict(p_show_id=SHOW,p_finalize_run_id=r['finalize_run_id'],p_scope_key=r['scope_key'],
                p_report_name=r['report_name'],p_artifact_id=r['report_artifact_id'])
            key=(r['finalize_run_id'],r['report_name'])
            if key in fallback: continue
            try: result=lab.rpc('requeue_closeout_artifacts',params,flow.people[110]['token'])
            except Exception as error:
                results.append(dict(artifact_id=r['report_artifact_id'],error=str(error)))
                # Same UI RPC supports regenerating a report type in this run.
                # Preserve the failed single-artifact attempt before fallback.
                result=lab.rpc('requeue_closeout_artifacts',dict(params,p_artifact_id=None),flow.people[110]['token'])
                fallback.add(key)
            results.append(dict(artifact_id=r['report_artifact_id'],result=result))
        (out/'explicit-retry-results.json').write_text(json.dumps(results,indent=2))
        flow.start_workers()
        flow.closeout(max_minutes=30,fail_on_tasks=False)
        test.summary['status']='continuation_finished_original_failures_retained'
    except Exception as e:
        test.summary.update(status='failed',error=str(e));raise
    finally:
        test.finish()
        (out/'closeout-continuation-summary.json').write_bytes((out/'summary.json').read_bytes())

if __name__=='__main__': main()
