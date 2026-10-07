"""Validate exact scenario totals and indivisible purchaser cohorts offline."""
from collections import Counter
import unittest
from registration_scenario import manifest_for, calendar, exact_cohort
from workload import staff_counts


class RegistrationScenarioTests(unittest.TestCase):
    def test_35k_distribution_and_65_percent_day(self):
        m = manifest_for()
        entries = []
        for row in m['classes']:
            s = m['sections'][row['section']-1]
            for n in range(row['first'], row['last']+1):
                entries.append(dict(n=n, exhibitor=s['first_exhibitor']+
                    (n-s['first_entry'])*s['exhibitors']//s['entries']))
        self.assertEqual([e['n'] for e in entries], list(range(1,35001)))
        self.assertEqual(len({e['exhibitor'] for e in entries}), 3441)
        self.assertEqual(sum(b['count'] for b in m['breeds']), 35000)
        p = calendar(entries)
        self.assertEqual(calendar(entries), p)
        days = p['registration_days']
        self.assertEqual([sum(d['entries'] for d in group) for group in
                          (days[:14], days[14:29], days[29:])], [8750,3500,22750])
        selected = [n for d in days for n in d['exhibitors']]
        self.assertEqual(sorted(selected), list(range(1,3442)))
        self.assertEqual(days[-1]['concurrency'], 500)
        self.assertEqual(staff_counts(m)['support'], 12)
        self.assertEqual(Counter(Counter(e['exhibitor'] for e in entries).values()).keys(), {10,11})

    def test_impossible_cart_split_rejected(self):
        with self.assertRaises(ValueError): exact_cohort([1,2], {1:10,2:11}, 5)

    def test_invalid_percent_rejected(self):
        for percent in (0,75,100):
            with self.assertRaises(ValueError): calendar([], percent)


if __name__ == '__main__': unittest.main()
