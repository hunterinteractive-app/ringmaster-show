"""Check official PDF populations, including successful-but-truncated reports."""
from collections import Counter,defaultdict
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
profile=json.loads((out/'event-profile.json').read_text()) if (out/'event-profile.json').exists() else None
combined='--combined' in sys.argv[2:]
checkout_only='--checkout-only' in sys.argv[2:]
show_winners=defaultdict(set)
for section in (1,2):
    for b in [b for b in manifest['breeds'] if b['section']==section and b['bob']][:2]:
        e=by_n[b['first']];show_winners[e['section_id']].add(e['tattoo'])
if (out/'expected-awards.json').exists():
    show_winners=defaultdict(set)
    for n,codes in json.loads((out/'expected-awards.json').read_text()).items():
        if {'BIS','RIS'}&set(codes):
            e=by_n[int(n)];show_winners[e['section_id']].add(e['tattoo'])
with zipfile.ZipFile(out/'report-files.zip') as archive:
    for a in artifacts:
        names=('arba_report','breed_results_detail_report','judge_report','paid_exhibitor_report','unpaid_balances_report') if profile else ('arba_report','breed_results_detail_report')
        if a['report_name'] not in names:continue
        pdf=PdfReader(io.BytesIO(archive.read(a['id']+'.pdf')))
        text='\n'.join(p.extract_text() or '' for p in pdf.pages)
        sections=a['section_ids']
        if a['report_name'] in ('arba_report','breed_results_detail_report') or not combined:
            assert len(sections)==1, 'A section report must have one section'
        else:
            assert set(sections)=={e['section_id'] for e in entries}, 'Combined report must cover both sections'
        section=sections[0];registered=[e for e in entries if e['section_id'] in sections]
        population=[e for e in registered if not e.get('scratched')]
        issues=[];checks={}
        if a['report_name']=='arba_report':
            found=re.search(r'Number of Rabbits Exhibited:\s*([\d,]+)',text)
            actual=int(found[1].replace(',','')) if found else None
            checks['rabbits_shown']=dict(expected=len(population),actual=actual)
            judges={int(n) for n in re.findall(r'Synthetic Judge\s+(\d+)',text)}
            checks['judges_printed']=dict(expected=110,actual=len(judges))
            if actual!=len(population):issues.append('Incorrect rabbit total')
            if judges!=set(range(1,111)):issues.append('Incomplete judge list')
        elif a['report_name']=='breed_results_detail_report':
            population=[e for e in population if e['breed']==a['metadata']['breed_name']]
            # This report promises top-five class placings plus show awards,
            # rather than printing every lower placing from the full population.
            want={e['tattoo'] for e in population if e['placement']<=5}|show_winners[section]
            actual=set(re.findall(r'\bC\d{5}X?\b',text))
            checks['animal_coverage']=dict(expected=len(want),actual=len(actual),missing=sorted(want-actual),unexpected=sorted(actual-want))
            if actual!=want:issues.append('Incomplete breed-report animal coverage')
        elif a['report_name']=='judge_report':
            checks['all_named_judges']={int(n) for n in re.findall(r'Synthetic Judge\s+(\d+)',text)}==set(range(1,111))
            checks['no_unknown_judges']='Unknown Judge' not in text and 'Unassigned Judge' not in text
            checks['total_judged']=bool(re.search(r'\b'+str(len(population))+r'\s+Total Judged',text))
        elif a['report_name']=='paid_exhibitor_report':
            checks['entry_total']=bool(re.search(r'Total Entries\s+'+str(len(registered))+r'\b',text))
            checks['exhibitor_total']=bool(re.search(r'Total Paid Exhibitors\s+'+str(len({e['exhibitor'] for e in registered}))+r'\b',text))
            online=len(registered)*5
            manual=sum(c['fee_cents'] for c in profile['changes'] if by_n[c['n']]['section_id'] in sections)/100
            for key,label,amount in [('online_total','Online Paid',online),('cash_total','Manual Paid',manual),('grand_total','Grand Amount Paid',online+manual)]:
                checks[key]=bool(re.search(label+r'\s+\$'+re.escape(f'{amount:.2f}')+r'\b',text.replace(',','')))
        else:
            checks['no_unpaid_balances']='No unpaid' in text or 'no unpaid' in text
        for name,value in checks.items():
            if value is False:issues.append('Failed '+name)
        results.append(dict(artifact_id=a['id'],report_name=a['report_name'],section_ids=sections,pages=len(pdf.pages),checks=checks,issues=issues))
expected_counts={'breed_results_detail_report':104}
if not checkout_only:expected_counts['arba_report']=2
if profile:expected_counts.update({name:1 if combined else 2 for name in ('judge_report','paid_exhibitor_report','unpaid_balances_report')})
counts=dict(Counter(r['report_name'] for r in results))
result=dict(status='failed' if counts!=expected_counts or any(r['issues'] for r in results) else 'passed',
            reports_checked=len(results),counts=counts,expected_counts=expected_counts,
            failed_reports=sum(bool(r['issues']) for r in results),results=results)
(out/'official-report-content-audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items() if k!='results'}))
print(json.dumps([r for r in results if r['report_name']=='arba_report'],indent=2))
if result['status']=='failed':raise SystemExit(1)
