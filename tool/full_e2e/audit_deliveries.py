"""Reconcile artifact IDs and actual captured attachment hashes, not HTTP success."""
from collections import Counter,defaultdict
import json
from pathlib import Path
import sys
from local import Local,SHOW

lab=Local(sys.argv[1]);out=Path(sys.argv[2])
artifacts={r['id']:r for r in json.loads((out/'generated-artifacts.json').read_text())}
pdfs={r['artifact_id']:r for r in json.loads((out/'pdf-audit-details.json').read_text())['results']}
types={'exhibitor_report','legs','sweepstakes_report','breed_results_detail_report',
       'details_by_breed','exh_by_breed','best_display_report','arba_report'}
expected={k:a for k,a in artifacts.items() if a['report_name'] in types and not pdfs[k]['empty_legs']}
captured=[json.loads(line) for line in (out/'captured-deliveries.jsonl').read_text().splitlines()]
by_message={r['id']:r for r in captured}
logs=lab.rows(f"select artifact_id,provider_message_id,recipient_email,report_name from show_email_deliveries where show_id='{SHOW}' and delivery_status='sent'")
by_id=defaultdict(list);by_provider=defaultdict(list)
for row in logs:by_id[row['artifact_id']].append(row);by_provider[row['provider_message_id']].append(row)
missing=sorted(set(expected)-set(by_id));unexpected=sorted(set(by_id)-set(expected));errors=[]
for message_id,rows in by_provider.items():
    message=by_message.get(message_id)
    if not message:errors.append(dict(message_id=message_id,error='No receiver capture'));continue
    want=Counter((artifacts[r['artifact_id']]['file_name'],artifacts[r['artifact_id']]['file_hash_sha256']) for r in rows)
    actual=Counter((a['filename'],a['sha256']) for a in message['attachments'])
    if want!=actual:errors.append(dict(message_id=message_id,error='Attachment name/hash mismatch'))
    if any(r['recipient_email']!=', '.join(message['to']) for r in rows):errors.append(dict(message_id=message_id,error='Recipient mismatch'))
extra_messages=sorted(set(by_message)-set(by_provider))
duplicates=[k for k,v in by_id.items() if len(v)!=1]
result=dict(status='passed' if not any((missing,unexpected,errors,extra_messages,duplicates)) else 'failed',
    captured_messages=len(captured),captured_attachments=sum(len(r['attachments']) for r in captured),
    expected_artifacts=len(expected),delivered_artifacts=len(by_id),missing_artifacts=missing,
    unexpected_artifacts=unexpected,duplicate_deliveries=duplicates,errors=errors,
    unlogged_messages=extra_messages,by_report_type=dict(Counter(r['report_name'] for r in logs)),
    empty_leg_files_correctly_excluded=sum(r['empty_legs'] for r in pdfs.values()))
(out/'delivery-audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
if result['status']=='failed':raise SystemExit(1)
