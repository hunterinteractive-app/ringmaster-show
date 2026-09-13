"""Fresh 120-entry functional fixture using the full event stages and audits."""
import argparse
import json
from pathlib import Path
from local import Local, SHOW, uid
import prepare
from event import specification


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace');parser.add_argument('output',type=Path)
    args=parser.parse_args();lab=Local(args.workspace)
    manifest=dict(totals=dict(entries=120,exhibitors=24),fixture_kind='smoke',
                  sections=[],classes=[],breeds=[],assumptions=[])
    for section in (1,2):
        first=1+(section-1)*60
        manifest['sections'].append(dict(id=uid('951',section),kind='open' if section==1 else 'youth',entries=60,exhibitors=12,first_entry=first,last_entry=first+59,first_exhibitor=1+(section-1)*12))
        for j,(breed,variety) in enumerate([('American','Blue'),('Dutch','Black')]):
            start=first+30*j
            manifest['breeds'].append(dict(section=section,breed=breed,count=30,first=start,last=start+29,exhibitors=12,bob=True))
            for k,sex in enumerate(('Buck','Doe')):
                n=start+15*k
                manifest['classes'].append(dict(section=section,breed=breed,variety=variety,class_name='Senior '+sex,group='',count=15,first=n,last=n+14,exhibitors=12))
    prepare.build=lambda:(None,manifest)
    manifest,entries=prepare.prepare(lab,args.output)
    for entry in entries:
        section=manifest['sections'][0 if entry['section_id']==uid('951',1) else 1]
        entry['exhibitor']=section['first_exhibitor']+(entry['n']-section['first_entry'])%12
    manifest['assumptions']=['Functional 120-entry fixture; not a capacity test.','Same check-in percentages and full event API/print stages; two judges and two support staff.']
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2))
    (args.output/'expected-entries.json').write_text(json.dumps(entries))
    profile=specification(args.output)
    profile['registration_days']=[day for day in profile['registration_days'] if day['exhibitors']]
    profile.update(peak_concurrency_assumption=max(d['concurrency'] for d in profile['registration_days']),
                   judge_sessions=2,qr_sessions=1,manual_sessions=1,checkin_sessions=1,admins=1,superintendents=1,
                   followup_change_entries=profile['followup_change_entries'][:1])
    (args.output/'event-profile.json').write_text(json.dumps(profile,indent=2))
    lab.sql(f"update shows set name='LOCAL Restart Preflight 120',start_date=current_date,end_date=current_date where id='{SHOW}';")
    print('Prepared 120 entries / 24 exhibitors / 2 judges; database has zero entries.')


if __name__=='__main__':main()
