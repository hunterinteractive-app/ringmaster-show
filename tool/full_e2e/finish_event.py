import json, subprocess, sys, time
from pathlib import Path

base = Path(sys.argv[1]).resolve()
assert str(base).startswith('/Users/zaynehunter/Dev/RingMasterShow/ringmaster_show/output/full_e2e/')
assert json.loads((base/'supervisor-state.json').read_text())['status'] == 'passed_through_reconciliation'
source = base/'source'; event = base/'event'
workspace = json.loads((base/'start-checks.json').read_text())['workspace']
pdfpython = '/Users/zaynehunter/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
steps = [
    ('delivery', [sys.executable, str(source/'tool/full_e2e/deliver.py'), workspace, str(event)]),
    ('pdf-audit', [pdfpython, str(source/'tool/full_e2e/audit_files.py'), workspace, str(event)]),
    ('official-report-audit', [pdfpython, str(source/'tool/full_e2e/audit_official_reports.py'), str(event), '--combined']),
    ('contact-content-audit', [pdfpython, str(source/'tool/full_e2e/audit_contact_report.py'), str(base)]),
    ('delivery-audit', [sys.executable, str(source/'tool/full_e2e/audit_deliveries.py'), workspace, str(event)]),
    ('backup-restore', [sys.executable, str(source/'tool/full_e2e/backup_restore.py'), workspace, str(event)]),
]
state_path = base/'finish-state.json'
assert not state_path.exists(), 'Preserve previous completion evidence'
state = dict(status='running', started_at=time.time(), steps=[])
def save(): state_path.write_text(json.dumps(state, indent=2))
for name, args in steps:
    step = dict(name=name, status='running', started_at=time.time())
    state['steps'].append(step); save(); print('Starting '+name, flush=True)
    with (base/(name+'.log')).open('x') as log:
        result = subprocess.run(args, cwd=source, stdout=log, stderr=subprocess.STDOUT)
    step.update(status='passed' if result.returncode==0 else 'failed', exit_code=result.returncode, finished_at=time.time())
    if result.returncode:
        state['status']='failed'; save(); raise SystemExit(result.returncode)
    if name == 'delivery':
        checks = json.loads((event/'delivery-summary.json').read_text())['checks']
        exhibitor = checks['exhibitor_delivery']
        valid = not exhibitor['errors'] and exhibitor['responses']==exhibitor['targets']
        valid = valid and len(checks.get('arba_generation', []))==2 and all(r['artifact_status']=='generated' for r in checks['arba_generation'])
        valid = valid and not checks['club_delivery'].get('failed_count') and not checks.get('delivery_state_error') and bool(checks.get('arba_delivery'))
        if not valid:
            step.update(status='failed', reason='Delivery coverage or ARBA completion did not pass')
            state['status']='failed'; save(); raise SystemExit(1)
    save(); print('Passed '+name, flush=True)
state.update(status='passed_automated_audits', finished_at=time.time()); save()
