# Doubled full-event rehearsal — September 12, 2026

**Result: failed at the closeout dashboard after successful finalization.**
The requested registration repairs, recovery of seven incomplete purchases, and
500-purchaser retest passed. A new event then started from an empty local database
and passed registration, printing, check-in and simultaneous judging. It stopped
at a new dashboard timeout before report workers started. This is not a passing
full closeout rehearsal or a national-capacity certification.

## Completed repairs and recovery

- Checkout preserves transient database errors as retryable 503 responses.
- Account reads and safe registration writes retry within a three-attempt bound.
  Stable IDs and authenticated read-back recover uncertain commits without
  duplicating or overwriting records. Validation failures permit form corrections.
- Local Auth and REST each use a bounded 20-connection pool; the database limit
  remains 100. Production settings were not changed.
- Coop assignment uses an efficient existing-assignment exclusion, preserving
  numbering, permission checks and NULL/overwrite behavior.
- Coop-card assignment reads use a complete animal/scope cursor rather than
  increasingly expensive offsets, with unchanged loading/rendering deadlines.
- The assertion-enabled judging-sheet integration test allows valid large class
  tables beyond the PDF library's default 20-page guard. That guard is disabled
  in release builds; this was a test-build failure, not demonstrated production
  truncation. The 481-animal class and its continuation pages were checked.

All seven original accounts recovered their 71 missing entries. Existing carts
were reused, completed entry/payment hashes stayed unchanged, payments were
unique per cart/session, and balances reconciled to zero. The real Dart save
helper was exercised with a deliberately lost response after a committed write,
replayed writes, and a denied cross-owner read.

The final burst completed **500/500 purchases**, adding 5,061 paid entries and
$25,305 in simulated payments in **20.38 seconds**, alongside 20 admins and 30
superintendents. There were no failed actions or pool timeouts. The original
failed burst and diagnostic failures remain preserved.

Focused verification: 16 Dart tests, 8 Python tests, 7 Edge tests, 10 coop-number
regression cases, Flutter analysis, Edge type checking, real print-screen checks,
printed-population audits and `git diff --check` passed. The registration repair
report contains the detailed comparison evidence.

## Fresh event profile

| Workload | Configuration |
| --- | ---: |
| Exhibitors | 5,056: 3,710 Open / 1,346 Youth, no overlap |
| Entries | 51,422: 37,734 Open / 13,688 Youth |
| Registration | Compressed 30-day calendar; approximately 25% early, 45% before final day, 30% final day |
| Last-day purchasers | 1,518; peak 500 simultaneous |
| Check-in | Two days; 60 clerks + 20 admins + 30 superintendents |
| Changes | 15,427 ear changes, 2,571 sex changes, 4,114 scratches |
| Active animals after scratches | 47,308 |
| Judging | Two days; 220 tables + 50 support sessions; Open and Youth together |
| Judging methods | 110 QR / 110 manual sessions, each with work on both days |
| Planned report workers | Four processes / 16 renders before planned interruption |
| Checkout generation target | Two hours after judging |

The historical 25,711-entry workload and staffing were doubled. The calendar's
actual cohort days remain 1–14, 15–29, and day 30; calendar time is compressed.
Both sections completed judging before finalization began.

## Fresh phase results

| Phase | Result | Wall time |
| --- | --- | ---: |
| registration | Passed | 170.89 s |
| preprint | Passed | 169.70 s |
| preprint-audit | Passed | 28.17 s |
| checkin | Passed | 275.55 s |
| judgeprint | Passed | 386.24 s |
| judgeprint-audit | Passed | 134.84 s |
| judging | Passed | 103.62 s |
| closeout | Failed | 54.45 s |

Registration completed all **51,422 paid entries and 5,056 purchasers**. The final
day completed its 15,417 entries at peak concurrency 500 in **54.61 seconds**,
with zero failed purchases. Transient HTTP failures recovered within the retry
policy and remain in raw logs; zero failed actions does not mean zero HTTP errors.

Pre-event print audits checked **17,912 pages**. Judging-pack audits checked
**27,318 pages**, including all active animals exactly once on judging sheets and
once on each main/detachable comment-card part. No required animal was missing
or duplicated. These are generated files, not physical-printer measurements.

Both check-in days passed. All 22,112 changes were approved; 60 returning
exhibitors exercised subsequent paid changes, preserving 7,562 earlier payment
records. All 5,056 exhibitors completed check-in.

Judging saved **24,109 QR results and 23,199 manual results** without failed saves.
All 202 deliberately replayed saves also passed. QR/manual save p95 latency was
approximately 1.03/1.04 seconds; maxima were 5.58/3.84 seconds. Both sections passed
readiness. Day one covered 25,351 animals; day two covered 21,957.

## Closeout failure and follow-up evidence

The real `run-closeout` call succeeded in **34.26 seconds**, creating 11,695
artifacts: **11,693 queued rendering tasks** and two deferred ARBA artifacts.
The immediately following `get_closeout_dashboard_scoped_for_species` request
failed after **8.01 seconds**, with SQLSTATE `57014` (statement timeout). Eighteen
concurrent admin dashboard refreshes also timed out. No report workers started;
there was no report-generation, worker-recovery, delivery or backup result.

This differs from the original registration connection-pool acquisition failures.
The full run recorded zero REST pool timeouts and a peak of 58 database connections.
The cause of the post-finalization dashboard failure is **not yet established**.

After the launcher stopped its services, a read-only diagnostic restarted the
same retained database. A single dashboard call took about 120 ms inside PostgreSQL.
With the same 20/20 pool configuration, 20 admins and 30 superintendents then
completed 150 read-only requests without errors. Combined dashboard p95 was
1.22 seconds, maximum 1.30 seconds. This shows that the restart changed observable
behavior; it does not prove that restart fixes the underlying cause. No report
or entry data was altered to obtain these read results.

An independent post-failure reconciliation passed **all 16 checks**:

- 51,422 entries, 5,056 exhibitors, exact section counts and zero entry-field mismatches.
- All placements, 108 awards and individual/aggregate synthetic points matched.
- 5,056 simulated online payments totaling **$257,110**.
- 5,067 cash change payments totaling **$89,990**.
- **$347,100** charged and paid; zero remaining balances.
- All check-ins and approved changes matched; coop coverage was complete with
  no duplicate labels within either section.

Leg certificate correctness and final PDF content remain untested in this run
because rendering did not begin.

## Remaining work

Reproduce the dashboard failure at the transition from an empty report queue to
first large finalization, with the existing connections and concurrent admin
polling left active. Capture query plans, statistics and waits during that
transition, then fix and retest it without restarting services. A fast query
after a restart is insufficient evidence of a repair.

After that targeted check passes, complete a fresh closeout rehearsal covering
the two-hour generation target, the planned worker interruption, all PDF/leg
content audits, navigation, simulated delivery and backup restoration. Do this
before increasing the event size again. The two-hour target was **not evaluated**
in this run.

## Evidence and limits

Fresh project: `ringmaster-show-full-e2e-double-r6-0912`.
Workspace: `/tmp/ringmaster-show-full-e2e-double-r6-20260912`.
Frozen source, worker/input hashes, all 230 migration hashes, phase logs, resource
samples and original failure are in `output/full_e2e/double-event-r6-20260912/`.
Read-only diagnostics and reconciliation are in its `dashboard-diagnostic/`
subdirectory. Earlier failed runs remain separately preserved.

Changes remain local and uncommitted; nothing from this turn was deployed or
pushed. Synthetic providers emulate payments and email protocols; no real
charges or messages were sent. Hosted resources, real provider behavior,
physical printers, actual QR scanning and simultaneous rendered browser sessions
were not tested. The local historical schema restoration is selective; complete
production schema parity is not claimed. Synthetic flat points and coop-prefix
fixtures do not certify every real club's rules.

## Follow-up: dashboard repair verified locally

The failure above was subsequently reproduced and fixed. Cached one-row plans
from the empty queue caused repeated scans after first finalization. The scoped
planning fix passed 416 concurrent probe requests with zero failures and a
1.101-second maximum dashboard read; all ten content comparisons and access
checks passed. See [the dashboard repair report](closeout-dashboard-fix-2026-09-12.md).
The original full-event status remains failed, and its unfinished closeout
stages still require a new rehearsal.
