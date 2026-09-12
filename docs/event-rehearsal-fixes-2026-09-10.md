# Event rehearsal repairs — September 10–11, 2026

The seven reported issues and the additional local fixture gaps have been
repaired and verified with targeted local checks. This does **not** turn the
[original event rehearsal](event-sequence-rehearsal-2026-09-10.md) into a pass.
A new, complete event run is still required. These repairs were not deployed
to production, and hosted configuration was not changed.

## Repairs and verification

| Issue | Repair | Targeted result |
| --- | --- | --- |
| Registration exhausts database connections | Bound the disposable Auth pool to 20 connections; distinguish temporary Auth outages from invalid credentials; prevent overlapping login submissions and add bounded transient retries. | 250 new concurrent purchasers completed public signup, sign-in, account lookup, checkout and signed payment callbacks. Exactly 250 paid entries/carts/provider sessions; zero failed operations. Peak 62 database connections, including 20 Auth connections, against the local limit of 100. |
| Oversized print and delivery requests / incomplete reads | Paginate to exhaustion, including lower API row caps; hydrate IDs in batches of 100; page control-sheet source reads and complete delivery history. Propagate transport errors instead of silently dropping report fields. | All seven print packs generated. The loader regression covers 6,370 artifacts, 3,321 deliveries and 2,528 exhibitors with a forced 37-row API cap. The real browser loaded 284 delivery-history pages and found exhibitor 2,528 with the correct attachment. |
| Missing coop-card number boxes | Correct fixed-height layout budgets for the header, animal details, exhibitor identity and footer. | All 23,654 active animals have coop/entry number labels and scope footers. An extracted-text regression verifies every identifier on four long-name sample cards; representative cards were visually inspected. |
| ARBA counts include scratches | Count shown animals with a scalar database function that also excludes scratch timestamps and inactive statuses, preserving caller row permissions. | Generated ARBA PDFs contain **17,337 Open** and **6,317 Youth** rabbits, matching the independent active population; all 110 judges appear. |
| Manual navigation times out at 110 tables | Plan cursor reads with their actual filter values and use bounded primary-key hydration instead of repeatedly scanning the whole show. Preserve the access boundary in the newer cursor-restoration migration. | Final repeat: **5,878 manual pages and 224 QR pages**, with 110 clerks, 10 admins and 15 superintendents; **zero errors**. Manual page p95 **1.42 seconds**, maximum **4.19 seconds**. The full roster contains all 2,528 exhibitors. |
| Checkout/email stalls | Bound upstream requests; log operation timing without tokens or payloads; retry safe reads and provider requests with the same idempotency key. Retain checkout attempt identity after ambiguous provider failures. | Checkout p95 **4.89 seconds**, maximum **7.77 seconds**, during the 250-purchaser probe. A provider accepted an email and stalled for 16 seconds: timeout/retry completed in **16.12 seconds**, with exactly one accepted message. All 250 tested deliveries reconciled; the other 249 had p95 **298 ms**. |
| Invalid staff-role filter / hidden access errors | Remove the invalid `show_admin` enum value while retaining the separate `show_admins` table lookup; display failed staff-access lookups with a retry action. | Static analysis and a real browser check passed: show list, Manage, staff PIN panel and closeout navigation load successfully. |

The final navigation repeat overlapped the last comment-card render. These are
authenticated API sessions plus one real browser check, not 135 simultaneously
rendered browsers.

## Additional fixture and harness corrections

- Restore the inspected caller-specific staff PIN functions and delivery-history
  SELECT policy in the disposable fixture. Tests verify own-PIN reading,
  nonstaff denial, revoked old PINs, staff delivery access and unrelated-user
  exclusion. Only hosted schema definitions were read to restore these contracts.
- Finalize the same combined Open/Youth scope used by the V2 screen, after both
  sections pass readiness. The browser shows **6,361 queued reports**, instead
  of 0/0; two ARBA reports are separately deferred. Repeating finalization reuses
  the run and creates no additional tasks. This check leaves the new queue
  unrendered; it is not another complete closeout timing test.
- Wait for the current Edge process's readiness message before calling it. A
  previous runtime could briefly answer during restart and cause a false 502.
- Model signed webhook delivery retries with the same event ID, body and
  signature, retaining failed attempts. The first registration repair probe
  had one transient local `WorkerAlreadyRetired` webhook failure; its failed
  evidence remains. The subsequent complete 250-purchaser probe passed.
- Aggregate the local cart-level balance fixture by exhibitor before its print
  join. Visual review found duplicated check-in rows/comment cards for people
  who made separate cash payments. Production's inspected balance report already
  returns exhibitor-level rows. All four affected packs were regenerated, and
  the stronger final audit rejects duplicates as well as omissions. Earlier
  repair PDFs and the insufficient coverage-only audit remain in `prints/`;
  **`prints-final/repaired-content-audit.json` is the final print audit.**

## Regression checks

- 112 SQL assertions across 11 files passed, including active counts, cursor
  completeness, staff authorization, report revisions and payment hardening.
- 17 focused Flutter tests passed, including complete reads, transient retries,
  delivery hydration and opt-in PDF layout verification.
- All 70 closeout worker tests and all 22 shared Edge tests passed. A pre-existing
  mock-fetch typing incompatibility exposed by the broader Deno test run was
  corrected without changing the license-email implementation.
- A local Flutter web build, affected-file static analysis, Edge type checking,
  Python compilation and Git whitespace checks passed.
- Local advisors reported existing baseline policy/index/search-path warnings;
  none identified the repaired query/count functions or restored PIN contracts.

## Evidence and next run

Raw evidence is retained under
[`output/full_e2e/event-fixes-20260910`](../output/full_e2e/event-fixes-20260910/):
`registration-repeat/summary.json`, `navigation-final/summary.json`,
`prints-final/repaired-content-audit.json`, `arba/content-audit.json`,
`delivery/summary.json`, `browser-contracts-final/summary.json`,
`browser-verification.json`, and the final validation logs.
`repair-provenance.json` identifies the directly applied query patch and its
hash. The original event's frozen migration manifest and evidence are unchanged.

The final print audit checks exact occurrence counts for 23,654 active animals
in the combined coop pack, and 17,337 Open / 6,317 Youth entries in each respective
check-in, control and comment-card pack. Physical printer throughput was not
measured. Stripe and email provider responses were emulated locally; no real
payments or emails were sent by these probes.

Before the larger rehearsal, use a new local project/volume built from the
complete current migration set and matching application, Edge and worker code.
Repeat the full event sequence, including registration concentration, two
check-in days, overnight print generation, simultaneous judging, the two-hour
checkout deadline, delivery and recovery. The earlier **11-minute-17-second**
closeout timing belongs to the original run and was not remeasured here.

Hosted readiness additionally requires deploying the matching code/migrations
and reviewing the actual Auth/Data API/worker connection budget. The local Auth
container adjustment does not configure hosted Supabase. Connection sizing must
follow that environment's measurements; see
[Supabase connection management](https://supabase.com/docs/guides/database/connection-management).
