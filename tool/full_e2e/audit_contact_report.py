import collections, hashlib, io, json, re, sys, zipfile
from pathlib import Path
from pypdf import PdfReader

base=Path(sys.argv[1]).resolve(); source=base/'source'; out=base/'event'
sys.path.insert(0,str(source/'tool/full_e2e'))
from local import Local, SHOW
lab=Local(json.loads((base/'start-checks.json').read_text())['workspace'])
artifacts=[a for a in json.loads((out/'generated-artifacts.json').read_text()) if a['report_name']=='entered_exhibitors_contact_report']
assert len(artifacts)==1, 'Expected one combined contact report'
a=artifacts[0]
with zipfile.ZipFile(out/'report-files.zip') as archive: raw=archive.read(a['id']+'.pdf')
assert hashlib.sha256(raw).hexdigest()==a['file_hash_sha256']
pdf=PdfReader(io.BytesIO(raw)); text='\n'.join(p.extract_text() or '' for p in pdf.pages)
matches=list(re.finditer(r'Synthetic\s+Exhibitor\s+(\d+)\b', text))
numbers=[int(m[1]) for m in matches]; counts=collections.Counter(numbers)
rows=lab.rows(f"select distinct x.id,x.display_name,x.email,x.phone,x.address_line1,x.address_line2,x.city,x.state,x.zip from exhibitors x join entries e on e.exhibitor_id=x.id where e.show_id='{SHOW}'")
expected={int(r['id'][-12:]):r for r in rows}
compact=lambda value:re.sub(r'\s+','',value or '')
issues=[]
for index,m in enumerate(matches):
    number=int(m[1]); row=expected.get(number)
    if not row: issues.append(dict(exhibitor=number,error='Unexpected exhibitor')); continue
    block=compact(text[m.end():matches[index+1].start() if index+1<len(matches) else len(text)])
    missing=[key for key in ('email','phone','address_line1','address_line2','city','state','zip') if compact(row.get(key)) and compact(row[key]) not in block]
    if missing: issues.append(dict(exhibitor=number,missing_fields=missing))
result=dict(status='passed' if set(numbers)==set(expected) and all(n==1 for n in counts.values()) and not issues else 'failed',
    artifact_id=a['id'], pages=len(pdf.pages), expected_contacts=len(expected), printed_contacts=len(numbers),
    missing_contacts=sorted(set(expected)-set(numbers)), unexpected_contacts=sorted(set(numbers)-set(expected)),
    duplicates={n:c for n,c in counts.items() if c!=1}, field_mismatches=issues, sha256=a['file_hash_sha256'])
(out/'contact-content-audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
if result['status']!='passed': raise SystemExit(1)
