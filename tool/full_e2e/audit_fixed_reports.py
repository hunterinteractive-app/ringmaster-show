"""Semantic checks of targeted report renders against the independent fixture."""
from collections import Counter
import json
from pathlib import Path
import re
import sys
from pypdf import PdfReader
out=Path(sys.argv[1]);source=Path(sys.argv[2]);rows=json.loads((out/'renders.json').read_text())
entries=json.loads((source/'expected-final-entries.json').read_text());manifest=json.loads((source/'manifest.json').read_text());by_n={e['n']:e for e in entries};results=[]
for r in rows:
    if not r['verified_render']:
        results.append(dict(id=r['id'],report=r['report_name'],passed=False,error=r['error']));continue
    pdf=PdfReader(out/(r['id']+'.pdf'));text='\n'.join(p.extract_text() or '' for p in pdf.pages)
    (out/(r['id']+'.txt')).write_text(text)
    section=r['section_ids'][0];pop=[e for e in entries if e['section_id']==section]
    checks={};errors=[]
    if r['report_name']=='arba_report':
        found=re.search(r'Number of Rabbits Exhibited:\s*([\d,]+)',text)
        count=int(found[1].replace(',','')) if found else None
        checks['animal_count']=count==len(pop)
        checks['all_judges']={int(n) for n in re.findall(r'Synthetic Judge\s+(\d+)',text)}==set(range(1,111))
    elif r['report_name']=='breed_results_detail_report':
        sn=1 if section.endswith('1') else 2
        winners={by_n[b['first']]['tattoo'] for b in [b for b in manifest['breeds'] if b['section']==sn and b['bob']][:2]}
        want={e['tattoo'] for e in pop if e['breed']==r['metadata']['breed_name'] and e['placement']<=5}|winners
        actual=set(re.findall(r'\bC\d{5}X?\b',text))
        checks['exact_top_five_and_show_winners']=actual==want
        if actual!=want:errors.append(dict(missing=sorted(want-actual),unexpected=sorted(actual-want)))
    elif r['report_name']=='judge_report':
        checks['all_named_judges']={int(n) for n in re.findall(r'Synthetic Judge\s+(\d+)',text)}==set(range(1,111))
        checks['no_unknown_judges']='Unknown Judge' not in text and 'Unassigned Judge' not in text
        checks['total_judged']=bool(re.search(r'\b'+str(len(pop))+r'\s+Total Judged',text))
    elif r['report_name']=='paid_exhibitor_report':
        # The independent SQL audit verifies money and section attribution.
        # PDF populations must not count the payment-only fee carriers.
        checks['entry_total']=bool(re.search(r'Total Entries\s+'+str(len(pop))+r'\b',text))
        checks['exhibitor_total']=bool(re.search(r'Total Paid Exhibitors\s+'+str(len({e['exhibitor'] for e in pop}))+r'\b',text))
        online=len(pop)*5;manual=150 if section.endswith('1') else 0
        checks['online_total']=bool(re.search(r'Online Paid\s+\$'+str(online)+r'\.00\b',text))
        checks['cash_total']=bool(re.search(r'Manual Paid\s+\$'+str(manual)+r'\.00\b',text))
        checks['grand_total']=bool(re.search(r'Grand Amount Paid\s+\$'+str(online+manual)+r'\.00\b',text))
        if manual: checks['cash_fee_section_visible']='Open A: fees' in text
    elif r['report_name']=='unpaid_balances_report':
        checks['no_unpaid_balances']='No unpaid' in text or 'no unpaid' in text
    results.append(dict(id=r['id'],report=r['report_name'],breed=r['metadata'].get('breed_name'),
                        section=section,pages=len(pdf.pages),passed=all(checks.values()),checks=checks,errors=errors))
counts=Counter(r['report'] for r in results)
expected=dict(arba_report=2,breed_results_detail_report=104,judge_report=2,paid_exhibitor_report=2,unpaid_balances_report=2)
result=dict(status='passed' if len(results)==112 and counts==expected and all(r['passed'] for r in results) else 'failed',
            reports_checked=len(results),counts=dict(counts),results=results)
(out/'content-audit.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='results'}))
for row in results:
    if not row['passed']:print(json.dumps(row))
if result['status']!='passed':raise SystemExit(1)
