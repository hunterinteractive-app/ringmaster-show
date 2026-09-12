# Event-sequence rehearsal — September 10, 2026

**Overall result: failed; the two-hour generation deadline passed.** All 6,368
queued checkout reports generated in **677.09 seconds (11 minutes 17 seconds)**,
including finalization and automatic recovery of four interrupted jobs.
Registration, printing, manual navigation and report/UI correctness failures
prevent this run from demonstrating national-show readiness. No production
deployment or production-data mutation was performed.

## Workload

The local event used the supplied 2024 convention breed totals: **25,711 rabbits
and 2,528 exhibitors**, in one Open section (18,867 rabbits, 1,855 exhibitors)
and one Youth section (6,844 rabbits, 673 exhibitors). Ownership, classes,
placements and winners were synthetic; the exhibitor split was proportional,
with no overlap between sections.

- Registration: 6,428 entries in days 1–14, 11,574 in days 15–29, and 7,709 on
  day 30. Thus 40% of the last two weeks' 75% arrives on the last day, about 30%
  of all entries. Calendar time was compressed. The assumed final-day burst
  was 250 simultaneous purchasers, not a concurrency figure supplied by the user.
- Check-in: two days, 30 sessions, 7,713 ear-number changes (30%), 1,286 sex
  corrections (5%), and 2,057 scratches (8%). These selections were disjoint.
  Test fees were $5 per ear/sex change and no scratch fee. All 2,528 exhibitors
  checked in; 23,654 active animals remained for judging.
- Judging: 110 sessions, 55 QR and 55 manual, with Open and Youth active on both
  days. Whole classes stayed with one clerk and finished on one day.
- Ten admins and 15 superintendents continued dashboard/API activity throughout.
  Check-in and judging did not overlap. Reports were finalized only after both
  sections finished judging and passed readiness.
- Checkout file-generation budget: **7,200 seconds (two hours)**, including
  finalization and an interrupted-worker recovery. Physical printing is separate.

## Results

| Phase | Result | Evidence |
| --- | --- | --- |
| Registration days 1–29 | Completed | Recorded daily cohorts and signed payment callbacks |
| Final-day registration burst | **Failed** | 633 of 758 purchasers failed: 627 Auth HTTP 500, five account-lookup HTTP 401, one checkout HTTP 401 |
| Controlled registration continuation | Passed; original failure retained | 632 preauthenticated purchasers at 250 concurrency plus one recovered existing cart; final population 25,711 paid entries |
| Pre-event check-in sheets | **Failed** | Both sections hit HTTP 414, URI too long |
| Coop-card diagnostic after check-in | **Failed content/layout** | All 23,654 active animals present across 5,914 pages, but no coop-number or entry-number boxes |
| Check-in days 1–2 | Passed | 11,056 requests/approvals, 2,528 check-ins and 2,502 cash payments; zero request errors |
| Overnight judges' sheets and comment cards | **Failed** | All four exports hit HTTP 414 |
| Simultaneous judging days 1–2 | Passed | 23,654 result saves plus 105 replayed saves; zero request errors, both sections ready |
| Finalization, generation and automatic recovery | Passed | 6,368 jobs completed; 677.09 seconds against a 7,200-second budget; 135 read sessions continued with zero errors |
| QR navigation and full roster | Passed | Both navigation trials returned complete QR populations; roster returned all 2,528 exhibitors |
| 110-table manual navigation | **Failed twice** | Three HTTP 504 pool timeouts during delivery/auditing; one timeout in an isolated repeat |
| Storage and exhibitor/leg content audit | Passed | 6,370 PDFs including two later ARBA reports; exact hashes/sizes, 2,528 exhibitor reports, all expected 653 leg certificates |
| Official report content | **Failed** | 110 of 112 reports passed; both ARBA rabbit totals include scratches |
| Report delivery | Passed locally | 2,582 captured messages / 3,321 attachments; exact recipients, artifact IDs and hashes; no duplicates or missing deliveries |
| Browser login and navigation | Partial | Real email-code login, show list, management and closeout navigation exercised; local fixture gaps recorded |
| Browser delivery-status screen | **Failed** | Unpaged artifact read stops at 1,000 rows; 740-exhibitor lookup produces a 33,409-byte URI and HTTP 414 |
| SQL regressions / source validation | Passed | 104 SQL assertions, relevant Dart analysis, Python compilation and Git whitespace checks |
| Backup restoration | Passed | All 127 tables matched in a separate unexposed database; all 6,370 archived PDFs restored with matching hashes |

The registration error was backed by local Auth and Postgres logs showing
SQLSTATE `53300`, exhausted ordinary connection slots, with `max_connections=100`.
The controlled continuation separates account/sign-in pressure from signed-in
purchasing. It does not certify the original burst or hosted capacity. Even in
that continuation, checkout's 95th percentile was **68.40 seconds**, with a
72.63-second maximum. Investigate Edge scheduling/timeouts and connection-pool
budgets before choosing hosted database sizing.

Check-in's compressed days took 36.40 and 43.16 seconds. Change approval's 95th
percentile was 255 ms; check-in save was 141 ms. The planned cash total was
**$44,995**, alongside **$128,555** in synthetic online entry payments.

Judging's compressed days took 23.29 and 22.69 seconds. There were 12,608 QR
saves and 11,046 manual saves. Their 95th percentiles were 523 ms and 513 ms,
respectively; the worst save was 1.88 seconds. These measure API operations,
not human judging pace, camera scanning or browser rendering.

The extra navigation trials load complete manual section lists at 110 tables,
with 25 support sessions. The first trial overlapped report delivery and file
auditing. The isolated trial ran after those activities stopped and still had
one failed request among 5,808 manual page reads. Its manual-read 95th percentile
was **3.50 seconds**, versus 3.17 seconds in the first trial. Successful saves do
not establish that opening/navigating the results interface is reliable.

The interrupted worker owned four tasks. A surviving worker completed them with
the same artifact generation and an incremented attempt count. Completion replay
succeeded and a changed checksum was rejected. Only the dead worker's leases
were advanced locally; this does not measure the normal ten-minute lease wait.
Report-generation timings were measured before delivery, browser compilation,
and the full file audit. The earlier coop-PDF audit overlapped the initial part
of generation and is part of the measured local workload.

The file audit verified **3,685,310,181 bytes** across 6,370 generated PDFs. All
2,528 exhibitor reports contain the independently expected active tattoos.
All 577 exhibitors expected to earn legs had their reports, totaling **653 leg
certificates**. Another 507 empty leg files were correctly excluded from email.
The semantic audit of official reports covered ARBA, breed results, judge,
paid-exhibitor and unpaid-balance reports. Other report types received file/hash
checks, not exhaustive independent checks of every printed value.

ARBA's printed rabbit totals were **18,867 Open / 6,844 Youth**, while the
independently expected active totals were **17,337 / 6,317**. The differences
exactly equal the 1,530 Open and 527 Youth scratches. Both reports did include
all 110 judge names. Financial reports reconciled their section populations and
online/cash totals; the underlying ledger reconciled **$173,550**, with zero due.

Delivery took 707.35 seconds locally and included 2,528 exhibitor recipients,
53 club packages and one ARBA package. One replayed email produced no additional
message. This certifies the synthetic receiver boundary, not internet email
deliverability. The later ARBA generation/delivery is separate from the timed
checkout generation stage.

## Fixes indicated by current evidence

1. **Bound account/sign-in connection pressure and handle transient failures.**
   Reproduce the 250-session burst with measured Auth/Postgres pool settings;
   verify retry behavior without duplicate exhibitors, carts or payments.
2. **Repair bulk reads in print generators and delivery status.** Check-in,
   control-sheet and remark-card reads build large UUID `in` filters that hit
   the local gateway's URI limit. Fix and retest every hydration path, not just
   the first request that fails. Paginate the control-sheet base RPC and the
   delivery-status artifact read. The latter actually returned only 1,000 of
   6,370 artifact records before its 740-ID exhibitor lookup hit HTTP 414.
3. **Repair coop-card layout and assert essential identifiers.** The saved PDF
   contains every active tattoo, but both identifier boxes are absent visually
   and both labels are absent from extracted text across the entire document.
   File existence and animal-set coverage alone are insufficient acceptance tests.
4. **Exclude scratches consistently from official shown-animal totals.** The
   scratch workflow retains `is_shown=true`, while the ARBA count filters only
   that flag and species. Reconcile both sections' PDFs after scratches and
   prove that entry edits cannot reintroduce them into shown totals.
5. **Make full manual-results navigation reliable under 110-table load.** The
   pool-acquisition failures reproduced without delivery or PDF auditing. Profile
   the enriched page RPC, limit unnecessary whole-section reads, and validate
   connection budgets and bounded retries against the intended hosted setup.
6. **Investigate long checkout and delivery stalls.** Signed-in checkout reached
   a 68.40-second 95th percentile, and a single local exhibitor email took
   68.40 seconds. These succeeded eventually but are poor recovery behavior
   for an arrival rush. Separate local Edge scheduling from query/provider time.
7. **Remove invalid role filters and stop hiding permission-query failures.**
   The show-list admin query includes `show_admin`, which is absent from the
   `app_role` enum in both the local and inspected hosted schema. The exact
   authenticated query returned HTTP 400 / `22P02`. An alternate show-list
   lookup still exposed this account's Manage button after local policies were
   restored, so this was not proven to block every admin workflow.

Relevant code: [check-in sheets](../lib/screens/admin/print_packs/check_in_generator_sheet.dart),
[judges' sheets](../lib/screens/admin/print_packs/control_sheets_generator_sheet.dart),
[comment cards](../lib/screens/admin/print_packs/remark_cards_generator_sheet.dart),
[delivery status](../lib/screens/admin/show_closeout_v2_preview.dart),
[coop-card layout](../lib/screens/admin/closeout/pdf/builders/coop_cards_report_pdf.dart),
[ARBA counts](../lib/screens/admin/closeout/data/loaders/arba_report_loader.dart),
and [show-list access](../lib/screens/show_list_screen.dart).

No application fixes for these newly observed failures were applied midway
through the rehearsal. The repair baseline remains distinguishable from this
fresh test's evidence.

## Fixture and harness corrections

The first coop attempt read zero assignments because the historical local
baseline lacked two production SELECT policies. Inspected schema metadata was
restored locally; no hosted data was copied or changed. This was a fixture gap,
not an application defect. The later coop run happened after check-in changes,
so it does not retroactively pass pre-event printing.

Browser checks additionally restored two self-read role policies, the historical
`user_can_manage_judges` helper, and `shows.timezone` / `shows.entry_open_at`.
They are now included in preparation for future local fixtures. The staff-PIN
read RPC remains absent from this local baseline, so PIN approvals are not
certified by this run. These fixture gaps are separate from application defects.

The representative browser followed actual email-code login via local Mailpit,
the show list, Manage, and Close Show/Reports V2. The delivery-status view failed
as described above. Its Generate Reports overview displayed **0 of 0** because
the current V2 page requests a combined Open/Youth scope, while this rehearsal
finalized two individual section scopes. Existing ARBA artifacts were visible.
The next fresh rehearsal must align its finalization call with the current V2
combined-scope path and verify the dashboard, rather than treating these API
timings as proof of browser-driven finalization. No additional combined-scope
finalization was submitted during this run.

Initial native-print probe issues were also preserved separately: a transitive
web-only import through `AppSession`, and an incorrect abstract-button finder.
The support-session data classes were moved verbatim into a small shared service
and re-exported from the original screen; this changes import dependencies, not
runtime behavior. Only the save-file dialog was replaced in the probe; real
widgets, authenticated reads, PDF builders, fonts and output bytes were used.

A first registration harness logging exception occurred after a completed day;
the recorded complete day was retained and subsequent days resumed. It was not
counted as an application registration failure. A reconciliation before
finalization correctly found no computed sweepstakes scores; that evidence was
retained under `before-finalization-*`, and full reconciliation is performed
after finalization. The expanded official-report auditor initially assumed all
report metadata had `section_id`; it was corrected to use each artifact's
single `section_ids` value. This harness exception was preserved separately.

The local stack's migrations were pinned to a complete filename/SHA-256 manifest.
The run began on source revision `73179c7` plus the previously reviewed fixes.
Another task committed `e523a2b` and migration
`20260910231422_prevent_distinct_exhibitor_auto_merges.sql` during the event.
That migration was **not** introduced into the running database; this report
does not validate it. The next fresh run must replay the intended final baseline.

## Evidence and limits

Raw evidence is retained, ignored by Git, in
`output/full_e2e/event-20260910/`; setup logs are in
`output/full_e2e/event-20260910-setup/`. The disposable local workspace is
`/tmp/ringmaster-show-full-e2e-event-20260910`. Individual phase summaries and
failure logs are authoritative; `summary.json` is only the latest stage.

This is a compressed event with real local Auth/API/RPC/worker/Storage execution,
not a month-long soak or a hosted capacity certificate. Stripe and email-provider
responses are synthetic local boundaries; no real charges or emails occur.
Historical schema contracts were restored selectively, so complete hosted-schema
parity is not claimed. The synthetic scoring schedule, catalog prefixes,
network conditions, physical printer capacity and device/browser concurrency
remain separate validation requirements.

The host had 24 GiB memory and 10 logical CPUs. Docker reported approximately
7.65 GiB memory and 10 CPUs; Postgres allowed 100 connections, with 128 MiB shared
buffers and 4 MiB work memory. These results apply to that local configuration.
They do not establish the database tier or pool sizes required in production.

Recovery verified data in `public`, `auth`, `storage` and
`report_generation_private`, including the report-revision records. The separate
restore database was never attached to live services. Roles, ownership, ACLs,
provider secrets, hosted failover and publishing restored Storage objects
through a fresh Storage API remain untested. The backup therefore demonstrates
data/file recoverability, not a complete production disaster-recovery procedure.

Before a larger run, complete the application repairs above, align the rehearsal
with the V2 combined-scope finalization flow, and finish the browser/PIN schema
fixtures. Then repeat the failed gates and a fresh event from zero entries.
Do not treat later successful phases or controlled registration recovery as a
replacement for the failures retained in this run.
