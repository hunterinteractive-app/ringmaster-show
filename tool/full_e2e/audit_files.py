"""Verify real Storage bytes, PDF content, and a restorable local file archive."""
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import threading
import urllib.parse
import urllib.request
import zipfile
from pypdf import PdfReader
from local import Local, SHOW


def main():
    lab=Local(sys.argv[1]);out=Path(sys.argv[2]);expected=json.loads((out/'expected-final-entries.json').read_text())
    manifest=json.loads((out/'manifest.json').read_text())
    entries_by_exhibitor=defaultdict(set);classes=defaultdict(list);breeds=defaultdict(list)
    by_n={e['n']:e for e in expected}
    for e in expected:
        entries_by_exhibitor[e['exhibitor']].add(e['tattoo'])
        classes[tuple(e[k] for k in ('section_id','breed','variety','class_name','sex'))].append(e)
        breeds[(e['section_id'],e['breed'])].append(e)
    qualifies=lambda rows:len(rows)>=5 and len({e['exhibitor'] for e in rows})>=3
    leg_ears=defaultdict(set)
    for rows in classes.values():
        if qualifies(rows):
            for e in rows:
                if e['placement']==1:leg_ears[e['exhibitor']].add(e['tattoo'])
    for b in manifest['breeds']:
        if b['bob']:
            e=by_n[b['first']]
            if qualifies(breeds[(e['section_id'],e['breed'])]):leg_ears[e['exhibitor']].add(e['tattoo'])
    # The first two awarded breeds in each section also win BIS/RIS.
    for section in (1,2):
        for b in [b for b in manifest['breeds'] if b['section']==section and b['bob']][:2]:
            e=by_n[b['first']];leg_ears[e['exhibitor']].add(e['tattoo'])
    artifacts=lab.rows(f"select * from show_report_artifacts where show_id='{SHOW}' and is_current and artifact_status='generated'")
    (out/'generated-artifacts.json').write_text(json.dumps(artifacts,indent=2))
    lock=threading.Lock();results=[];errors=[]
    archive_path=out/'report-files.zip'
    append='--append' in sys.argv[3:]
    if archive_path.exists() and not append:raise RuntimeError('Report archive exists; preserve it before a new audit')
    already={}
    if append:
        previous=json.loads((out/'pdf-audit-details.json').read_text())
        results=previous['results'];errors=previous['errors'];already={r['artifact_id']:r for r in results}
        for a in artifacts:
            if a['id'] in already:assert a['file_hash_sha256']==already[a['id']]['sha256'],'A previously audited file changed'
    with zipfile.ZipFile(archive_path,'a' if append else 'x',compression=zipfile.ZIP_DEFLATED,compresslevel=1) as archive:
        def audit(a):
            path='/storage/v1/object/authenticated/'+a['storage_bucket']+'/'+urllib.parse.quote(a['storage_path'],safe='/')
            req=urllib.request.Request(lab.url+path,headers={'apikey':lab.key,'Authorization':'Bearer '+lab.key})
            with urllib.request.urlopen(req,timeout=120) as response:raw=response.read()
            digest=hashlib.sha256(raw).hexdigest()
            assert digest==a['file_hash_sha256'], 'Storage checksum differs from artifact metadata'
            assert len(raw)==a['file_size_bytes'], 'Storage length differs from artifact metadata'
            assert raw.startswith(b'%PDF-'), 'Not a PDF'
            pdf=PdfReader(io.BytesIO(raw));pages=len(pdf.pages)
            kind=a['report_name'];meta=a['metadata'];issues=[];empty=False;ears=set()
            if kind in ('exhibitor_report','legs'):
                text='\n'.join(page.extract_text() or '' for page in pdf.pages)
                ears=set(re.findall(r'\bC\d{5}X?\b',text))
                exhibitor=int(meta['exhibitor_id'][-12:])
                want=entries_by_exhibitor[exhibitor] if kind=='exhibitor_report' else leg_ears[exhibitor]
                if ears!=want:issues.append(dict(expected_ears=sorted(want),actual_ears=sorted(ears)))
                if kind=='legs':
                    empty='no leg certificates earned' in text.lower()
                    if pages!=max(1,len(want)):issues.append(dict(expected_pages=max(1,len(want)),actual_pages=pages))
            with lock:
                archive.writestr(a['id']+'.pdf',raw)
                sample=out/'pdf-samples';sample.mkdir(exist_ok=True)
                target=sample/(kind+'.pdf')
                if not target.exists() and not empty:target.write_bytes(raw)
            return dict(artifact_id=a['id'],report_name=kind,bytes=len(raw),sha256=digest,
                        pages=pages,empty_legs=empty,ear_count=len(ears),issues=issues)
        with ThreadPoolExecutor(max_workers=6) as pool:
            jobs={pool.submit(audit,a):a for a in artifacts if a['id'] not in already}
            for future in as_completed(jobs):
                a=jobs[future]
                try:results.append(future.result())
                except Exception as e:errors.append(dict(artifact_id=a['id'],error=str(e)))
                if (len(results)+len(errors))%500==0:print(json.dumps(dict(audited=len(results),errors=len(errors))),flush=True)
    issue_rows=[r for r in results if r['issues']]
    (out/'pdf-audit-details.json').write_text(json.dumps(dict(results=results,errors=errors),indent=2))
    summary=dict(status='passed' if not errors and not issue_rows else 'failed',
        generated_artifacts=len(artifacts),verified_files=len(results),bytes=sum(r['bytes'] for r in results),
        storage_errors=errors,pdf_content_mismatches=len(issue_rows),
        expected_leg_certificates=sum(len(v) for v in leg_ears.values()),
        actual_leg_certificates=sum(r['pages'] for r in results if r['report_name']=='legs' and not r['empty_legs']),
        archive_bytes=archive_path.stat().st_size)
    (out/'pdf-audit-summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary),flush=True)
    if summary['status']=='failed':raise SystemExit(1)

if __name__=='__main__':main()
