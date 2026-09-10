"""Reconcile the entire synthetic fixture and inspect generated local objects."""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import urllib.request
from urllib.parse import quote

from lab import Lab, ROOT, SHOW, uid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('workspace')
args = parser.parse_args()
lab = Lab(args.workspace)
out = ROOT / 'output/closeout_rehearsal'
manifest = json.loads((out / 'convention_manifest.json').read_text())
result = {'checks': {}, 'limitations': manifest['closeout_rehearsal']['limitations']}


def rows(query):
    return json.loads(lab.sql(f"select coalesce(json_agg(q),'[]') from ({query}) q;"))


expected_entries = {}
expected_counts = Counter()
expected_legs_owners = {1: set(), 2: set()}
for clazz in manifest['classes']:
    sec = manifest['sections'][clazz['section'] - 1]
    for n in range(clazz['first'], clazz['last'] + 1):
        exhibitor = sec['first_exhibitor'] + (n-sec['first_entry'])*sec['exhibitors']//sec['entries']
        expected_counts[exhibitor] += 1
        expected_entries[uid('954', n)] = {
            'id': uid('954', n), 'section_id': sec['id'], 'exhibitor_id': uid('952', exhibitor),
            'placement': str(n-clazz['first']+1), 'tattoo': f'C{n:05d}',
            'breed': clazz['breed'], 'variety': clazz['variety'], 'class_name': clazz['class_name'],
        }
        if n == clazz['first']:
            expected_legs_owners[clazz['section']].add(uid('952', exhibitor))
actual_entries = rows(f"select id,section_id,exhibitor_id,placement,tattoo,breed,variety,class_name from public.entries where show_id='{SHOW}' order by id")
differences = [r['id'] for r in actual_entries if r != expected_entries.get(r['id'])]
result['checks']['all_entries_match_expected'] = len(actual_entries) == 25711 and not differences
result['entry_mismatches'] = differences
expected_awards = set()
for b in manifest['breeds']:
    if b['bob']:
        expected_awards.add((uid('954', b['first']), 'BOB'))
for section in (1, 2):
    for b, code in zip([b for b in manifest['breeds'] if b['section'] == section and b['bob']][:2], ('BIS','RIS')):
        expected_awards.add((uid('954', b['first']), code))
actual_awards = rows(f"select entry_id,award_code from public.entry_awards where show_id='{SHOW}'")
result['checks']['all_awards_match_expected'] = len(actual_awards) == len(expected_awards) and {(r['entry_id'],r['award_code']) for r in actual_awards} == expected_awards
balances = rows(f"select exhibitor_id,entry_count,calculated_total_cents,paid_manual_cents,balance_due_cents from public.show_exhibitor_balances where show_id='{SHOW}'")
bad_balances = []
for row in balances:
    n = int(row['exhibitor_id'].split('-')[-1])
    total = expected_counts[n]*500
    paid = total if n <= 64 else 0
    if (row['entry_count'],row['calculated_total_cents'],row['paid_manual_cents'],row['balance_due_cents']) != (expected_counts[n],total,paid,total-paid):
        bad_balances.append(row['exhibitor_id'])
result['checks']['all_balances_match_expected'] = len(balances) == 2528 and not bad_balances
result['balance_mismatches'] = bad_balances
result['expected_paid_cents'] = sum(expected_counts[n]*500 for n in range(1,65))
checks = rows(f"select exhibitor_id,status from public.show_checkin_records where show_id='{SHOW}'")
result['checks']['all_exhibitors_checked_in_once'] = len(checks) == 2528 and len({r['exhibitor_id'] for r in checks}) == 2528 and all(r['status']=='completed' for r in checks)
artifacts = rows(f"select id,report_name,artifact_status,section_ids,metadata,storage_bucket,storage_path,file_size_bytes,file_hash_sha256,mime_type from public.show_report_artifacts where show_id='{SHOW}' and is_current order by report_name,id")
(out/'artifact-manifest.json').write_text(json.dumps(artifacts,indent=2))
expected_types = {'checkin_sheet':2528,'exhibitor_report':2528,'legs':sum(map(len,expected_legs_owners.values())),
    'arba_report':2,'sweepstakes_report':104,'breed_results_detail_report':104,
    'details_by_breed':2,'exh_by_breed':2,'best_display_report':2,
    'unpaid_balances_report':2,'paid_exhibitor_report':2,'entered_exhibitors_contact_report':2,
    'ribbon_payout_report':2,'payback_report':2,'judge_report':2,'breed_judged_totals_report':2}
actual_types = Counter(r['report_name'] for r in artifacts)
result['checks']['all_manifest_types_and_counts_match'] = dict(actual_types) == expected_types
result['expected_artifact_counts'] = expected_types
result['actual_artifact_counts'] = dict(actual_types)
coverage = {}
for section in (1,2):
    sec=manifest['sections'][section-1]
    owners={uid('952',n) for n in range(sec['first_exhibitor'],sec['first_exhibitor']+sec['exhibitors'])}
    for kind in ('exhibitor_report','checkin_sheet','legs'):
        scoped=[a for a in artifacts if a['report_name']==kind and a['section_ids']==[sec['id']]]
        expected=expected_legs_owners[section] if kind=='legs' else owners
        coverage[f'{sec["kind"]}_{kind}']=len(scoped)==len(expected) and {a['metadata'].get('exhibitor_id') for a in scoped}==expected
result['checks']['all_exhibitor_artifact_owners_match'] = all(coverage.values())
result['artifact_owner_coverage'] = coverage
result['artifact_statuses'] = dict(Counter(a['artifact_status'] for a in artifacts))
result['checks']['full_render_completed'] = all(a['artifact_status']=='generated' for a in artifacts)

# Verify every completed object's bytes against its stored metadata. This is
# independent of the queue's success flag. Save two PDFs per type for visual QA.
samples = set()
for kind in actual_types:
    samples.update(a['id'] for a in [a for a in artifacts if a['report_name']==kind and a['artifact_status']=='generated'][:2])
pdf_dir=out/'pdf-samples'
pdf_dir.mkdir(exist_ok=True)


def inspect(artifact):
    path='/storage/v1/object/authenticated/'+quote(artifact['storage_bucket'],safe='')+'/'+quote(artifact['storage_path'],safe='/')
    request=urllib.request.Request(lab.url+path,headers={'apikey':lab.key,'Authorization':'Bearer '+lab.key})
    try:
        with urllib.request.urlopen(request,timeout=60) as response:
            data=response.read()
        correct=(len(data)==artifact['file_size_bytes'] and hashlib.sha256(data).hexdigest()==artifact['file_hash_sha256'])
        detail={'artifact':artifact['id'],'report':artifact['report_name'],'bytes':len(data),'checksum_matches':correct}
        if artifact['mime_type']=='application/pdf':
            detail['pdf_header']=data.startswith(b'%PDF-')
        if artifact['id'] in samples and artifact['mime_type']=='application/pdf':
            from pypdf import PdfReader
            pdf=PdfReader(io.BytesIO(data))
            detail['pages']=len(pdf.pages)
            text='\n'.join(page.extract_text() or '' for page in pdf.pages)
            detail['text_characters']=len(text)
            if artifact['report_name'] in ('exhibitor_report','checkin_sheet'):
                expected=[e['tattoo'] for e in expected_entries.values()
                          if e['exhibitor_id']==artifact['metadata']['exhibitor_id'] and e['section_id'] in artifact['section_ids']]
                detail['missing_tattoos']=[t for t in expected if t not in text]
            filename=f'{artifact["report_name"]}-{artifact["id"]}.pdf'
            (pdf_dir/filename).write_bytes(data)
            (pdf_dir/filename.replace('.pdf','.txt')).write_text(text)
        return detail
    except Exception as error:
        return {'artifact':artifact['id'],'report':artifact['report_name'],'error':str(error)}


with ThreadPoolExecutor(max_workers=4) as pool:
    objects=list(pool.map(inspect,[a for a in artifacts if a['artifact_status']=='generated']))
result['objects_checked']=len(objects)
result['object_bytes']=sum(o.get('bytes',0) for o in objects)
result['checks']['generated_object_checksums_match']=bool(objects) and all(o.get('checksum_matches',False) for o in objects)
result['checks']['sampled_pdf_entries_complete']=all(not o.get('missing_tattoos') and 'error' not in o for o in objects)
(out/'object-verification.json').write_text(json.dumps(objects,indent=2))
(out/'verification.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
raise SystemExit(0 if all(result['checks'].values()) else 1)
