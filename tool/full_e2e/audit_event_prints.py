"""Check printed animal populations against pre-check-in and final expectations."""
import json
from pathlib import Path
import re
import sys
import subprocess
from collections import Counter
from pypdf import PdfReader

out=Path(sys.argv[1]);stage=sys.argv[2]
entries=json.loads((out/('expected-entries.json' if stage=='preprint' else 'expected-final-entries.json')).read_text())
modes=['remark-open','remark-youth'] if stage=='remark-recheck' else ['coop','checkin-open','checkin-youth','control-open','control-youth','remark-open','remark-youth'] if stage=='repaired' else ['coop-recheck'] if stage=='coop-recheck' else ['coop','checkin-open','checkin-youth'] if stage=='preprint' else ['control-open','control-youth','remark-open','remark-youth']
results=[]
for mode in modes:
    folder=out/'print-packs'/mode
    result=dict(mode=mode,passed=False)
    try:
        generated=json.loads((folder/'result.json').read_text());assert generated['passed'],generated
        path=Path(generated['file']);pdf=PdfReader(path)
        text_path=folder/'extracted-text.txt'
        subprocess.run(['pdftotext',str(path),str(text_path)],check=True)
        text=text_path.read_text()
        ears=re.findall(r'\bC\d{5}X?\b',text)
        actual=set(ears);occurrences=len(ears)
        coop_labels=text.upper().count('COOP NO.');entry_labels=text.upper().count('ENTRY NO.')
        pop=[e for e in entries if not e.get('scratched') and
             (mode.startswith('coop') or e['section_id'].endswith('1' if mode.endswith('open') else '2'))]
        expected={e['tattoo'] for e in pop}
        # Comment cards have one animal on the main card and another copy on
        # its detachable runner. Repeated animals within either part are errors.
        copies=2 if mode.startswith('remark') else 1
        counts=Counter(ears)
        result.update(expected_animals=len(expected),printed_animals=len(actual),tattoo_occurrences=occurrences,
                      pages=len(pdf.pages),bytes=path.stat().st_size,elapsed_ms=generated['elapsed_ms'],
                      missing=sorted(expected-actual),unexpected=sorted(actual-expected),
                      expected_occurrences_per_animal=copies,
                      duplicate_occurrences=sum(max(0,n-copies) for n in counts.values()),
                      passed=expected==actual and counts==Counter({ear:copies for ear in expected}))
        if mode.startswith('remark'):
            result['runner_card_labels']=len(re.findall(r'DETACHABLE\s+RUNNER\s+CARD',text))
            result['passed']=result['passed'] and result['runner_card_labels']==len(expected)
            # At 72 dpi the landscape page's bottom two-inch card area starts
            # 144 points above the 20-point bottom margin. Audit both regions.
            height=round(float(pdf.pages[0].mediabox.height));boundary=height-20-144
            for part,y,h in (('main',0,boundary),('runner',boundary,height-boundary)):
                cropped=subprocess.run(['pdftotext','-r','72','-x','0','-y',str(y),'-W',str(round(float(pdf.pages[0].mediabox.width))),'-H',str(h),str(path),'-'],check=True,capture_output=True,text=True).stdout
                found=Counter(re.findall(r'\bC\d{5}X?\b',cropped))
                result[part+'_card_population_correct']=found==Counter(expected)
                result['passed']=result['passed'] and result[part+'_card_population_correct']
        if mode.startswith('coop'):
            result.update(coop_number_labels=coop_labels,entry_number_labels=entry_labels,footer_labels=len(re.findall(r'(?:OPEN|YOUTH) RABBIT',text)))
            result['passed']=result['passed'] and occurrences==len(expected) and coop_labels==len(expected) and entry_labels==len(expected) and result['footer_labels']==len(expected)
    except Exception as e:result['error']=str(e)
    results.append(result)
    print(json.dumps({k:v for k,v in result.items() if k not in ('missing','unexpected')}),flush=True)
summary=dict(status='passed' if all(r['passed'] for r in results) else 'failed',stage=stage,results=results,
             total_pages=sum(r.get('pages',0) for r in results),physical_printer_tested=False)
(out/(stage+'-content-audit.json')).write_text(json.dumps(summary,indent=2))
if summary['status']!='passed':raise SystemExit(1)
