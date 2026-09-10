"""Restore inspected historical read indexes missing from the loader baseline."""
import json
import sys
from local import Local,ROOT
NAMES={'idx_entries_results','idx_entries_show_exhibitor','idx_entry_awards_show_entry',
       'entry_awards_entry_id_idx','idx_results_show_entry','idx_show_exhibitor_lookup',
       'idx_sweepstakes_results_breed_name','idx_sweepstakes_results_scope',
       'idx_sweepstakes_results_show_breed_scope','idx_sweepstakes_results_show_id',
       'varieties_breed_id_sort_order_idx','idx_variety_groups_breed_id','exhibitors_owner_idx','exhibitors_owner_active_idx'}
def restore(lab):
    existing={r['indexname'] for r in lab.rows("select indexname from pg_indexes where schemaname='public'")}
    rows=json.loads((ROOT/'supabase/local/e2e_historical_indexes.json').read_text())
    missing=[r for r in rows if r['indexname'] in NAMES and r['indexname'] not in existing]
    lab.sql('begin;\n'+'\n'.join(r['indexdef']+';' for r in missing)+'\ncommit;\nanalyze;')
    return [r['indexname'] for r in missing]
if __name__=='__main__': print(json.dumps(restore(Local(sys.argv[1]))))
