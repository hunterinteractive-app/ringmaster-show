"""Enable PDF layout assertions for one local artifact without uploading it."""
import argparse
import json
import subprocess
import sys
from lab import Lab, ROOT, SHOW, sql_quote

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('workspace')
parser.add_argument('report', choices=['checkin_sheet','details_by_breed', 'sweepstakes_report', 'breed_results_detail_report', 'exh_by_breed', 'best_display_report'])
parser.add_argument('--upload-replay', action='store_true')
args = parser.parse_args()
lab = Lab(args.workspace)
extra = " and artifact_status='generated' and metadata->>'exhibitor_id'>'95200000-0000-0000-0000-000000000064'" if args.upload_replay else ''
artifact = lab.sql(f"select id from public.show_report_artifacts where show_id='{SHOW}' and is_current and report_name={sql_quote(args.report)}{extra} order by created_at,id limit 1;").strip()
if not artifact:
    raise RuntimeError('No matching synthetic artifact')
try:
    result = subprocess.run(['dart', '--enable-asserts', 'run', 'bin/rehearsal_probe.dart',
                            *(['--upload-replay'] if args.upload_replay else []), artifact],
        cwd=ROOT / 'worker/closeout_renderer', env=lab.worker_env('local-probe'),
        capture_output=True, text=True, timeout=90)
    print(result.stdout)
    if result.stderr:
        print(result.stderr[-2500:])
    sys.exit(result.returncode)
except subprocess.TimeoutExpired:
    print(json.dumps({'ok': False, 'error': 'Probe exceeded 90 seconds', 'report': args.report}))
    sys.exit(1)
