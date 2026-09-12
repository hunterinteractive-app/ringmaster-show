"""Repeat the two navigation peaks with the corrected historical indexes."""
from pathlib import Path
import sys
from local import Local, SHOW
from run import Rehearsal
from workflows import Workflows

test=Rehearsal(Local(sys.argv[1]),Path(sys.argv[2]))
try:
    flow=Workflows(test);flow.staff()
    for mode in ('qr','manual'):
        try:flow.parallel_phase('all_'+mode+'_navigation',flow.people[:110],lambda p:flow.navigation(p,mode))
        except RuntimeError:pass
    roster=[];after=None
    while True:
        page=flow.rpc('get_show_checkin_roster_page',dict(p_show_id=SHOW,p_after_exhibitor_id=after,p_page_size=1000),flow.people[110],'complete_roster_read')
        if not page:break
        roster.extend(page);after=page[-1]['exhibitor_id']
    assert len(roster)==2528 and len({r['exhibitor_id'] for r in roster})==2528
    test.summary['checks']['complete_checkin_roster']=len(roster)
    test.summary['status']='failed' if any(not e['ok'] for e in test.events) or any(p['failures'] for p in test.summary['phases'].values()) else 'passed'
except Exception as e:
    test.summary.update(status='failed',error=str(e));raise
finally:
    test.finish()
    (test.output/'navigation-with-indexes-summary.json').write_bytes((test.output/'summary.json').read_bytes())
if test.summary['status']=='failed':raise SystemExit(1)
