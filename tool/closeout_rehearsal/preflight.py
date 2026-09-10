"""Measure local fixture readiness before launching the staff workload."""
import json
import sys
from lab import Lab, SHOW, elapsed

lab = Lab(sys.argv[1])
staff = lab.staff(1)[0]
result = {'sections': {}}
for section in (1, 2):
    value, ms = elapsed(lambda: lab.readiness(section, staff['token']))
    result['sections'][section] = {'readiness': value, 'duration_ms': ms}
roster, ms = elapsed(lambda: lab.rpc('get_show_checkin_roster', {'p_show_id': SHOW}, staff['token']))
result['roster'] = {'returned': len(roster), 'expected': 2528, 'duration_ms': ms}
dashboard, ms = elapsed(lambda: lab.rpc('get_show_checkin_dashboard', {'p_show_id': SHOW}, staff['token']))
result['checkin_dashboard'] = {'result': dashboard, 'duration_ms': ms}
qr, ms = elapsed(lambda: lab.rpc('report_results_entry_rows',
    {'p_show_id': SHOW, 'p_section_id': '95100000-0000-0000-0000-000000000001'}, staff['token']))
result['qr_judging_section_read'] = {'returned': len(qr), 'expected': 18867,
    'duration_ms': ms, 'breeds_in_response': sorted({r['breed'] for r in qr})}
print(json.dumps(result, indent=2))
