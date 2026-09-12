"""Repeat the two navigation peaks with the corrected historical indexes."""
from pathlib import Path
import sys
from local import Local, SHOW
from run import Rehearsal
from workflows import Workflows
from configure_capacity import configure

test=Rehearsal(Local(sys.argv[1]),Path(sys.argv[2]))
try:
    # A standalone invocation may follow a CLI restart, which recreates the
    # default gateway and pool limits. Restore the intended load-test budget
    # before authenticating staff or opening the navigation barrier.
    test.summary['checks']['capacity']=configure(test.lab)
    flow=Workflows(test);flow.staff()
    largest='--largest-breed' in sys.argv[3:]
    if largest:
        targets=[max((b for b in test.manifest['breeds'] if b['section']==n),key=lambda b:b['count']) for n in (1,2)]
        test.summary['checks']['largest_breed_targets']=[dict(section=b['section'],breed=b['breed'],entries=b['count']) for b in targets]
        test.manifest['breeds']=targets
    test.summary['checks']['manual_page_size']=250
    for mode in (('manual',) if largest else ('qr','manual')):
        try:flow.parallel_phase('all_'+mode+'_navigation',flow.people[:flow.judge_count],lambda p:flow.navigation(p,mode))
        except RuntimeError:pass
    roster=[];after=None
    while True:
        page=flow.rpc('get_show_checkin_roster_page',dict(p_show_id=SHOW,p_after_exhibitor_id=after,p_page_size=1000),flow.people[flow.judge_count],'complete_roster_read')
        if not page:break
        roster.extend(page);after=page[-1]['exhibitor_id']
    assert len(roster)==len(test.by_exhibitor) and len({r['exhibitor_id'] for r in roster})==len(test.by_exhibitor)
    test.summary['checks']['complete_checkin_roster']=len(roster)
    test.summary['status']='failed' if any(not e['ok'] for e in test.events) or any(p['failures'] for p in test.summary['phases'].values()) else 'passed'
except Exception as e:
    test.summary.update(status='failed',error=str(e));raise
finally:
    test.finish()
    (test.output/'navigation-with-indexes-summary.json').write_bytes((test.output/'summary.json').read_bytes())
if test.summary['status']=='failed':raise SystemExit(1)
