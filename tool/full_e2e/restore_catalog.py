"""Restore only the inspected breed abbreviation reference data locally."""
import json
from pathlib import Path
from local import ROOT, Local, sql_quote as q

def restore(lab):
    rows=json.loads((ROOT/'supabase/local/e2e_breed_abbreviations.json').read_text())
    # Missing convention breeds use explicit LOCAL prefixes, not an assertion
    # that these are the national's official coop abbreviations.
    rows += [dict(species='rabbit',breed_name=name,abbreviation=abbr) for name,abbr in [
        ('Blue Holicer','BHC'),('Champagne Dargent','CDG'),('Creme D Argent','CDA'),
        ('Stewer','STW'),('Single Fryer','SFR')]]
    assert len({(r['species'],r['breed_name'].lower()) for r in rows})==len(rows)
    statements=['begin;']
    for r in rows:
        species,name,abbr=map(q,(r['species'],r['breed_name'],r['abbreviation']))
        statements.append(f"delete from public.breed_abbreviations where lower(species)=lower({species}) and lower(breed_name)=lower({name}); insert into public.breed_abbreviations(species,breed_name,abbreviation) values({species},{name},{abbr});")
    statements.append('commit;')
    lab.sql('\n'.join(statements))
    return len(rows)

if __name__=='__main__':
    import sys
    print('Restored',restore(Local(sys.argv[1])),'reference abbreviations.')
