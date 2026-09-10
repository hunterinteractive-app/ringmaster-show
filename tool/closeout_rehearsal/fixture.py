"""Adapt the count fixture to the full, reconstructed LOCAL schema only."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool/national_scale"))
from convention_2024 import build, quote, uid, SHOW


def fixture():
    base, manifest = build()
    names = sorted({b['breed'] for b in manifest['breeds']})
    catalog = ',\n'.join(
        f"({quote(uid('956', n))}::uuid,{quote(name)},'rabbit',true,true)"
        for n, name in enumerate(names, 1))
    # These historical columns are referenced by the tracked save RPC but were
    # absent from the deliberately small bootstrap. No function is replaced.
    before = f"""
begin;
set local statement_timeout = '180s';
do $$ begin
  if exists(select 1 from public.shows where id='{SHOW}') then
    raise exception 'Refusing to overwrite an existing convention fixture';
  end if;
end $$;
alter table public.entries add column if not exists result_entered_by_user_id uuid;
alter table public.entries add column if not exists result_entered_by_name text;
alter table public.entries add column if not exists result_entered_by_phone text;
alter table public.entries add column if not exists result_entered_at timestamptz;
alter table public.shows add column if not exists is_closed boolean not null default false;
create unique index if not exists local_rehearsal_award_identity
  on public.entry_awards(entry_id,award_code);
insert into public.breeds(id,name,species,is_active,has_prejunior)
select v.* from (values {catalog}) v(id,name,species,is_active,has_prejunior)
where not exists(select 1 from public.breeds b
  where lower(b.name)=lower(v.name) and b.species=v.species);
"""
    # Use BIS/RIS with two different, deterministic BOB winners per section.
    finals = []
    for section in (1, 2):
        winners = [b for b in manifest['breeds'] if b['section'] == section and b['bob']][:2]
        for b, award in zip(winners, ('BIS', 'RIS')):
            finals.append(f"('{SHOW}','{uid('954', b['first'])}','{award}','{award}')")
    after = f"""
update public.shows set final_award_mode='bis_ris', club_name='Synthetic Convention Club',
  location_name='LOCAL TEST ONLY', secretary_address='1 Synthetic Lane, Localtown IN 00000'
where id='{SHOW}';
insert into public.show_breeds(show_id,breed_id,is_enabled)
select '{SHOW}',b.id,true from public.breeds b where b.species='rabbit'
and exists(select 1 from public.entries e where e.show_id='{SHOW}' and lower(e.breed)=lower(b.name));
insert into public.show_judges(show_id,judge_id,section_id,is_enabled)
select '{SHOW}','31000000-0000-0000-0000-000000000001',id,true
from public.show_sections where show_id='{SHOW}';
insert into public.entry_awards(show_id,entry_id,award_code,award)
values {','.join(finals)};
insert into public.show_sanctions(show_id,section_id,breed_name,club_name,sanction_number,sanctioning_body,sweepstakes_email)
select distinct e.show_id,e.section_id,e.breed,'Synthetic '||e.breed||' Club',
  'LOCAL-'||sec.kind||'-'||e.breed,'NATIONAL CLUB','club@example.invalid'
from public.entries e join public.show_sections sec on sec.id=e.section_id
where e.show_id='{SHOW}' and e.breed not in ('Meat Pen','Roaster','Single Fryer','Stewer');
insert into public.show_sanctions(show_id,section_id,club_name,sanction_number,sanctioning_body,sweepstakes_email)
select show_id,id,'Synthetic State Club','LOCAL-STATE-'||kind,'STATE CLUB','state@example.invalid'
from public.show_sections where show_id='{SHOW}';
-- Independent fixed fee: 500 cents per entry; no provider transactions.
insert into public.show_exhibitor_balances(show_id,exhibitor_id,entry_count,
  entries_subtotal_cents,subtotal_before_discount_cents,calculated_total_cents,
  balance_due_cents,payment_status,source,section_breakdown)
select e.show_id,e.exhibitor_id,count(*)::int,count(*)::int*500,count(*)::int*500,
  count(*)::int*500,count(*)::int*500,'unpaid','manual',
  jsonb_build_array(jsonb_build_object('section_id',min(e.section_id::text),
    'entry_count',count(*),'fur_count',0,'entries_subtotal_cents',count(*)*500,
    'fur_subtotal_cents',0,'show_fee_subtotal_cents',0))
from public.entries e where e.show_id='{SHOW}' group by e.show_id,e.exhibitor_id;
-- Youth has 1,000 unfinished results. Staff must save their expected placement
-- through the same authenticated RPC the app uses before Youth can finalize.
update public.entries set placement=null where show_id='{SHOW}'
and id between '{uid('954', 18868)}' and '{uid('954', 19867)}';
commit;
analyze public.entries;
analyze public.show_exhibitor_balances;
"""
    manifest['closeout_rehearsal'] = {
        'staff_sessions': 40, 'checkin_sessions': 16, 'judging_sessions': 20,
        'admin_sessions': 4, 'pending_youth_results': 1000,
        'fee_per_entry_cents': 500, 'expected_fees_cents': 25711 * 500,
        'expected_award_rows': 108,
        'limitations': [
            'Historical show scoring RPC remains a local no-op; scoring parity is not tested.',
            'Fixed synthetic balances are seeded, not computed by registration checkout.',
            'Live provider email delivery is not enabled; only local files are generated.',
            '40 API clients model staff activity, not 40 rendered browser sessions.',
        ],
    }
    return before + base + after, manifest


if __name__ == '__main__':
    target = Path(sys.argv[1])
    target.mkdir(parents=True, exist_ok=True)
    seed, manifest = fixture()
    (target / 'seed.sql').write_text(seed)
    (target / 'convention_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
