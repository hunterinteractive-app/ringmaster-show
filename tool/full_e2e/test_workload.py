"""Offline checks of fixture scaling; no services or workload are started."""
from collections import Counter
import json
from pathlib import Path
import sys
import tempfile
import unittest

from event import specification
from workload import scale_manifest, staff_counts
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'national_scale'))
from convention_2024 import build


class WorkloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _, cls.historical = build()

    def test_default_preserves_historical_populations(self):
        actual = scale_manifest(self.historical)
        for key in ('totals', 'sections', 'classes', 'breeds'):
            self.assertEqual(actual[key], self.historical[key])

    def test_scaled_populations_remain_exact_and_disjoint(self):
        for factor in (2, 4):
            with self.subTest(factor=factor):
                actual = scale_manifest(self.historical, factor)
                self.assertEqual(actual['totals'], dict(open=18867*factor,
                    youth=6844*factor, entries=25711*factor, exhibitors=2528*factor))
                seen=set()
                for row, original in zip(actual['classes'], self.historical['classes']):
                    self.assertEqual(row['count'], original['count']*factor)
                    ids=set(range(row['first'], row['last']+1))
                    self.assertFalse(seen & ids)
                    self.assertEqual(len(ids), row['count'])
                    seen.update(ids)
                self.assertEqual(seen, set(range(1,25711*factor+1)))
                for row, original in zip(actual['breeds'], self.historical['breeds']):
                    self.assertEqual(row['count'], original['count']*factor)
                self.assertEqual(staff_counts(actual), dict(judges=110*factor,
                    admins=10*factor, superintendents=15*factor, checkin=30*factor,
                    support=25*factor, total=135*factor))

    def test_doubled_calendar_changes_and_later_fees(self):
        manifest=scale_manifest(self.historical,2)
        entries=[]
        for row in manifest['classes']:
            s=manifest['sections'][row['section']-1]
            for n in range(row['first'],row['last']+1):
                entries.append(dict(n=n, tattoo=f'C{n:05d}',
                    sex=row['class_name'].split()[-1],
                    exhibitor=s['first_exhibitor']+(n-s['first_entry'])*s['exhibitors']//s['entries']))
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            (out/'manifest.json').write_text(json.dumps(manifest))
            (out/'expected-entries.json').write_text(json.dumps(entries))
            profile=specification(out)
            self.assertEqual(specification(out),profile)
        days=profile['registration_days']
        self.assertEqual([d['day'] for d in days],list(range(1,31)))
        registered=[n for d in days for n in d['exhibitors']]
        self.assertEqual(sorted(registered),list(range(1,5057)))
        self.assertEqual(sum(d['entries'] for d in days),51422)
        for group,fraction in ((days[:14],.25),(days[14:29],.45),(days[29:],.30)):
            self.assertLessEqual(abs(sum(d['entries'] for d in group)-51422*fraction),22)
        self.assertEqual(days[-1]['concurrency'],500)
        self.assertEqual(profile['change_counts'],dict(ear_number=15427,other_sex=2571,scratches=4114))
        changes=profile['changes']
        self.assertEqual(len({c['n'] for c in changes}),sum(profile['change_counts'].values()))
        followups=set(profile['followup_change_entries'])
        self.assertEqual(len(followups),60)
        returned=[c['exhibitor'] for c in changes if c['n'] in followups]
        self.assertEqual(len(set(returned)),60)
        self.assertTrue(set(returned).issubset(profile['checkin_days'][0]))
        charged=Counter(c['exhibitor'] for c in changes if c['fee_cents'])
        self.assertTrue(all(charged[n]>=2 for n in returned))
        self.assertEqual(sum(c['fee_cents'] for c in changes),8999000)
        self.assertEqual(profile['final_report_deadline_seconds'],7200)

    def test_invalid_scales_rejected(self):
        for scale in (0,-1,1.5):
            with self.assertRaises(ValueError):scale_manifest(self.historical,scale)
        with self.assertRaises(ValueError):scale_manifest(self.historical,2,0)


if __name__=='__main__':unittest.main()
