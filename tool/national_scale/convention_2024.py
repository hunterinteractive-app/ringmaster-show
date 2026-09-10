"""Build a deterministic local fixture from verified convention count data."""
import json
from pathlib import Path

SOURCE = Path(__file__).with_name('convention_2024_counts.json')
SHOW = '95000000-0000-0000-0000-000000000001'


def uid(prefix, number):
    return f'{prefix}00000-0000-0000-0000-{number:012d}'


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def proportional(total, weights):
    """Largest remainders, with source order breaking ties; exact integer sum."""
    denominator = sum(weights)
    counts = [total * w // denominator for w in weights]
    order = sorted(range(len(weights)),
                   key=lambda i: (-(total * weights[i] % denominator), i))
    for i in order[:total - sum(counts)]:
        counts[i] += 1
    assert sum(counts) == total
    return counts


def build():
    source = json.loads(SOURCE.read_text())
    assert source['totals'] == dict(open=18867, youth=6844, entries=25711, exhibitors=2528)
    sections, classes, breeds = [], [], []
    next_entry, next_exhibitor = 1, 1
    for section_number, (kind, exhibitor_count) in enumerate(
            [('open', 1855), ('youth', 673)], 1):
        total = source['totals'][kind]
        section = dict(id=uid('951', section_number), kind=kind, entries=total,
                       exhibitors=exhibitor_count, first_exhibitor=next_exhibitor,
                       first_entry=next_entry, last_entry=next_entry + total - 1)
        sections.append(section)

        def exhibitor_for(entry):
            return next_exhibitor + (entry - section['first_entry']) * exhibitor_count // total

        for name, counts in source['breeds'].items():
            assert sum(c[3] for c in counts['youth_classes']) == counts['youth']
            sizes = [c[3] for c in counts['youth_classes']]
            if kind == 'open':
                sizes = proportional(counts['open'], sizes)
            breed_start = next_entry
            for (group, variety, age_sex, _, page), size in zip(counts['youth_classes'], sizes):
                if size == 0:
                    continue
                first, last = next_entry, next_entry + size - 1
                classes.append(dict(section=section_number, breed=name.title(),
                    group=group.title(), variety=variety.title(), class_name=age_sex.title(),
                    count=size, first=first, last=last,
                    exhibitors=exhibitor_for(last) - exhibitor_for(first) + 1,
                    youth_source_page=page))
                next_entry += size
            assert next_entry - breed_start == counts[kind], (kind, name)
            breeds.append(dict(section=section_number, breed=name.title(), count=counts[kind],
                first=breed_start, last=next_entry - 1,
                exhibitors=exhibitor_for(next_entry - 1) - exhibitor_for(breed_start) + 1,
                bob=name not in {'MEAT PEN', 'ROASTER', 'SINGLE FRYER', 'STEWER'}))
        assert next_entry - section['first_entry'] == total
        next_exhibitor += exhibitor_count
    assert next_entry == 25712 and next_exhibitor == 2529
    manifest = dict(show_id=SHOW, totals=source['totals'], sections=sections,
                    classes=classes, breeds=breeds,
                    assumptions=[
                        'One Open A and one Youth A; separate coop numbering.',
                        '1,855 Open and 673 Youth exhibitors; no overlap; synthetic identities.',
                        'Contiguous blocks of 10 or 11 entries per exhibitor; no observed ownership data.',
                        'Exact Youth classes; Open classes scaled from Youth using largest remainders.',
                        'One synthetic animal record per entry, including each meat pen; not a physical rabbit census.',
                        'Synthetic placements and one BOB per breed per section, excluding meat classes.',
                        'All entered/shown; no fur duplicates, scratches, DQs, payments, or real winners.',
                    ])
    class_values = ',\n'.join('(' + ','.join(quote(c[k]) for k in
        ['section', 'breed', 'group', 'variety', 'class_name', 'count', 'first', 'last']) + ')'
        for c in classes)
    breed_values = ',\n'.join(f"({b['first']})" for b in breeds if b['bob'])
    sql = f"""-- Generated synthetic convention fixture. Fresh LOCAL baseline lab only.
-- One block keeps temp-table creation and use together in CLI seed batches.
do $convention$ begin
set local statement_timeout = '120s';
insert into public.shows(id,name,start_date,end_date,coop_numbering_mode,
  secretary_name,secretary_email,is_national_show)
values ('{SHOW}','SYNTHETIC 2024 Convention Counts','2026-09-10','2026-09-10',
  'separate','Synthetic Secretary','convention-secretary@example.test',true);
insert into public.show_sections(id,show_id,kind,letter,display_name,sort_order)
values ('{uid('951', 1)}','{SHOW}','open','A','Open A',1),
       ('{uid('951', 2)}','{SHOW}','youth','A','Youth A',2);
insert into public.show_sanctions(show_id,section_id,club_name,sanction_number,sanctioning_body)
select show_id,id,'Synthetic Convention Club','SYNTHETIC-' || upper(kind),'ARBA'
from public.show_sections where show_id='{SHOW}';
insert into public.exhibitors(id,display_name,first_name,last_name,exhibitor_number,
  email,city,state,arba_number,type,created_for_show_id)
select ('95200000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'Synthetic Convention Exhibitor ' || n,'Synthetic','Convention ' || lpad(n::text,4,'0'),
  n::text,'convention-' || n || '@example.test','Localtown','IN','SYN-C-' || n,
  case when n<=1855 then 'open' else 'youth' end,'{SHOW}'
from generate_series(1,2528) n;
create temporary table convention_classes(section integer,breed text,group_name text,
  variety text,class_name text,amount integer,first_entry integer,last_entry integer) on commit drop;
insert into convention_classes values
{class_values};
create temporary table convention_entries on commit drop as
select n, c.*,case when section=1 then 1+(n-1)*1855/18867
  else 1856+(n-18868)*673/6844 end exhibitor,
  split_part(class_name,' ',2) sex,
  case when section=1 then 'open' else 'youth' end scope
from convention_classes c cross join lateral generate_series(first_entry,last_entry) n;
insert into public.animals(id,species,tattoo,name,breed,variety,sex,class_name)
select ('95300000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'rabbit','C' || lpad(n::text,5,'0'),'Synthetic Convention Animal ' || n,
  breed,variety,sex,class_name from convention_entries;
insert into public.entries(id,show_id,section_id,exhibitor_id,animal_id,species,
  tattoo,animal_name,breed,variety,group_name,sex,class_name,placement,
  result_status,judged_by_show_judge_id,coop_number)
select ('95400000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,'{SHOW}',
  ('95100000-0000-0000-0000-' || lpad(section::text,12,'0'))::uuid,
  ('95200000-0000-0000-0000-' || lpad(exhibitor::text,12,'0'))::uuid,
  ('95300000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'rabbit','C' || lpad(n::text,5,'0'),'Synthetic Convention Animal ' || n,
  breed,variety,group_name,sex,class_name,n-first_entry+1,'placed',
  '31000000-0000-0000-0000-000000000001',
  upper(left(scope,1)) || (case when section=1 then n else n-18867 end)::text
from convention_entries;
insert into public.show_animal_coop_numbers(show_id,animal_id,section_id,coop_number,scope,breed_name)
select show_id,animal_id,section_id,coop_number,
  case when section_id='{uid('951', 1)}' then 'open' else 'youth' end,breed
from public.entries where show_id='{SHOW}';
insert into public.entry_awards(show_id,entry_id,award_code,award)
select '{SHOW}',('95400000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,'BOB','Best of Breed'
from (values {breed_values}) winners(n);
if (select count(*) from public.entries where show_id='{SHOW}') <> 25711 then
  raise exception 'Convention entry count is incorrect'; end if;
end $convention$;
analyze public.entries;
analyze public.exhibitors;
analyze public.animals;
analyze public.entry_awards;
analyze public.show_animal_coop_numbers;
"""
    return sql, manifest
