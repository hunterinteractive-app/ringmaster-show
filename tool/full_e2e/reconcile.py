"""Independent expected-value checks; never repair data to make a check pass."""
from collections import Counter, defaultdict
import json
from pathlib import Path
import sys
from local import Local, SHOW, uid


def reconcile(lab,out):
    expected=json.loads((out/'expected-final-entries.json').read_text())
    manifest=json.loads((out/'manifest.json').read_text())
    checks={}
    def check(name,want,got):
        checks[name]=dict(passed=want==got,expected=want,actual=got)
    rows=lab.rows(f"select id,animal_id,exhibitor_id,section_id,breed,variety,class_name,sex,tattoo,placement,payment_status from entries where show_id='{SHOW}'")
    check('entry_count',25711,len(rows))
    by_id={r['id']:r for r in rows};mismatches=[]
    for e in expected:
        r=by_id.get(e['id'],{})
        want=dict(animal_id=uid('953',e['n']),exhibitor_id=uid('952',e['exhibitor']),
                  section_id=e['section_id'],breed=e['breed'],variety=e['variety'],
                  class_name=e['class_name'],sex=e['sex'],tattoo=e['tattoo'],
                  placement=str(e['placement']),payment_status='paid')
        bad={k:dict(expected=v,actual=r.get(k)) for k,v in want.items() if str(r.get(k) or '')!=str(v or '')}
        if bad:mismatches.append(dict(entry_id=e['id'],fields=bad))
    (out/'entry-reconciliation-mismatches.json').write_text(json.dumps(mismatches,indent=2))
    check('entry_field_mismatches',0,len(mismatches))
    check('exhibitors',2528,len({r['exhibitor_id'] for r in rows}))
    check('section_counts',{uid('951',1):18867,uid('951',2):6844},dict(Counter(r['section_id'] for r in rows)))
    awards={}
    for b in manifest['breeds']:
        if b['bob']:awards[b['first']]=['BOB']
    for section in (1,2):
        for b,code in zip([b for b in manifest['breeds'] if b['section']==section and b['bob']][:2],('BIS','RIS')):
            awards[b['first']].append(code)
    ids={e['n']:e['id'] for e in expected}
    want_awards=sorted((ids[n],code) for n,codes in awards.items() for code in codes)
    actual_awards=lab.rows(f"select entry_id,award_code from entry_awards where show_id='{SHOW}'")
    check('award_assignments',len(want_awards),len(actual_awards))
    check('award_mismatches',0,len(set(want_awards)^set((r['entry_id'],r['award_code']) for r in actual_awards)))
    want_points={(e['id'],'CLASS'):max(0,6-e['placement']) for e in expected if e['placement']<=5}
    actual_points=defaultdict(float)
    for r in lab.rows(f"select entry_id,points_source,points from sweepstakes_entry_results where show_id='{SHOW}'"):
        actual_points[(r['entry_id'],r['points_source'])]+=r['points']
    check('individual_score_mismatches',0,sum(want_points.get(k,0)!=actual_points.get(k,0) for k in set(want_points)|set(actual_points)))
    totals=lab.rows(f"select scope,sum(total_points) total from sweepstakes_results where show_id='{SHOW}' group by 1")
    check('aggregate_sweepstakes_points',{'OPEN':12776,'YOUTH':10572},{r['scope']:r['total'] for r in totals})
    payments=lab.rows(f"select provider,count(*) n,sum(total_cents) total,sum(refunded_cents) refunded from show_payments where show_id='{SHOW}' and payment_status='paid' group by 1")
    check('payment_counts',{'stripe':2528,'cash':30},{r['provider']:r['n'] for r in payments})
    check('payment_amounts_cents',{'stripe':12855500,'cash':15000},{r['provider']:r['total'] for r in payments})
    balances=lab.rows(f"select count(*) n,sum(calculated_total_cents) charged,sum(paid_online_cents) online,sum(paid_manual_cents) manual,sum(balance_due_cents) due from show_exhibitor_balances where show_id='{SHOW}'")[0]
    check('balance_ledger',dict(n=2558,charged=12870500,online=12855500,manual=15000,due=0),balances)
    check('completed_checkins',2528,int(lab.sql(f"select count(*) from show_checkin_records where show_id='{SHOW}' and status='completed'")))
    changes=lab.rows(f"select count(*) n,sum(fee_cents) fee from show_checkin_change_requests where show_id='{SHOW}' and status='approved'")[0]
    check('approved_changes',dict(n=30,fee=15000),changes)
    coops=lab.rows(f"select animal_id,scope,breed_name,coop_number from show_animal_coop_numbers where show_id='{SHOW}'")
    check('coop_assignments',25711,len(coops))
    check('coop_animal_coverage',25711,len({r['animal_id'] for r in coops}))
    collisions=lab.rows(f"select scope,coop_number,count(*) n,array_agg(distinct breed_name) breeds from show_animal_coop_numbers where show_id='{SHOW}' group by 1,2 having count(*)>1")
    (out/'coop-label-collisions.json').write_text(json.dumps(collisions,indent=2))
    check('duplicate_coop_labels_within_section',0,sum(r['n']-1 for r in collisions))
    result=dict(status='passed' if all(c['passed'] for c in checks.values()) else 'failed',checks=checks,
                limitations=['Scores use the explicit synthetic flat 5/4/3/2/1 schedule; real club rules require separate fixtures.',
                             'Local breed abbreviation catalog is incomplete; collision evidence is retained.',
                             'Leg certificate counts and report bytes are checked separately.'])
    (out/'reconciliation.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
    return result

if __name__=='__main__':
    result=reconcile(Local(sys.argv[1]),Path(sys.argv[2]))
    if result['status']=='failed':raise SystemExit(1)
