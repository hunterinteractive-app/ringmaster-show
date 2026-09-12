# Doubled closeout rehearsal — September 12, 2026

**Overall result: failed on one contact-list PDF. All independent correctness,
delivery and recovery audits completed successfully. Manual navigation remains
a performance concern before a larger rehearsal.**

This was a fresh local closeout from the completed 51,422-entry synthetic judging
fixture in `double-event-r6-20260912`. Registration, check-in, print preparation
and judging were not repeated. The earlier full-event failure remains recorded
separately.

Fresh finalization and staff load passed. The rendering stage completed 11,692
tasks and failed one `entered_exhibitors_contact_report` after its PDF builder
exceeded the two-minute render limit. The complete closeout process, including
staff setup and warmup, took 1,708.58 seconds (28 minutes 28.6 seconds). This is
not a complete two-hour deadline pass because that report remains missing.

All four tasks interrupted by the worker failure completed on surviving workers,
with unchanged generations and exactly one additional attempt. Completion replay
succeeded and a changed checksum was rejected. The recovered tasks waited in
the existing queue before finishing; recovery completed after 1,643.67 seconds.

The 270 staff sessions made 162,279 background requests with zero errors:
120,788 judging reads, 16,418 admin dashboard reads and 25,073 superintendent
dashboard reads. Combined-dashboard p95 was 215.88 ms (maximum 2,558.12 ms),
judging p95 was 18.48 ms, and superintendent p95 was 37.05 ms. Empty-queue
warmup added 240 successful reads, and the fresh finalization request took
31.40 seconds. Sampled database connections peaked at 58/100 with zero REST
pool timeouts.

## Completed verification

| Check | Result |
| --- | --- |
| Event reconciliation | All 16 checks passed: entries, exhibitors, placements, awards, points, payments, balances, check-in changes and coops. |
| Final report manifest | 11,695 intended artifacts; 11,694 generated, including two later ARBA reports. The contact-list PDF is the only missing file. The authenticated dashboard explicitly reports one failure. |
| Generated PDFs | All 11,694 files, totaling 14,530 pages and 6,300,965,557 bytes, passed Storage checksum/size checks and the applicable content checks. |
| Exhibitor coverage | All 5,056 exhibitor reports and 5,056 check-in sheets were present without duplicates. Every exhibitor report contained the expected animal identities. |
| Legs | Exactly 1,016 qualifying certificates across 921 exhibitors. Another 439 candidate files correctly contain no earned certificate and were excluded from email delivery. |
| Official reports | All 109 reports passed the corrected semantic audit, including financial totals and 104 breed-detail reports. |
| ARBA | Both five-page PDFs include every judge assigned to their section: 219 Open and 220 Youth. Rabbit totals are 34,741 Open and 12,567 Youth. |
| Simulated delivery | 5,056 exhibitor packages, 53 club packages and one combined ARBA package in 422.02 seconds. All 5,110 captured messages and 6,193 attachments matched recipients and hashes, without missing, duplicate or unlogged deliveries. |
| Database restoration | All 130 restored tables matched their source fingerprints. |
| File restoration | All 11,694 archived PDFs were individually restored and their hashes matched. |
| Visual review | Representative exhibitor, leg and paid-report pages, plus both ARBA first and last continuation pages, had no clipping or overlap. Visual review was sampled; semantic and byte checks covered every generated file. |

The first ARBA audit incorrectly expected all 220 judges in both sections.
The frozen fixture's class-allocation plan assigned Judge 201 only to Youth.
Reconstructing that plan independently and comparing all 47,308 saved active-entry
judge assignments found zero mismatches. The corrected audit checks the planned
roster for each section. The original failed expectation is preserved; no PDF
or result assignment was changed to make the audit pass.

## Additional local navigation limit

The first independent navigation attempt restarted services without restoring
the 20-connection REST pool. It recorded 79 request errors with the default
10-connection pool. A second attempt restored Auth/REST to 20 connections each
and still produced connection closures. Kong logged `512 worker_connections
are not enough` at the synchronized navigation barriers.

The local CLI uses a custom Nginx template with no explicit connection limit.
Its template also ignores Kong's normal environment injection for these
directives. The rehearsal helper now updates only that template's events block
and open-file limit, preserving routes and credentials, then verifies the
effective `nginx.conf`. It permits 2,048 gateway connections and 4,096 open
files with the same single gateway worker, 20/20 database pools and 100 database
connection limit. Standalone navigation now runs that preflight after restarts.
See [Kong's configuration reference](https://developer.konghq.com/gateway/configuration/)
for the supported connection and file-limit directives.

The original failures are retained in `event/navigation-with-indexes-summary.json`
(79 errors) and `navigation-capacity20/` (76 errors). After the gateway correction,
`navigation-gateway2048-final/` had no connection closures and QR navigation
passed, but manual navigation encountered three REST pool acquisition timeouts.
An intermediate environment-only setup attempt failed verification before opening
the workload. These are local test-environment changes, not a production gateway
deployment.

The final repeat, `navigation-app-retries/`, used the same three-attempt read
retry codes and jitter as the application's `transient_retry.dart`. It is a
Python protocol equivalent, not an execution of the Dart cursor loader or a
rendered browser. All 23,072 logical manual page reads, 482 QR page reads and
the complete 5,056-exhibitor roster passed. One raw `PGRST003` pool timeout was
logged and recovered; there were no exhausted retries or failed logical reads.
The final repeat took 142.40 seconds including staff setup. Manual page p95 was
2,888.64 ms and its slowest recovered page took 11,962.69 ms. Admin and
superintendent reads also all succeeded during that burst.

This proves bounded recovery under the tested burst, but full-list loading is
still slow at this scale. Manual navigation currently hydrates an entire show
section for each session. Reducing that work is a performance priority before
the next larger workload; a successful retry should not hide the pool pressure.

## Fixture and source preservation

The stopped rehearsal's database and Storage volumes were copied into the
isolated local project `ringmaster-show-full-e2e-c1-0912`. Source volumes were
mounted read-only and both copies passed a byte comparison. The clone passed
all 16 event reconciliation checks before its derived closeout state was
cleared. Fingerprints of 11 input tables were identical before and after that
reset. The new queue began empty and sweepstakes points were recalculated during
the new finalization.

The fixture contains 51,422 registered entries and 5,056 exhibitors in one Open
and one Youth show. After 4,114 scratches, 47,308 entries remain active. Online
payments total $257,110 and cash change payments total $89,990, with nothing due.

The timed source, migration set and newly compiled report worker were frozen and
hashed. Final verification found all 1,508 source files, 12 prepared inputs and
the worker executable unchanged. Later diagnostic harness/configuration changes
have separate manifests. The clone includes the dashboard planning fix in
migration `20260912145011_replan_closeout_dashboard_after_queue_growth.sql`.

The local gateway helper, restart preflight and section-specific judge expectation
were improved during this test. Seven focused Dart retry tests and four protocol
retry tests passed. The modified Python modules compile, and repeating the
capacity preflight left all three already-configured services unchanged.

Local services are stopped. The original fixture, cloned fixture, failed runs,
corrected audits, database backup and report archive are preserved.

## Work before the next larger rehearsal

1. Fix the contact-list PDF layout for 5,056 exhibitors, then verify complete
   contact coverage and rendering within the existing timeout. The worker
   recorded a permanent PDF render timeout; the report has not been repaired.
2. Reduce the work required to load full manual judging lists. The burst passed
   with the application's equivalent bounded retry policy, but it still took
   over two minutes and encountered a pool timeout. Preserve complete reads
   while reducing the data loaded per session.

## Workload and acceptance checks

- Warm the empty-queue dashboard with 20 authenticated admins across combined,
  Open and Youth scopes, then finalize both sections without restarting REST.
- Continue 20 admin and 30 superintendent sessions during finalization; add 220
  judging readers while reports generate. Admins continue alternating all three
  dashboard scopes. Judging has finished, so these sessions read results.
- Start four worker processes with four render slots each. Interrupt one owned
  worker and require surviving workers to recover its tasks through normal
  polling. Advance only the dead worker's leases locally; do not manually
  requeue tasks. This tests recovery behavior, not the natural lease wait.
- Require fresh finalization, checkout report generation and interruption
  recovery to finish within 7,200 seconds.
- Reconcile entries, placements, awards, points, payments, balances and coops;
  repeat 220-session QR and manual navigation peaks and the full exhibitor roster.
- Send every exhibitor, club and ARBA package through the actual local delivery
  functions to a synthetic receiver. Verify recipients, attachment hashes and
  duplicate suppression. ARBA generation follows the required delivery dates.
- Verify every generated PDF's Storage bytes, checksum and size; reconcile all
  exhibitor animal lists and qualifying legs, official report populations,
  financial totals and every judge actually assigned to each ARBA section.
- Restore a database backup into a separate database and compare table
  fingerprints. Restore and hash every archived report file.

## Scope limits

All services, identities and provider responses are synthetic/local. This run
does not certify hosted capacity, real payment or email providers, physical QR
scanning, browser rendering under concurrency, physical printing or real club
scoring schedules. The fixture uses an explicit flat 5/4/3/2/1 scoring schedule.

The two-hour measurement starts at this rehearsal's fresh closeout, not at the
historical judging timestamp copied with the fixture. Later email delivery,
ARBA generation and audits are measured separately from checkout generation.
The database recovery test excludes role/ownership restoration and a hosted
platform switchover; restored Storage bytes are verified on disk.

## Evidence

Run directory: `output/full_e2e/double-closeout-c1-20260912/`.

- `source-manifest.json`, `clone-provenance.json`, `selected-capacity.json`
- `run-outcome.json`, `runtime-adjustment-v2-manifest.json`
- `preflight-final/summary.json` and `preflight-final/reconciliation.json`
- `closeout_only.py`, `start_when_requested.py`, `phase-results.json`
- `event/closeout-summary.json`, `event/worker-recovery.json`
- `event/reconciliation.json`, `navigation-app-retries/navigation-with-indexes-summary.json`
- `event/pdf-audit-summary.json`, `event/official-report-content-audit.json`
- `event/final-report-manifest.json`, `event/final-dashboard.json`
- `event/judge-assignment-reconciliation.json`, `expected-judge-assignment-reconstruction.json`
- `event/delivery-audit.json`, `event/backup-restore-summary.json`
- `visual-qa/summary.json`, `capacity-idempotence.json`

Preparation logs retain two harness setup issues: the CLI shortened an
overlong project ID, and an initial preflight incorrectly treated reserved
Storage paths as generated files. Both were corrected before workload execution;
the clone had no generated files or Storage objects. These were setup failures,
not report or staff-load results.
