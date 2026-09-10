"""Repeat the two navigation peaks with the corrected historical indexes."""
from pathlib import Path
import sys
from local import Local
from run import Rehearsal
from workflows import Workflows

test=Rehearsal(Local(sys.argv[1]),Path(sys.argv[2]))
try:
    flow=Workflows(test);flow.staff()
    for mode in ('qr','manual'):
        try:flow.parallel_phase('all_'+mode+'_navigation',flow.people[:110],lambda p:flow.navigation(p,mode))
        except RuntimeError:pass
    test.summary['status']='failed' if any(not e['ok'] for e in test.events) else 'passed'
finally:
    test.finish()
    (test.output/'navigation-with-indexes-summary.json').write_bytes((test.output/'summary.json').read_bytes())
if test.summary['status']=='failed':raise SystemExit(1)
