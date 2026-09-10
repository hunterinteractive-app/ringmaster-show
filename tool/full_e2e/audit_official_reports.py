"""Check official PDF populations, including successful-but-truncated reports."""
from collections import defaultdict
import io
import json
from pathlib import Path
import re
import sys
import zipfile
from pypdf import PdfReader

out=Path(sys.argv[1]);entries=json.loads((out/'expected-final-entries.json').read_text())
artifacts=json.loads((out/'generated-artifacts.json').read_text());results=[]
manifest=json.loads((out/'manifest.json').read_text());by_n={e['n']:e for e in entries}
show_winners=defaultdict(set)
for section in (1,2):
    for b in [b for b in manifest['breeds'] if b['section']==section and b['bob']][:2]:
        e=by_n[b['first']];show_winners[e['section_id']].add(e['tattoo'])
with zipfile.ZipFile(out/'report-files.zip') as archive:
    for a in artifacts:
        if a['report_name'] not in ('arba_report','breed_results_detail_report'):continue
        pdf=PdfReader(io.BytesIO(archive.read(a['id']+'.pdf')))
        text='\n'.join(p.extract_text() or '' for p in pdf.pages)
        section=a['metadata']['section_id'];population=[e for e in entries if e['section_id']==section]
        issues=[];checks={}
        if a['report_name']=='arba_report':
            found=re.search(r'Number of Rabbits Exhibited:\s*([\d,]+)',text)
            actual=int(found[1].replace(',','')) if found else None
            checks['rabbits_shown']=dict(expected=len(population),actual=actual)
            judges={int(n) for n in re.findall(r'Synthetic Judge\s+(\d+)',text)}
            checks['judges_printed']=dict(expected=110,actual=len(judges))
            if actual!=len(population):issues.append('Incorrect rabbit total')
            if judges!=set(range(1,111)):issues.append('Incomplete judge list')
        else:
            population=[e for e in population if e['breed']==a['metadata']['breed_name']]
            # This report promises top-five class placings plus show awards,
            # rather than printing every lower placing from the full population.
            want={e['tattoo'] for e in population if e['placement']<=5}|show_winners[section]
            actual=set(re.findall(r'\bC\d{5}X?\b',text))
            checks['animal_coverage']=dict(expected=len(want),actual=len(actual),missing=sorted(want-actual),unexpected=sorted(actual-want))
            if actual!=want:issues.append('Incomplete breed-report animal coverage')
        results.append(dict(artifact_id=a['id'],report_name=a['report_name'],section_id=section,pages=len(pdf.pages),checks=checks,issues=issues))
result=dict(status='failed' if any(r['issues'] for r in results) else 'passed',
            reports_checked=len(results),failed_reports=sum(bool(r['issues']) for r in results),results=results)
(out/'official-report-content-audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items() if k!='results'}))
print(json.dumps([r for r in results if r['report_name']=='arba_report'],indent=2))
if result['status']=='failed':raise SystemExit(1)
