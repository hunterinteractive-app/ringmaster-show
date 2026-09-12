"""Prepare a fresh local-only workflow fixture; never insert entries or payments."""
import json
from pathlib import Path
import sys
from local import Local, ROOT, SHOW, uid, sql_quote as q
sys.path.insert(0, str(ROOT / 'tool/national_scale'))
from convention_2024 import build


def prepare(lab, output):
    if int(lab.sql(f"select count(*) from public.shows where id='{SHOW}'")):
        raise RuntimeError('Fresh show required; preserve previous run evidence')
    contracts = json.loads((ROOT / 'supabase/local/e2e_historical_contracts.json').read_text())
    columns = json.loads((ROOT / 'supabase/local/e2e_historical_columns.json').read_text())
    existing = {(r['table_name'], r['column_name']) for r in lab.rows("select table_name,column_name from information_schema.columns where table_schema='public'")}
    existing_tables = {t for t, _ in existing}
    statements = ['begin;']
    needed = {'breed_rules_matrix', 'breed_rules_profiles', 'entry_carts', 'breed_abbreviations', 'show_animal_coop_numbers', 'show_exhibitor_balances', 'closeout_jobs'}
    specific = {'shows': {'is_closed', 'finalized_at','is_demo','demo_resets_at','timezone','entry_open_at'}, 'exhibitors': {'claimed_by_user_id',
                'birth_date','group_members','group_shows_as_youth','claimed_at',
                'imported_from','imported_source_id','imported_at'},
                'animals': {'exhibitor_id'}}
    for table in sorted(needed - existing_tables):
        statements.append(f'create table public.{table} (); alter table public.{table} enable row level security; grant all on public.{table} to service_role;')
    for c in columns:
        t, n = c['table_name'], c['column_name']
        if (t not in needed and n not in specific.get(t, set())) or (t, n) in existing:
            continue
        assert c['data_type'] in ('uuid', 'text', 'integer', 'numeric', 'boolean', 'timestamp with time zone', 'jsonb','date')
        default = ' default ' + c['column_default'] if c['column_default'] else ''
        statements.append(f'alter table public.{t} add column {n} {c["data_type"]}{default};')
    statements += [
        'alter table public.entries add column if not exists result_entered_by_user_id uuid, add column if not exists result_entered_by_name text, add column if not exists result_entered_by_phone text, add column if not exists result_entered_at timestamptz;',
        'alter table public.sweepstakes_entry_results alter column exhibitor_id type text using exhibitor_id::text;',
        'alter table public.show_report_artifacts add column if not exists warning_count integer default 0;',
        'alter table public.show_payment_account_links add column if not exists payouts_enabled boolean default false;',
        'create unique index if not exists local_e2e_award_identity on public.entry_awards(entry_id,award_code);',
        'alter table public.show_animal_coop_numbers drop constraint show_animal_coop_numbers_pkey;',
        'alter table public.show_animal_coop_numbers alter column section_id drop not null;',
        'create unique index local_e2e_coop_identity on public.show_animal_coop_numbers(show_id,animal_id,scope);',
        # The loader baseline used void placeholders for these historical APIs.
        'drop function public.calculate_sweepstakes_for_show(uuid,text,text);',
        'drop function public.apply_show_payment_to_balance(uuid);',
        'drop function public.calculate_sweepstakes_for_breed_baseline(uuid,text,text,text);',
    ]
    allow = {'calculate_sweepstakes_for_show', 'calculate_sweepstakes_for_breed_baseline',
             'user_can_enter_results', 'calculate_entry_cart_balance_without_canada_special'}
    for f in contracts['functions']:
        if f['proname'] in allow:
            statements.append(f['definition'] + ';')
    for f in sorted(json.loads((ROOT / 'supabase/local/e2e_historical_extras.json').read_text()), key=lambda f: 0 if f['arguments']=='p_role app_role' else 1):
        statements.append(f['definition'] + ';')
    # The original loader-only baseline returned JSON here. Real workers use
    # the historical typed result contracts; restore them before any rendering.
    for f in json.loads((ROOT / 'supabase/local/e2e_historical_breed_reports.json').read_text()):
        signature = f"public.{f['proname']}({f['arguments']})"
        statements += [f'drop function {signature};', f['definition'] + ';',
                       f'revoke all on function {signature} from public,anon;',
                       f'grant execute on function {signature} to authenticated,service_role;']
    # Only historical owner policies needed by this rehearsal. Preserve all
    # tracked policies; do not invent an authenticated-allow-all test bypass.
    names = {'entry_carts_owner_all', 'cart_items_insert_own', 'cart_items_select_own',
             'cart_items_delete_own', 'animals_insert_own', 'animals_select_own',
             'exhibitors_insert_own', 'exhibitors_select_own', 'exhibitors_update_own',
             'shows_select_published', 'show_sections_select_authenticated',
             'breeds_read_all', 'show_breeds_read_published_show',
             'show_fee_settings_select_authenticated', 'Authenticated users can read show fee settings'}
    existing_policies = {(r['tablename'], r['policyname']) for r in lab.rows("select tablename,policyname from pg_policies where schemaname='public'")}
    for p in contracts['policies']:
        if p['policyname'] not in names or (p['tablename'], p['policyname']) in existing_policies:
            continue
        roles = p['roles'].strip('{}')
        sql = f'create policy "{p["policyname"]}" on public.{p["tablename"]} for {p["cmd"]} to {roles}'
        if p['qual']: sql += ' using (' + p['qual'] + ')'
        if p['with_check']: sql += ' with check (' + p['with_check'] + ')'
        statements.append(sql + ';')
    statements += ['grant insert,update,delete on public.entry_carts, public.entry_cart_items, public.animals, public.exhibitors to authenticated;',
                   'revoke all on function public.calculate_sweepstakes_for_show(uuid,text,text), public.calculate_sweepstakes_for_breed_baseline(uuid,text,text,text), public.user_can_enter_results(uuid,uuid) from public,anon;',
                   'grant execute on function public.calculate_sweepstakes_for_show(uuid,text,text), public.calculate_sweepstakes_for_breed_baseline(uuid,text,text,text), public.user_can_enter_results(uuid,uuid) to authenticated,service_role;']
    _, manifest = build()
    statements.append(f"insert into public.shows(id,name,start_date,end_date,coop_numbering_mode,secretary_name,secretary_email,is_national_show,is_published,is_test,payment_timing_mode,final_award_mode,club_name,location_name,secretary_address) values ('{SHOW}','LOCAL E2E Convention 25711','2026-09-10','2026-09-10','separate','Synthetic Secretary','secretary@example.invalid',true,true,true,'online_or_at_show','bis_ris','Synthetic Convention Club','LOCAL ONLY','1 Synthetic Lane, Localtown IN 00000');")
    for s in manifest['sections']:
        statements.append(f"insert into public.show_sections(id,show_id,kind,letter,display_name,sort_order) values ('{s['id']}','{SHOW}','{s['kind']}','A','{s['kind'].title()} A',{1 if s['kind']=='open' else 2});")
        statements.append(f"insert into public.show_section_fee_settings(section_id,fee_per_entry) values ('{s['id']}',5);")
        for body, club in [('ARBA', 'Synthetic Convention Club'), ('STATE CLUB', 'Synthetic State Club')]:
            statements.append(f"insert into public.show_sanctions(show_id,section_id,club_name,sanction_number,sanctioning_body,sweepstakes_email) values ('{SHOW}','{s['id']}',{q(club)},{q('LOCAL-'+s['kind']+'-'+body)},{q(body)},'club@example.invalid');")
    statements.append(f"insert into public.show_fee_settings(show_id,currency) values ('{SHOW}','usd'); insert into public.show_payment_settings(show_id,stripe_enabled) values ('{SHOW}',true); insert into public.show_payment_account_links(show_id,provider,stripe_account_id,charges_enabled,account_status) values ('{SHOW}','stripe','acct_local_synthetic',true,'ready');")
    names = sorted({b['breed'] for b in manifest['breeds']})
    for i, name in enumerate(names, 1):
        statements.append(f"insert into public.breeds(id,name,species,is_active,has_prejunior) select '{uid('956',i)}',{q(name)},'rabbit',true,true where not exists(select 1 from public.breeds where lower(name)=lower({q(name)}) and species='rabbit');")
    statements.append(f"insert into public.show_breeds(show_id,breed_id,is_enabled) select '{SHOW}',id,true from public.breeds where species='rabbit';")
    for b in manifest['breeds']:
        if b['bob']:
            statements.append(f"insert into public.show_sanctions(show_id,section_id,breed_name,club_name,sanction_number,sanctioning_body,sweepstakes_email) values ('{SHOW}','{uid('951',b['section'])}',{q(b['breed'])},{q('Synthetic '+b['breed']+' Club')},{q('LOCAL-'+str(b['section'])+'-'+b['breed'])},'NATIONAL CLUB','club@example.invalid');")
    # Explicit synthetic flat schedule gives independently calculable scores.
    for name in names:
        statements.append(f"insert into public.breed_rules_matrix(breed_name,engine_family,class_points_model,place_1,place_2,place_3,place_4,place_5,status,rule_source) values ({q(name)},'ADDITIVE_LIGHT','FLAT_BY_PLACING',5,4,3,2,1,'verified','LOCAL SYNTHETIC') on conflict (breed_name) do update set class_points_model='FLAT_BY_PLACING',place_1=5,place_2=4,place_3=3,place_4=2,place_5=1,status='verified';")
    entries = []
    for c in manifest['classes']:
        s = manifest['sections'][c['section']-1]
        age, _, sex = c['class_name'].rpartition(' ')
        if sex not in ('Buck','Doe'): age, sex = c['class_name'], ''
        for n in range(c['first'],c['last']+1):
            entries.append(dict(n=n,exhibitor=s['first_exhibitor']+(n-s['first_entry'])*s['exhibitors']//s['entries'],
                section_id=s['id'],species='rabbit',tattoo=f'C{n:05d}',animal_name=f'Synthetic Animal {n}',
                breed=c['breed'],variety=c['variety'],class_name=age,sex=sex,placement=n-c['first']+1,
                group=c['group']))
    for i in range(1,111):
        statements.append(f"insert into public.judges(id,display_name,name,first_name,last_name,arba_number,arba_judge_number) values ('{uid('958',i)}','Synthetic Judge {i}','Synthetic Judge {i}','Synthetic','Judge {i}','LOCAL-{i}','LOCAL-{i}'); insert into public.show_judges(show_id,judge_id,section_id,is_enabled) values ('{SHOW}','{uid('958',i)}','{uid('951',1+(i%2))}',true);")
    statements += ['commit;', "notify pgrst, 'reload schema';"]
    script='\n'.join(statements)
    output.mkdir(parents=True,exist_ok=False)
    (output/'foundation-and-show.sql').write_text(script)
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2))
    (output/'expected-entries.json').write_text(json.dumps(entries))
    lab.sql(script)
    from restore_indexes import restore
    restore(lab)
    from restore_profiles import restore as restore_profiles
    restore_profiles(lab)
    from restore_closeout_access import restore as restore_closeout_access
    restore_closeout_access(lab)
    from restore_catalog import restore as restore_catalog
    restore_catalog(lab)
    lab.sql((ROOT/'supabase/local/e2e_account_lookup.sql').read_text())
    from restore_print_reports import restore as restore_print_reports
    restore_print_reports(lab)
    from restore_staff_pins import restore as restore_staff_pins
    restore_staff_pins(lab)
    assert int(lab.sql(f"select count(*) from public.entries where show_id='{SHOW}'")) == 0
    return manifest, entries

if __name__ == '__main__':
    prepare(Local(sys.argv[1]),Path(sys.argv[2]))
    print('Fresh show prepared with zero entries and zero payments.')
