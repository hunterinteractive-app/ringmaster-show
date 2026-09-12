"""Reconcile all breed choices, full sections, exact links and access control."""
import json
from pathlib import Path
import sys
import time
from local import Local, SHOW, uid, ApiError

lab = Local(sys.argv[1])
out = Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
assert not (out/'judging-scope-audit.json').exists(), 'Preserve previous evidence'
clerk = lab.person('judging-scope-clerk')
lab.sql(f"insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{clerk['user_id']}','reporting_clerk'); insert into show_managers(show_id,user_id,can_manage_entries,can_manage_settings,can_finalize) values ('{SHOW}','{clerk['user_id']}',true,false,false)")
expected = lab.rows(f"select e.id,e.section_id,e.breed,e.species,e.animal_id,e.scratched_at,coalesce((select jsonb_agg(a.award_code order by a.award_code,a.id) from entry_awards a where a.entry_id=e.id and a.show_id=e.show_id),'[]') awards from entries e where e.show_id='{SHOW}' order by e.id")
by_id = {e['id']:e for e in expected}
checks = {}; pages = 0
def read(section=None, breed=None, entry_ids=None):
    global pages
    ids=[]; after=None
    while True:
        page=lab.rpc('get_judging_entry_rows_page',dict(p_show_id=SHOW,p_section_id=section,
            p_breed=breed,p_entry_ids=entry_ids,p_after_entry_id=after,p_page_size=250),clerk['token'])
        pages+=1
        if not page: break
        for r in page:
            e=by_id[r['entry_id']]
            assert r['section_id']==e['section_id'] and r['animal_id']==e['animal_id']
            assert r['species']==e['species'] and r['_awards']==e['awards']
            assert bool(r['scratched_at'])==bool(e['scratched_at'])
            assert after is None or r['entry_id']>after
            ids.append(r['entry_id'])
        after=page[-1]['entry_id']
    assert len(ids)==len(set(ids))
    return set(ids)

start=time.monotonic()
for number in (1,2):
    section=uid('951',number)
    wanted={e['id'] for e in expected if e['section_id']==section}
    index=lab.rpc('get_judging_breed_index',dict(p_show_id=SHOW,p_section_id=section),clerk['token'])
    assert len({r['breed_key'] for r in index})==len(index)
    assert sum(r['entry_count'] for r in index)==len(wanted)
    seen=set()
    for b in index:
        actual=read(section,b['breed'])
        want={e['id'] for e in expected if e['section_id']==section and (e['breed'] or '').strip().lower()==b['breed_key']}
        assert actual==want and len(actual)==b['entry_count']
        assert not seen.intersection(actual)
        seen.update(actual)
    assert seen==wanted
    assert read(section)==wanted, 'Explicit full-section validation read omitted entries'
    assert not read(section,'Nonexistent synthetic breed')
    readiness=lab.rpc('get_judging_section_readiness',dict(p_show_id=SHOW,p_section_id=section),clerk['token'])
    canonical=lab.rpc('show_results_readiness_scoped',dict(p_show_id=SHOW,p_section_ids=[section]))
    assert readiness==canonical, 'Staff readiness differs from the canonical validator'
    checks[section]=dict(breeds=len(index),entries=len(wanted),readiness=readiness)

target=expected[-1]['id']
assert read(entry_ids=[target])=={target}
outsider=lab.person('judging-scope-outsider')
for role,token in [('anonymous',lab.anon),('unrelated_user',outsider['token'])]:
    try: lab.rpc('get_judging_breed_index',dict(p_show_id=SHOW,p_section_id=uid('951',1)),token)
    except ApiError as error:
        assert error.code in (401,403), str(error)
        checks[role]='denied'
    else: raise AssertionError(role+' was allowed to read the show')

summary=dict(status='passed',entries=len(expected),pages=pages,elapsed_s=time.monotonic()-start,checks=checks)
(out/'judging-scope-audit.json').write_text(json.dumps(summary,indent=2))
print(json.dumps({k:v for k,v in summary.items() if k!='checks'}))
