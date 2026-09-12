# Separate rehearsal stages — September 11, 2026

**Archived run; superseded by the user's requested restart.** The original stages
below passed before concurrent source changes. The late comment-card repeat
generated successfully, but its new content audit was still pending at restart.
These results do not certify the subsequently frozen source snapshot.
The completed restart is recorded in `docs/section-restart-2026-09-11.md`.
These were new executions of the repaired sections,
using the retained synthetic convention fixture. They were not a fresh event
from registration opening through checkout. No production deployment, real
payment or external email was performed.

The retained show has 25,711 entries and 2,528 exhibitors: one Open and one Youth
section. Its 2,057 scratches leave 17,337 Open and 6,317 Youth animals active.
The new registration probe uses a separate synthetic show.

| Stage | Result | Evidence |
| --- | --- | --- |
| Registration/payment burst | **Passed** | 250 new simultaneous purchasers completed signup, sign-in, account lookup, checkout and signed payment callbacks. Exactly 250 paid entries, carts and provider sessions; no duplicates or failed operations. Checkout p95 2.63 seconds, maximum 4.31 seconds. Peak database connections: 47, including the bounded 20-connection Auth pool. |
| Check-in and judging print packs | **Passed** | Seven complete packs, totaling 22,687 pages. Exact expected populations, zero missing animals, zero unexpected animals and zero duplicate occurrences. All 23,654 coop cards have coop/entry number labels and scope footers. Representative coop, check-in, judging and comment-card pages were visually inspected. |
| Simultaneous staff navigation | **Passed** | 110 clerks, 10 admins and 15 superintendents. All 5,878 manual pages and 224 QR pages loaded without errors. Manual-page p95 1.41 seconds; maximum 4.36 seconds. The roster contains all 2,528 exhibitors. |
| Combined Open/Youth closeout | **Passed** | All 6,361 queued checkout reports generated in **774.58 seconds — 12 minutes 54.6 seconds**, within the 7,200-second budget. Both sections passed readiness before generation. |
| Staff activity during closeout | **Passed** | 27,945 judging reads, 3,686 admin dashboard reads and 5,730 superintendent dashboard reads; zero errors. Their p95 times were 40 ms, 179 ms and 50 ms respectively. |
| Worker interruption | **Passed** | One of four workers was killed. Three interrupted tasks completed on surviving workers, retaining their generation and incrementing their attempt count once. Completion replay succeeded; an altered checksum was rejected. No manual requeue or test-invoked recovery RPC was used. |
| Saved-file and exhibitor/leg audit | **Passed** | All 6,361 files matched Storage size/hash metadata, covering 3,683,866,308 bytes. All 2,528 exhibitor reports have the exact expected active tattoos. All 653 expected leg certificates are present; 507 empty leg placeholders are distinguished from earned certificates. |
| Official checkout report contents | **Passed** | 107 reports: 104 section/breed reports plus combined judge, paid-exhibitor and unpaid-balance reports. Breed placings, show winners, judge totals, entry/exhibitor totals and online/cash amounts matched the independent expectations. |
| ARBA counts | **Passed** | Both PDFs were rendered from this combined run's artifacts using the real renderer. They contain 17,337 Open and 6,317 Youth rabbits, and all 110 judges. First pages were visually inspected. |
| Delivery and stalled-provider retry | **Passed** | 250 packages from this run reached the local receiver with matching recipients and attachment hashes. An accepted-but-stalled request recovered in 15.86 seconds with exactly one accepted message. The other 249 sends had p95 305 ms. Replaying the first send returned already-sent without another message. |
| PIN, permission and dashboard contracts | **Passed** | Own-PIN access, nonstaff denial, old-PIN revocation and delivery-history permissions passed. The exact V2 combined scope reports 6,361 generated, zero queued and zero failed. Finalization replay reused the run and created no extra tasks. |

All 112 database assertions and 15 complete-read/delivery-loader/retry tests also
passed. Python compilation, scoped ARBA-helper analysis and whitespace checks
passed. Test helpers gained an explicit finalize-run filter and combined report
auditing so older separate-section runs cannot contaminate these results.

A concurrent commit (`b6da0e9`) changed the detachable runner-card layout after
the initial print stage. The source check caught that change. Only the two
affected comment-card packs were repeated; their new audit checks the main-card
and runner-card populations separately, requiring one occurrence per animal in
each part. Two layout tests also passed with runners enabled and disabled.
The core closeout/worker rendering implementation remained unchanged.

## Boundaries

- The registration probe used one-entry carts for 250 new purchasers. It tests
  the Auth/payment burst, not the complete month's arrival distribution.
- Check-in edits and judging saves were retained from the earlier event. This
  run repeated their affected printing/navigation paths, not both days of
  changes or all result-entry writes.
- The combined queue was already prepared by the repair checks. The timed stage
  included readiness, reuse of that finalization, generation and worker recovery;
  it did not create a new finalization population from scratch.
- Only the dead worker's leases were advanced locally. This verifies recovery
  behavior but does not measure the normal lease-expiry wait.
- Concurrency represents authenticated API sessions. Native Flutter tests ran
  the actual print widgets. PIN/dashboard checks exercised their APIs; this run
  did not launch 135 rendered browsers, scan physical QR codes or run printers.
- Stripe/email provider responses were local emulations. ARBA PDFs were tested
  directly; the application still defers their distribution until its delivery
  requirements are satisfied. Full exhibitor/club distribution was not repeated.
- The original event's frozen migration baseline and separately applied repairs
  were preserved. This is evidence for the repaired stages on the local fixture,
  not fresh-migration, hosted-capacity or national-show certification.

## Retained evidence

All evidence is in
[`output/full_e2e/section-rehearsal-20260911`](../output/full_e2e/section-rehearsal-20260911/).
`stage-status.json` records this run as superseded. The late comment-card
repeat's content audit was not completed before restart. The principal
summaries are:

- `registration/summary.json`
- `prints/repaired-content-audit.json` and `comment-card-repeat/summary.json`
- `navigation/summary.json`
- `closeout/closeout-summary.json` and `closeout/worker-recovery.json`
- `closeout/pdf-audit-summary.json` and `closeout/official-report-content-audit.json`
- `arba/content-audit.json`, `delivery/summary.json` and `contracts/summary.json`

`selected-finalize-run.json`, `source-manifest.json`, `harness-amendments.json`,
`comment-card-repeat-sources.json` and `baseline-migration-manifest.json` identify
the tested run and sources.
The report archive and failed-run evidence from earlier rehearsals are retained.
Local services were stopped with their data volumes preserved, then restarted
for the later comment-card check and the requested new run.

The next broader validation remains a fresh event using the complete current
migration set and matching application, Edge and worker versions.
