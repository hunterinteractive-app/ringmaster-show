# Full local workflow rehearsal — September 10, 2026

**Result: FAILED. The application is not yet cleared for the national.**

The subsequent fixes and targeted regression results are recorded in
[National rehearsal fixes](national-rehearsal-fixes-2026-09-10.md). This document
preserves the original failed run. Future rehearsals finish both Open and Youth
judging before finalization or report generation, per the clarified workflow.

The rehearsal exercised registration through payment, check-in, judging,
closeout, report delivery and data recovery. It found failures in both performance
and report correctness. Successful PDF generation and email delivery were not
enough: official reports could still contain incomplete information.

This was a fresh, isolated local show. Earlier test evidence and stopped local
volumes were retained. Production was not changed; no real payments or emails
were sent. Selected historical schema definitions were inspected read-only to
repair gaps in the local bootstrap. Production application code remained at
`52a490d` throughout this rehearsal.

## Population and concurrency

| Item | Tested |
| --- | ---: |
| Open | 18,867 entries / 1,855 exhibitors |
| Youth | 6,844 entries / 673 exhibitors |
| Total | 25,711 entries / 2,528 exhibitors |
| Registration | 12 concurrent purchasers |
| Check-in | 30 check-in + 10 admin + 15 superintendent = 55 sessions |
| Judging | 110 reporting clerks + 10 admin + 15 superintendent = 135 sessions |
| Result-entry methods | 55 QR / 55 manual, plus separate all-QR and all-manual navigation bursts |
| Closeout | 4 worker processes / 16 renders, with 135 continuing read/support sessions |

There was one Open and one Youth show, with the approved proportional exhibitor
split and no overlap. Check-in and judging were separate phases. Open closeout
ran while Youth results were entered. Ownership, class distribution where not
specified, placements, judges, winners and contact details were synthetic.

The sessions used real, separate local Auth identities and application APIs.
This was not a test of 135 rendered browsers, mobile radios or hosted Supabase
capacity. Navigation bursts requested data as quickly as possible; they were
not paced to human typing speed. The local PostgREST connection pool had 10 slots.

## Verified results

| Stage | Result |
| --- | --- |
| Registration and checkout | All 2,528 exhibitors and 25,711 paid entries created through Auth/Data API, checkout Edge Function and signed payment webhook |
| Payment reconciliation | $128,555 online + $150 cash = **$128,705**; zero balance due |
| Retry protection | First 16 checkout/webhook retries created no duplicate registrations or payments; first 30 check-in retries preserved record identity |
| Check-in | All 2,528 completed; 30 requested tattoo changes approved and paid at $5 each; complete roster read returned every exhibitor |
| Result entry | All 25,711 placements matched expected entry IDs, owners, animals, sections and changed tattoos; all 108 award assignments matched |
| Synthetic scoring | Every scored entry matched the explicit 5/4/3/2/1 schedule; Open 12,776 points / Youth 10,572 points |
| Rendering | **6,441 generated / 6 failed** out of 6,447 current report artifacts, including deferred ARBA reports |
| File integrity | All 6,441 generated PDFs downloaded, parsed and matched stored lengths and SHA-256 hashes; about 3.57 GB |
| Exhibitor PDFs | Every expected tattoo was present in all 2,528 exhibitor reports |
| Legs | Exactly **554 certificates** across 551 nonempty files; 610 empty leg files correctly excluded from email |
| Delivery transport | **2,582 captured messages / 3,295 attachments**: 2,528 exhibitor messages, 53 club messages and one two-report ARBA message |
| Delivery reconciliation | Every eligible artifact matched its captured recipient, filename and hash; no missing, duplicate, unexpected or unlogged deliveries; exact email retry sent no extra message |
| Data recovery | All **126 tables** matched after restore into an unexposed database; all **6,441 archived PDFs** restored to disk and matched their hashes |
| Regression checks | 90 assertions across 9 database test files passed; final local security error-level advisor check found no issues; Python harness syntax checks passed |

The scoring schedule was intentionally synthetic. These checks do not certify
the accuracy of real national/state club rules. Storage hashes prove byte
integrity, not that a report's contents are correct.

## Failures to address

1. **ARBA reports silently undercount animals and omit judges.** Both generated
   PDFs show **1,000 rabbits**, instead of 18,867 Open and 6,844 Youth. Both print
   **12 judges instead of 110**. `_countShownSpecies` uses the length of an
   unpaginated entry read; `_judgesSection` prints only six two-column rows.
   These incorrect files successfully rendered and reached the local receiver.
   Fix the count read and print every judge, then check the PDF contents again.
   Sources: `lib/screens/admin/closeout/data/loaders/arba_report_loader.dart:595`
   and `lib/screens/admin/closeout/pdf/builders/arba_report_pdf.dart:554`.

2. **Breed report species inference loses American rabbits.** The two American
   rabbit detail reports contain no animals. The other 102 breed detail reports
   omit the known American BIS winner from their show-awards summaries. The
   historical typed report contracts omit species, and the loader treats the
   shared breed name “American” as cavy; its entry hydration does not restore
   the explicit species. The content audit checked top-five class placings plus
   known BIS/RIS winners, matching this report's intended population. All 104
   breed detail reports failed that audit. Explicit species must survive the
   complete reporting path. Source:
   `lib/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart:14`.

3. **Peak manual navigation exhausts the local connection pool.** After restoring
   the historical indexes, the repeat produced eight manual navigation HTTP 504
   errors and two superintendent dashboard errors. QR navigation passed. Review
   manual loading of the entire show at every table, database query work and
   connection capacity before repeating the same 135-session burst.

4. **Four section financial reports fail with cash change fees.** Paid and unpaid
   exhibitor reports fail in both sections because whole-show payment records
   cannot be safely allocated to selected sections. The underlying ledger still
   reconciles exactly. Payments need reliable section allocation; ignoring the
   error or marking balances paid would not fix report correctness.

5. **Both judge PDFs exceed the rendering deadline.** The isolated PDF builders
   are terminated at the two-minute limit. The queue remains usable, but the
   required reports are missing. Improve the large report's rendering work and
   verify its full contents before changing operational timeout assumptions.

6. **Cross-section edits can fail a stable section's report read.** Two Open
   exhibitor reports exhausted snapshot retries while Youth results were being
   saved. The version check is show-wide. Both succeeded after explicit retry
   once writes stopped. Section closeout must remain reliable while other
   sections continue judging.

7. **Single-artifact breed-report regeneration fails.** The application retry RPC
   returned “No canonical artifact matched the requested finalize run and scope.”
   Its section-specific repair branch selects an ARBA artifact even for a breed
   report. Regenerating the report type for the section worked as a fallback.
   Source: `supabase/migrations/20260722003342_repair_legacy_arba_artifacts_before_requeue.sql`.

The worker interruption check killed one real worker with four active tasks.
The real recovery RPC processed four expired leases; those tasks subsequently
completed after explicit UI-style requeue. An exact completion replay succeeded
and a changed checksum was rejected. **Fully automatic recovery to completion
was not demonstrated.** Lease expiry was advanced only for the stopped worker,
so this did not measure the normal waiting interval.

## Representative timing

| Operation | p95 | Observed errors |
| --- | ---: | ---: |
| Checkout session, 12 purchasers | 133 ms | 0 |
| Signed paid webhook | 46 ms | 0 |
| Check-in save, 55 sessions | 49 ms | 0 |
| Cash change payment | 116 ms | 0 |
| Open QR/manual result saves, 135 sessions | 739 / 714 ms | 0 |
| Youth QR/manual result saves during Open closeout | 901 / 876 ms | 0 |
| All-QR navigation, repeated with indexes | 929 ms | 0 |
| All-manual navigation, repeated with indexes | 5,008 ms | 8 |
| Superintendent reads during that manual burst | 4,629 ms | 2 |
| Judge reads during closeout continuation | 78 ms | 0 |
| Admin / superintendent reads during continuation | 194 / 72 ms | 0 |
| Exhibitor email function, sequential bulk workflow | 278 ms | 0 |

The first registration smoke test contained one exhibitor; the remaining 2,527
completed in about 195 seconds. The complete delivery stage took about 604
seconds. Some local Edge requests took about **68 seconds**, despite much lower
p95 values; their cause was not established. Closeout required interrupted
segments and explicit retries, so this run does not establish a continuous
end-to-end completion-time target.

## Local fixture and test limitations

Historical functions, indexes, form columns, nullability and owner/manager
policies were missing or simplified in the original local bootstrap. Restoring
13 historical indexes resolved the first 55-second Open finalization timeout;
both sections then finalized under the unchanged deadline. Typed breed-report
contracts resolved 11 initial SQL errors. Those setup failures were preserved
and separated from the application failures above.

The incomplete breed abbreviation catalog produced **790 duplicate coop labels
within sections**, although every animal had a coop assignment. Restore the
reference catalog and verify label uniqueness before another fresh rehearsal.

The compiled browser build passed email OTP sign-in and synthetic manual
exhibitor creation after historical profile/form contracts were restored.
The recurring `claim-or-import-exhibitor` Edge Function is absent from the local
checkout, blocking a complete repeatable browser journey. Browser judging,
check-in and closeout interactions were therefore **not certified** by this run.

Stripe and Resend provider responses were emulated locally. Real external
payments, processor behavior, inbox delivery, QR camera scanning, interrupted
mobile connectivity and production sizing were not tested. The source URL
substitutions and hashes are recorded in the evidence.

The successful backup check restored application/Auth/Storage tables and the
private report-revision schema into a separate database. Platform-owned ACLs
could not be restored by the local database role and were explicitly excluded,
along with ownership, from the successful data check. PDF bytes were restored
and verified individually on disk; a fresh Storage API was not brought online.
This does not certify full platform restoration or hosted failover.
The file archive covers current generated report PDFs; obsolete Storage versions
are retained in the stopped local volumes and were not included in that archive.

## Evidence and next gate

Raw evidence is retained in `output/full_e2e/run-20260910-v6/`, including phase
summaries, events, failed tasks, explicit retries, captured delivery hashes,
reconciliation results, official-report content checks and backups. Its
`summary.json` is only the most recently executed stage; use the named phase
summaries and `final-assessment.json` for the overall result. The reusable local
harness and prerequisites are documented in `tool/full_e2e/README.md`.
The test workers, Edge serve process, HTTP server and local stack were stopped.
The local-only browser build was moved into the evidence directory so it cannot
be mistaken for the next deployable `build/web` output.

Fix the application failures, finish local catalog/browser parity, and then
repeat a fresh rehearsal with the same counts and staff peaks. Passing means
correct report contents and reliable recovery as well as successful saves,
rendering and delivery. A staging rehearsal with the actual deployment remains
necessary before committing to national capacity.
