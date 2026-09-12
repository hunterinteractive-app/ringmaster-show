# Restarted section rehearsal — September 11, 2026

**The targeted sections passed, including an uninterrupted closeout repeat that
generated all 6,361 checkout reports in 11 minutes 30 seconds.** The first
closeout attempt was interrupted by repeated Mac sleep events; its failures
remain recorded separately.

The retained synthetic convention has 25,711 entries and 2,528 exhibitors in
one Open and one Youth show. Its 2,057 scratches leave 17,337 Open and 6,317 Youth
animals active. Registration used a separate synthetic 250-purchaser show.
No production deployment, real payment, or external email was performed.

| Section | Result | Measured evidence |
| --- | --- | --- |
| Registration and payment | Passed | 250 new purchasers completed signup, sign-in, account lookup, checkout, signed payment callbacks and duplicate-request checks. Exactly 250 paid entries, carts and provider sessions. Zero failed operations. Checkout p95 4.65 seconds; maximum 6.74 seconds. Peak database connections 41, including 20 Auth connections. |
| Print packs | Passed | All seven actual Flutter generator paths produced complete packs totaling 22,687 pages. No missing or excess animal occurrences. All 23,654 coop labels, entry labels and scope footers are present. |
| Detachable comment-card runners | Passed | Every active animal appears once in its main card and once in its runner. Open: 17,337 matching pairs; Youth: 6,317. Both regions were audited separately. |
| Simultaneous navigation | Passed | 110 clerks, 10 admins and 15 superintendents. All 5,878 manual pages and 224 QR pages loaded without errors. Manual-page p95 1.47 seconds; maximum 4.86 seconds. The roster contains all 2,528 exhibitors. |
| Closeout regeneration | Passed on uninterrupted repeat | All 6,361 artifacts received a new generation and completed in 690.23 seconds, including queue preparation, combined finalization replay and worker recovery. Budget: 7,200 seconds. Both sections passed readiness before generation. |
| Staff activity during closeout | Passed on uninterrupted repeat | 24,647 judging reads, 3,230 admin reads and 5,066 superintendent reads; zero errors. Their p95 times were 59 ms, 234 ms and 70 ms. |
| Worker interruption | Passed | One of four workers was killed. Four interrupted tasks completed on surviving workers with the same generation and exactly one additional attempt. Completion replay succeeded and a changed checksum was rejected. No manual recovery RPC or retry was used for those interrupted tasks. |
| Saved files and report contents | Passed | All 6,361 files matched stored sizes and SHA-256 hashes: 3,683,863,287 bytes. Complete exhibitor-report coverage for 2,528 exhibitors and all 653 expected leg certificates; zero content mismatches. The audit distinguishes 507 empty leg placeholders from earned certificates. |
| Official checkout reports | Passed | 107 reports: 104 section/breed reports and combined judge, paid-exhibitor and unpaid-balance reports. Expected populations, placings, winners and financial totals matched. |
| ARBA reports | Passed | Both real PDF renders contain the correct active counts, distinct Open/Youth sanction labels and all 110 judges. Each has three pages. |
| Delivery and retry | Passed | 250 packages reached the local receiver with matching recipients and attachment hashes. An accepted request followed by a 16-second stall recovered with exactly one message. Replaying it returned already-sent. Other sends: p95 256 ms, maximum 438 ms. |
| Permissions and finalization replay | Passed | PIN ownership, nonstaff denial, revoked old PINs and delivery-history access checks passed. Finalization replay showed 6,361 generated, zero queued and zero failed, with no extra tasks. |

All 112 database test results, 22 focused Flutter tests and five Edge retry tests
passed. The database suites include the latest fur add-on duplicate-entry fix.
One initial Edge test invocation failed type checking because it lacked the
explicit Deno configuration; rerunning with the repository configuration passed
without skipping type checking or changing application code. Both logs remain.
Representative print pages, the long-identifier coop layout, and both ARBA first
pages were visually inspected.

**The interrupted attempt is preserved.** It generated 6,344 reports and left
17 exhibitor reports failed. All 17 timeout events occurred within five seconds
of recorded Mac wake events. Later, the synthetic staff access tokens expired,
producing 9,592 rejected requests. These observations make that attempt
unsuitable for capacity timing. The uninterrupted repeat used fresh sessions,
temporary idle sleep prevention and the same frozen application/database code.
Its wall-clock and active-time difference was less than one millisecond. All
17 previously affected reports generated successfully in the repeat.

The source snapshot contains 719 files from commit
`a10892e22dd561a81013bd115c8360be26f6945c` plus the existing uncommitted repairs.
It includes the detachable runner-card change and fur cart-item fix. Worker
source links resolve inside the snapshot. Source hashes, the original local
migration manifest and separately applied repair hashes are retained. The
original migration baseline was not rewritten. This was a repaired local
fixture, not a fresh database bootstrap.

This run rechecked the repaired sections. Registration used one-entry carts;
the original event's check-in edits and judging saves were retained. It did not
repeat the complete month's arrival pattern, both days of check-in changes, or
all judging writes. Concurrency represents authenticated API sessions; native
Flutter tests exercised the print widgets. Physical QR scanning, printers,
hosted capacity, real payment settlement, full email distribution and backup
restoration were outside this repeat. ARBA PDFs were rendered directly from the
selected run's artifacts; their deferred distribution workflow was not repeated.

The closeout repeat regenerated an existing combined finalization population.
The dead worker's leases were advanced locally, so recovery correctness was
tested without waiting for the normal lease interval. The temporary sleep
prevention ended after testing. Future long rehearsals should also detect host
suspension and refresh synthetic staff tokens if they outlast their lifetime.

Evidence is retained at
`output/full_e2e/section-restart-20260911/` in the application repository:

- `registration/`, `prints/`, and `navigation/`: the successful initial sections.
- `closeout/`: the sleep-interrupted attempt, preserved as failed.
- `host-sleep-events.txt` and `sleep-timeout-correlation.json`: interruption evidence.
- `awake-repeat/closeout/`: the successful new generation, recovery and file audits.
- `awake-repeat/arba/`, `awake-repeat/delivery/`, and
  `awake-repeat/contracts/`: subsequent scoped checks.
- `source-manifest.json`, `final-source-check.json`, `fixture-provenance.json`,
  `final-database-state.json` and `stage-status.json`: provenance and final state.

Local Supabase services were stopped with their data volumes preserved. The
next broader validation is a fresh full-event rehearsal using the complete
current migration set and matching app, Edge Function and worker versions.
