"""Exact registration-volume scenarios; no production access or seeding entries."""
from collections import Counter
from copy import deepcopy
import random
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'national_scale'))
from convention_2024 import build, proportional


def manifest_for(total=35000):
    if total < 25711:
        raise ValueError('This growth scenario requires at least the historical entry count')
    _, original = build()
    m = deepcopy(original)
    m.update(fixture_kind='registration_only', historical_totals=original['totals'])
    exhibitors = round(total * 2528 / 25711)
    sizes = proportional(total, [s['entries'] for s in original['sections']])
    owners = proportional(exhibitors, [s['exhibitors'] for s in original['sections']])
    m['totals'] = dict(open=sizes[0], youth=sizes[1], entries=total, exhibitors=exhibitors)
    entry = owner = 1
    for number, section in enumerate(m['sections'], 1):
        size, count = sizes[number-1], owners[number-1]
        section.update(entries=size, exhibitors=count, first_entry=entry,
                       last_entry=entry+size-1, first_exhibitor=owner)
        rows = [c for c in m['classes'] if c['section'] == number]
        def ownership(first, last):
            return (last-section['first_entry'])*count//size - (first-section['first_entry'])*count//size + 1
        for row, amount in zip(rows, proportional(size, [c['count'] for c in rows])):
            row.update(count=amount, first=entry, last=entry+amount-1,
                       exhibitors=ownership(entry, entry+amount-1))
            entry += amount
        for breed in [b for b in m['breeds'] if b['section'] == number]:
            classes = [c for c in rows if c['breed'] == breed['breed']]
            first, last = classes[0]['first'], classes[-1]['last']
            breed.update(count=sum(c['count'] for c in classes), first=first,
                         last=last, exhibitors=ownership(first, last))
        owner += count
    m['assumptions'] = [
        'Registration-only growth fixture; historical Open/Youth and class proportions rounded by largest remainders.',
        'Synthetic exhibitors retain approximately the historical entries-per-exhibitor ratio; Open/Youth have no overlap.',
        'One synthetic animal record per entry, including meat pens; not a physical animal census.',
        'Four admins and eight superintendents read dashboards during registration.',
        'Purchaser concurrency is an explicit stress assumption, not inferred from public count updates.',
    ]
    return m


def exact_cohort(ordered, counts, target):
    """Select whole purchasers with an exact entry sum using bounded subset sums."""
    reachable = 1
    mask = (1 << (target+1))-1
    parents = {}
    for n in ordered:
        shifted = (reachable << counts[n]) & mask
        new = shifted & ~reachable
        while new:
            bit = new & -new
            amount = bit.bit_length()-1
            parents[amount] = (amount-counts[n], n)
            new ^= bit
        reachable |= shifted
        if reachable & (1 << target):
            chosen = set()
            while target:
                target, n = parents[target]
                chosen.add(n)
            return [n for n in ordered if n in chosen]
    raise ValueError('Cannot satisfy exact phase share with whole purchaser carts')


def calendar(entries, final_percent=65, peak=500):
    if not 1 <= final_percent <= 74 or peak < 1:
        raise ValueError('Final-day percent must leave room for the 25% early phase and middle phase')
    counts = Counter(e['exhibitor'] for e in entries)
    ordered = sorted(counts)
    random.Random(20261006).shuffle(ordered)
    total = len(entries)
    if total % 100:
        raise ValueError('Use a total divisible by 100 for exact percentage cohorts')
    days = []
    phases = ((1,14,25,40),(15,29,75-final_percent,200),(30,30,final_percent,peak))
    for start, end, percent, limit in phases:
        group = exact_cohort(ordered, counts, total*percent//100)
        selected = set(group)
        ordered = [n for n in ordered if n not in selected]
        for day in range(start, end+1):
            daily = group[day-start::end-start+1]
            if not daily:
                raise ValueError('Not enough exhibitors for a nonempty daily cohort')
            days.append(dict(day=day, exhibitors=daily, entries=sum(counts[n] for n in daily),
                             concurrency=min(limit, len(daily))))
    assert not ordered
    return dict(scope='registration_only', seed=20261006, calendar_days=30,
                calendar_compressed=True, entries=total, exhibitors=len(counts),
                registration_days=days, early_share=.25, middle_share=(75-final_percent)/100,
                last_day_share_of_all_entries=final_percent/100,
                peak_concurrency_assumption=peak, admins=4, superintendents=8,
                physical_printer_tested=False)
