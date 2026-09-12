"""Check section ARBA PDFs against the independently retained active population."""
import json,re,sys
from pathlib import Path
from pypdf import PdfReader

out=Path(sys.argv[1]);source=Path(sys.argv[2])
entries=json.loads((source/'expected-final-entries.json').read_text())
renders=json.loads((out/'renders.json').read_text())
sections={e['section_id'] for e in entries};results=[]
for row in renders:
    result=dict(artifact_id=row['id'],finalize_run_id=row['finalize_run_id'],passed=False)
    try:
        assert row['report_name']=='arba_report' and row['verified_render']
        assert len(row['section_ids'])==1
        section=row['section_ids'][0]
        expected=sum(e['section_id']==section and not e.get('scratched') for e in entries)
        pdf=PdfReader(out/(row['id']+'.pdf'))
        text='\n'.join(page.extract_text() or '' for page in pdf.pages)
        found=re.search(r'Number of Rabbits Exhibited:\s*([\d,]+)',text)
        actual=int(found[1].replace(',','')) if found else None
        judges={int(n) for n in re.findall(r'Synthetic Judge\s+(\d+)',text)}
        result.update(section_id=section,expected_animals=expected,actual_animals=actual,
                      judges=len(judges),pages=len(pdf.pages),
                      passed=expected==actual and judges==set(range(1,111)))
    except Exception as error:result['error']=str(error)
    results.append(result)
passed=len(results)==len(sections) and {r.get('section_id') for r in results}==sections and all(r['passed'] for r in results)
summary=dict(status='passed' if passed else 'failed',results=results)
(out/'content-audit.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
if not passed:raise SystemExit(1)
