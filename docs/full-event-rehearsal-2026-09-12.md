**Fresh full-event rehearsal — September 12, 2026**

The existing readiness fixes were deployed, and a new synthetic event completed registration, printing, check-in, simultaneous Open/Youth judging, closeout, delivery, and backup restoration. Checkout generation took **12 minutes 22 seconds**, within the two-hour target. All planned event reconciliations passed after correcting two test-harness problems. Additional checks found unresolved fee-access and subsequent-fee billing problems, plus a local database crash during a diagnostic. This is **completed with findings**, not national-readiness certification.

The run used 25,711 entries and 2,528 exhibitors: Open 18,867/1,855 and Youth 6,844/673, without exhibitor overlap. Breed counts came from the supplied convention counts. Ownership, individual animals, placements, awards, and class distributions were synthetic. Each animal entered one section.

The registration month was compressed into 30 chronological batches: 25% in the first 14 days, 45% in days 15–29, and 30% on the final day. The final day included 7,709 entries from 758 exhibitors. The harness assumed 250 concurrent purchasers; that concurrency is an assumption rather than a measured historical peak. New exhibitors used public signup and password sign-in. Check-in and judging each ran two separate day batches.

All workload traffic went to the fresh local Supabase project `ringmaster-show-full-e2e-r2-0912`. Payment-provider and report-email responses were simulated locally. No synthetic production entries, real charges, or external report emails were created.

**Deployment and verification**

The deployed application source is `5db1dc275d2ff24f6aa28507e9a776eca1cc67fd` on main. The release included the national-read completeness, staff-query, report-scope, fee-attribution, recovery, and ARBA continuation-page changes already in the repository.

| Component | Deployed result |
| --- | --- |
| Web | [Successful CI run 34671967215](https://github.com/hunterinteractive-app/ringmaster-show/actions/runs/34671967215); [release site](https://64748673.ringmaster-show.pages.dev) |
| Database | Atomic migration `20260912035946`, `national_event_readiness_release_20260912`, covering seven outstanding migrations |
| Edge Functions | 16 affected functions deployed and verified active; JWT settings retained |
| Report worker | Cloud Run revision `ringmaster-closeout-renderer-00043-2gx`, 100% traffic; authenticated health returned the release SHA |

The first database migration attempt rolled back because production uses an enum for breed species and an enum-to-text index expression was not immutable. The index was corrected to use native species values, then the atomic release succeeded. Existing production credentials, provider configuration, worker capacity, and access settings were preserved. Local fixture migrations were not deployed.

Release checks passed: Flutter analysis, 32 application tests, 74 worker tests, 22 shared Deno tests, and 112 pgTAP assertions across 11 files. ARBA unit coverage includes 0, 12, 13, and 110 judges. Production migration history uses different names for some earlier schema changes, so a blind migration push was not used.

**Event results**

| Stage | Observed result |
| --- | --- |
| Registration | 2,528 completed registrations and simulated online payments; all 25,711 entries paid; about 5m 52s total compressed workload |
| Coop cards and check-in sheets | 8,956 pages generated in 98.6s; every entry present exactly once in the expected pack |
| Two-day check-in | 30 clerks, 10 admins, 15 superintendents per day; 7,713 ear changes, 1,286 sex changes, 2,057 scratches; no failed operations |
| Check-in fees | 2,502 simulated cash payments totaling $44,995; $5 per charged change, scratches free |
| Overnight judging packs | 14,245 pages generated in 135.9s; 23,654 active animals complete in control sheets and each expected main/runner card |
| Two-day judging | 110 tables split 55 QR/55 manual, plus 10 admins and 15 superintendents; both sections active together; all results and 105 save replays passed |
| Finalization | Started after both sections were ready; fresh combined run, generation 1, 6,361 checkout tasks |
| Checkout reports | 6,361 generated, none failed; 741.6s including finalization and worker recovery, against 7,200s budget |
| Continued staff use | 135 staff readers during closeout; 35,212 reads without errors |
| Navigation | 5,878 manual pages and 224 QR pages checked; complete 2,528-exhibitor roster; no errors |
| Delivery | 2,528 exhibitor targets, 53 club messages, one ARBA message; 398.3s total stage; local replay produced no duplicate email |
| PDF verification | 6,363 final files, 3,683,858,813 bytes; every file/hash checked; no content mismatches |
| Official reports | All 109 audited reports passed, including breed, judge, paid/unpaid, and ARBA reports |
| Legs | All 653 expected certificates found; 507 empty leg files correctly excluded from delivery |
| Delivery verification | 2,582 captured messages containing 3,321 expected attachments; exact recipient/name/hash reconciliation; no omissions or duplicate deliveries |
| Backup restoration | All 130 tables matched restored row counts and content hashes; all 6,363 archived PDFs restored and verified |

The seven pre-event printing packs contain 23,201 pages in total. These timings measure file generation, not physical printer throughput.

Online payments reconciled to **$128,555**, cash payments to **$44,995**, and the complete ledger to **$173,550**, with no unpaid amount for the planned event. Entry identities, sections, changes, scratches, coops, placements, awards, and points matched the expected fixture. The event collected each exhibitor's change fees together before their cash payment; it did not include another charged change after that payment.

Both ARBA reports have three pages: the main form with 12 judges, followed by two continuation pages containing the remaining 98. Each report includes all 110 judges. Rabbit totals are 17,337 Open and 6,317 Youth, excluding scratches. Rendered inspection confirmed the main form and continuation pages are readable, with no missing footer or clipped form sections. Samples of coop cards, check-in sheets, control/remark cards, financial reports, and legs were also visually inspected.

**Recovery and performance**

One report worker was stopped while it owned four tasks. A surviving worker automatically reclaimed and completed all four at attempt 2, keeping generation 1. No manual requeue or recovery RPC was used. The test advanced only the stopped worker's lease expiry, so it verifies recovery behavior rather than the normal ten-minute lease wait. Completion replay passed; a changed checksum was rejected. The overall checkout deadline includes this recovery.

Manual judging saves had p95 436ms; QR saves 427ms. During closeout, staff-read p95 ranged from 31ms to 53ms. Registration had longer tails: account lookup reached **70.22s**, checkout **31.41s**, and checkout p95 was **3.27s**. Local Edge worker CPU-limit recycling appeared around these delays. One transient checkout HTTP 500 recovered through the application's existing retry policy; it remains visible in the evidence. Local timing does not establish the cause or magnitude of hosted delays.

Resource sampling observed up to 49 database connections and 20 Auth connections, including the later diagnostic period. This is not a production sizing recommendation. Clock continuity checks passed during the measured event; a temporary wake assertion prevented host sleep.

The backup restored public, Auth, Storage metadata, and private report-generation data into a separate local database. It did not restore role/ACL ownership or perform a hosted-service switchover. PDF bytes were independently restored to disk and checked, without publishing a replacement Storage service.

**Unresolved findings before a larger rehearsal**

1. **Another charged change after cash payment can leave the balance unchanged.** A rolled-back follow-up approved a $7.50 fee for an exhibitor whose earlier $30 fee balance was paid. The charge row existed, but the balance remained $30 paid/$0 due, and another cash-payment call reported no balance due. This reproduced on the unchanged release without the proposed permissions patch. The paid-balance protection trigger and reuse of an active fee cart need a coordinated fix that preserves prior payment records. The next test should collect a fee, approve another fee on a later check-in day, and then collect the new amount.

2. **Existing fee bookkeeping access is too broad.** Read-only production checks found RLS disabled on `show_checkin_fee_carts` and `show_checkin_fee_charges`, with direct anonymous/authenticated table privileges. The internal `add_checkin_fee_charge` helper also retains explicit client-role execution privileges despite lacking its own caller authorization. These are pre-existing access settings. A proposed restriction was prepared, but it remains a draft outside the automatic migration directory and **has not been deployed**.

3. **The draft permissions diagnostic crashed local PostgreSQL.** At 05:10:05 UTC, the backend received signal 11 while testing a denied direct helper call inside a PL/pgSQL exception block. PostgreSQL recovered automatically. The diagnostic had reached the negative-access portion after the initial authorized fee/payment assertions, but the entire transaction rolled back. This is not a passing patch validation, and no equivalent write test was run in production. Isolate the database/extension failure before relying on or deploying this draft. Post-recovery checks confirmed 25,711 entries, 2,528 exhibitors, $44,995 cash, 6,363 generated artifacts, no failed tasks, no diagnostic fee request, and no persisted RLS changes.

4. **Registration tail latency needs a targeted capacity check.** All final user operations completed, but 31–70 second outliers are too long to dismiss before a larger entry rush. Investigate local Edge recycling, then run a separately authorized hosted staging check with realistic provider configuration.

**Evidence integrity and limits**

The first fresh attempt is preserved separately as a failed registration run. Its harness sent each checkout only once and saw eight transient failures before day 30. The corrected fresh run uses the deployed client's three-attempt policy for HTTP 500/502/503/504, with the same cart and token on retry, and records every failed attempt. It also exercises public signup rather than admin-created exhibitor accounts. The retry helper was checked for transient recovery, retry exhaustion, no retry for 400/429, and unchanged request identity.

The original official-report audit is also retained: it falsely missed the first-page ARBA totals and 12 names because text extraction joined adjacent words after form scaling. The corrected audit allows optional spaces and still requires exact totals and the complete judge-ID set. The PDFs were not regenerated or changed to make that audit pass. The initial orchestrator's nonzero audit exit remains in its original log; the corrected audit and subsequent delivery/restore results are recorded separately.

The frozen application and worker source stayed at release `5db1dc2`; only the registration harness overlay and later audit correction differed. The local worker binary SHA-256 is `63a41b72cbeb27ffcb08036a0d59c0b45fde15eeb65ccb314a49bfa74363ab60`. No draft fee code was included in the measured event or production deployment.

This rehearsal exercises local API concurrency, not 135 rendered browsers, an actual month of uptime, real payment settlement, real email-provider acceptance, or physical printers. A supplemental real-browser check reached the local OTP screen, but the tab became unavailable before authenticated workflow completion; that UI check is incomplete. Historical local schema contracts were restored selectively, so full production schema parity is not claimed.

Evidence lives under `output/full_e2e/fresh-event-20260912-v2/`, with event outputs under `event/`, draft fee work under `drafts/`, and final assessment in `run-outcome.json`. The original failed attempt and deployment evidence are under `output/full_e2e/fresh-event-20260912/`. The synthetic backup, isolated restored database, and prior evidence are retained. Temporary test services are stopped after the run.
