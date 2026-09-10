# National-scale testing: fixes and local results

For the subsequent completeness fixes, repaired tests, and rerun results, see
[the September 10 follow-up](national-readiness-fixes.md). Earlier failures below
are retained as historical test evidence.

The subsequent [2024 convention-count rehearsal](convention-2024-testing.md)
uses the supplied Open/Youth PDFs and 2,528 exhibitors. The original stress
scenario and its observations below remain separate.

## Fix verification

The confirmed report failures are fixed in the working tree. All **nine local
scale checks pass** with the same 30,000 animals, 60,000 entries, and 3,000
exhibitors. No API limit was raised and no hosted system was changed.

| Check | Corrected output | Local elapsed time |
| --- | --- | --- |
| Fixture counts | All expected counts reconcile | Less than one second |
| Balance-entry loader | 60,000 distinct entries | 28.4 s |
| Entered-exhibitor list | All 3,000 exhibitors | 2.8 s |
| Coop-card loader | 30,000 unique animals, both A/B sections | 35.3 s |
| Batched ID enrichment | All 100 and all 500 requested entries | Less than one second |
| Exhibitor 1 report | All 20 entries; populations 6,000/24,000 | 22.8 s |
| Exhibitor 3000 report | All 20 entries; populations 6,000/24,000 | 22.3 s |
| Exhibitor 1 legs | Four certificates; correct animal/exhibitor counts | 21.8 s |

Total: **9 passes in 133 seconds**. These timings include complete data reads;
they cannot be compared as a speed improvement against the earlier truncated
reports. The lab still uses simplified baseline RPCs and local service-role
access, so these are not production throughput estimates.

Changes:

- A shared page reader continues until an empty page and advances by the actual
  number received. It handles server limits below the requested page size.
  Table lookups use explicit ordering; result reads retain the legacy RPC's order.
- UUID enrichment uses batches of 100 and paginates one-to-many results such as
  entry awards. The former raw 500-ID diagnostic now exercises this production
  reader and still requires all 500 entries. A regression also verifies that
  request URLs remain bounded and each batch contains at most 100 IDs.
- Exhibitor and leg populations use indexed counts rather than repeatedly
  scanning the full section for every entry. Eligibility rules remain distinct
  for class, breed, variety, group, and show awards.
- An exhibitor report shares its loaded results with its own leg check. The
  next report loads fresh data; there is no persistent result cache. Leg loading
  counts the whole selected scope but hydrates only the requested exhibitor.
- Failed award reads propagate rather than turning into apparently empty awards.
  Placement display separates Open/Youth sections even when they share a letter.

Validation: **34 focused regression checks pass**, including 17 new checks for
pagination boundaries, smaller server caps, interrupted reads, UUID batching,
one-to-many awards, duplicate fur results, scratches/disqualifications, species
and section boundaries, and fresh data on later requests. Analysis of all changed
Dart files reports no issues. The full Flutter suite reports **343 passes, the
same 11 pre-existing failures, and 10 skipped opt-in integration tests**. The
worker suite remains **47 passes and the same one pre-existing failure**. Those
unrelated failures are described in the initial results below.

Current evidence is in `output/national_scale/fixes-scale-tests.log`,
`fixes-regression-tests.log`, `fixes-all-tests.log`, `fixes-worker-tests.log`, and
`fixes-analysis.log`. No deployment or database migration is required to review
these source changes; release of the app and worker remains a separate step.

The section reads still occur separately for subsequent exhibitor reports. The
next dataset/rehearsal should measure full closeout throughput and simultaneous
staff activity, as well as behavior when results change during a multi-page read.

## Initial failure reproduction

Run date: September 9, 2026 (America/Indiana/Indianapolis).
Repository base revision: `202c60d`.

The first local test pass reproduced report truncation and a coop-card request
failure. The historical observations below explain the fixes above. Neither run
establishes national-show capacity or readiness.

## Synthetic scenario

The local database contains 30,000 animals, 3,000 exhibitors, two Open sections,
60,000 entries, 30,000 combined coop assignments, two synthetic ARBA sanctions,
and four breed-winning entries. Each exhibitor has ten animals and 20 entries.
Each section contains 24,000 Mini Rex and 6,000 Jersey Wooly. All entries are
shown, with deterministic placements and four known qualifying legs belonging
to exhibitor 1. This is a deliberately concentrated loader stress case, not a
model of the actual national's breed mix, classes, or simultaneous staff work.

Supabase CLI 2.95.4 runs the repository's local baseline in Docker, with an API
row limit of 1,000. Tests call the actual Flutter report loaders using local
service-role credentials. Exact-count API requests verify the fixture totals
independently of the loaders being tested.

## Observations

| Check | Required output | Observed output | Result |
| --- | --- | --- | --- |
| Fixture counts | 60,000 entries; 30,000 animals/coops; 3,000 exhibitors; 4 awards | Counts reconcile | Pass |
| Balance-entry loader | 60,000 distinct entry IDs | 60,000 distinct IDs, 32.1 seconds | Pass |
| Entered-exhibitor list | 3,000 exhibitors | 1,000 exhibitors | Fail |
| Coop-card loader | 30,000 unique animal cards, each with A and B | HTTP 414, `URI too long`, during loading | Fail |
| ID enrichment, 100 UUIDs | 100 rows | 100 rows | Pass |
| ID enrichment, 500 UUIDs | 500 rows | HTTP 414, `URI too long` | Fail |
| Exhibitor 1 report | 20 entries; correct class populations | 2 entries; reported class population 1,000 | Fail |
| Exhibitor 3000 report | 20 entries | Throws `No shown result rows found` | Fail |
| Exhibitor 1 legs | 4 certificates; populations 24,000 or 6,000 | 2 certificates; population 1,000 | Fail |

Final scale run: **3 passes and 6 failures in 79 seconds**. The two ID-enrichment
checks isolate the same request-size failure seen in the coop loader; six failing
tests should not be interpreted as six independent defects.

The leg fixture was checked against the loader's sanction requirement and supplied
with synthetic section sanctions before the authoritative final run. The earlier
zero-leg observation from a fixture without sanctions is not an application defect.

The entered-exhibitor loader reads entries without pagination and deduplicates
only the returned rows. The exhibitor and leg loaders each read section-wide
`report_results_entry_rows` without pagination. Jersey Wooly sorts first in this
fixture, so those readers receive only its first 1,000 rows in each section;
Mini Rex and later Jersey Wooly entries are absent. This also corrupts the
population totals used on reports and certificates.

Relevant code:

- `lib/screens/admin/closeout/data/loaders/entered_exhibitors_list_report_loader.dart:17`
- `lib/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart:53`
- `lib/screens/admin/closeout/data/loaders/legs_report_loader.dart:622`
- `lib/screens/admin/closeout/data/loaders/coop_cards_report_loader.dart:255`

Coop loading uses 500 UUIDs in a GET `in` filter. The focused enrichment checks
reproduce rejection at 500 IDs and success at 100 on the same local gateway.
This request-size boundary depends on gateway configuration; it is not a
measurement of the hosted gateway's exact limit.

## Existing tests

Before adding the scale harness, `flutter test --reporter expanded` completed
with **326 passes, 11 failures, and one skipped local integration test**:

- One grouped-specialty breed-count assertion expects 4 and receives 5.
- The generic widget test cannot compile browser-only `dart:html` imports on the
  native Flutter test platform.
- Nine closeout architecture/source-contract assertions fail, including a
  reference to a missing migration file. These need individual review; a failed
  source-text assertion alone does not prove a runtime defect.

The initial headless worker suite completed with **47 passes and one failure**. Its
failing source-contract assertion expects a particular exact-scope expression
in the unpaid-balance loader.

The new opt-in harness is analyzed separately and is skipped by ordinary test
runs. Its expected outputs remain complete counts; those checks now pass.

## Reproduce and inspect

See [the runner instructions](../tool/national_scale/README.md).
The workspace created for this run is
`/tmp/ringmaster-national-loader-lab-20260910`.
Local services were stopped after testing, with the synthetic database retained.

```sh
supabase start --workdir /tmp/ringmaster-national-loader-lab-20260910 --exclude edge-runtime,logflare,vector,supavisor,studio,postgres-meta,imgproxy
python3 tool/national_scale/run.py /tmp/ringmaster-national-loader-lab-20260910
```

Local logs are saved under `output/national_scale/` (ignored by Git):
`scale-tests.log`, `baseline-flutter-tests.log`, `worker-tests.log`, and
`harness-analysis.log`. The runner returns a nonzero status for failing tests.

## Remaining work

1. Continue the complete-read audit across report paths beyond the failures
   exercised here. Measure repeated section reads across thousands of exhibitor
   reports; per-entry population scans and duplicate reads within one exhibitor
   report have been removed, but full-closeout throughput is not yet established.
2. Repair the local full-schema bootstrap. Applying all checked-in migrations
   currently stops at `20260718164151_add_national_club_sanction_links.sql`
   because the reconstructed baseline lacks legacy directory tables.
3. Run a faithful staging rehearsal with the real show sections and breed/class
   distribution, authenticated users and RLS, registration/check-in/judging
   activity, payments and reconciliation, full closeout rendering/delivery,
   retried writes, worker recovery, and backup restoration.

The loader lab applies the checked-in baseline only. That baseline contains
simplified reconstructions of legacy RPCs and does not include all current
migrations, triggers, or production indexes. Its timings are diagnostic local
observations, not production throughput estimates. No production data was
changed. A proposed production schema-only export was rejected by automatic
approval review as outside the synthetic-local-data authorization; the run
continued using only repository fixtures.
