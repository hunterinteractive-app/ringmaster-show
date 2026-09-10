# Closeout rehearsal: five fixes

The five defects in the September 10 diagnostic have been addressed in the
local code and three new migrations. No production deployment or new full staff
rehearsal was performed. The original failed rehearsal remains preserved in
`closeout-staff-rehearsal-2026-09-10.md`.

| Defect | Change | Focused evidence |
| --- | --- | --- |
| Incomplete staff reads | Check-in uses stable exhibitor-ID cursor pages; QR results filter the breed inside SQL; manual result refreshes fetch their exact entry IDs in bounded batches. | All 2,528 roster exhibitors returned as 1,000 + 1,000 + 528 unique rows. All 18,867 Open entries and 1,615 Mini Rex entries returned. Tests cover lower API caps and exhibitors completing check-in while pages load. |
| Large-class PDFs and worker stalls | Breed, class, and special-award tables span directly across pages. PDF building runs in a disposable isolate with a hard two-minute deadline. The worker claims only jobs it can start immediately. | The previously failing 100-row class renders. A 1,000-row class produced 18 pages with every tattoo exactly once. The complete Open details PDF has 358 pages and all 18,867 unique tattoos. A CPU-spin regression verifies termination while the worker timer stays responsive. |
| Slow dashboard reads | Authorize at the dashboard boundary instead of rechecking every report/task row; active jobs stay in progress counts while review rows contain actionable failures. Species filtering occurs before pagination. Added artifact/task indexes. | One authenticated read of the saved Open run fell from 3,284 ms to 59 ms. Scope/permission and mixed-species pagination regressions passed. This is a single-query measurement, not a concurrency result. |
| Repeated section-wide exhibitor/leg reads | Bound result rows before report joins and share in-flight/completed snapshots across worker reports while their database revision remains unchanged. Keep at most four scopes; invalidate on relevant source changes and discard reads spanning an edit. | In the release-mode probe, the first exhibitor load took 1,799 ms; a repeated load took 183 ms and a leg load took 107 ms. Tests cover edits, scope isolation, failed loads, concurrent reads, and eviction. |
| Immutable upload retries | Store a receipt atomically with the file. Recovery verifies identity, generation, size, type, and checksum, then completes using the first uploaded file. | Actual local Storage accepted recovery and preserved the original checksum despite different rerendered bytes. Tests cover lost completion, wrong generation/scope, corrupt bytes, missing objects, and authorization failures. |

## Verification

- Flutter: **364 passed**, 26 opt-in integration tests skipped.
- Worker: **69 passed**, including new isolation, cache, and upload regressions.
- Database: **90 assertions passed in nine suites**; the exact three migrations
  replayed successfully and were recorded in local migration history.
- Production worker and focused probe compiled successfully as native release
  executables. The release probe rendered representative reports and verified
  actual local immutable Storage recovery without claiming queue tasks.
- PDF content was extracted with pypdf; representative pages were rendered and
  inspected for clipping and pagination.

Evidence is under `output/closeout_rehearsal/fixes-20260910/` (ignored generated
artifacts). The local database and earlier failed-run evidence are retained.

The broad database lint still reports 13 issues in unchanged historical/local
bootstrap functions, including missing legacy scoring/payment columns and
relations. None names the newly changed functions. These limit production-schema
parity and must be accounted for when preparing the next rehearsal; this work
does not certify national capacity or full scoring/payment correctness. Older
orphaned Storage objects without a verifiable receipt require a new generation.

## Next rehearsal profile

`tool/closeout_rehearsal/workload.json` records the user's revised limits:

- Check-in phase: **30 check-in + 10 admins + 15 superintendents = 55 sessions**.
- Judging/closeout phase: **110 judging tables + 10 admins + 15 superintendents
  = 135 sessions**, exercising both QR and manual entry.
- Check-in and judging do not overlap. Admins and superintendents span both.
- Payments are primarily synthetic online payments, with occasional small cash
  change fees. $5 is an adjustable test assumption, not a show policy.

The historical 40-session runner now requires an explicit replay flag. Prepare
the phased runner and updated payment fixture/reconciliation from the new
profile before running the next full closeout rehearsal. Apply the three migrations
before the matching application/worker build in any later environment.
