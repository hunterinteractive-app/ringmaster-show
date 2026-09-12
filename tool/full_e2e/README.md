# Full local workflow rehearsal

This harness exercises the actual Auth, Data API, RPCs, payment Edge Functions,
closeout workers, PDF builders, Storage and report-email Edge Functions. It uses
25,711 synthetic entries and 2,528 synthetic exhibitors, derived from the 2024
Open/Youth convention counts. It never operates on a linked or hosted project.

The `Local` guard requires a disposable `/tmp` workspace, the exact project ID
`ringmaster-show-full-e2e` (optionally followed by a unique lowercase suffix),
loopback API URLs, and byte-identical production
migrations. A long-running event may instead use a frozen
`rehearsal-migration-manifest.json` in its workspace: the guard verifies the
complete workspace migration set and SHA-256 hashes against that manifest.
Record its source revision and copy the manifest into the evidence directory;
do not silently add newer migrations midway through an event.
Production migrations and application code are not altered by this
harness. Existing test evidence is retained; there is no automatic destructive
reset. Stop older local stacks before starting this stack on the default ports.

## Workload and boundaries

- Open: 18,867 entries / 1,855 exhibitors; Youth: 6,844 / 673; no overlap.
- Registration: 12 concurrent synthetic purchasers, $5 per entry, absorbed fees.
- Check-in: 30 staff, 10 admins, 15 superintendents. Thirty approved tattoo
  corrections each incur a $5 cash payment. All exhibitors complete check-in.
- Judging: 110 clerks, 10 admins, 15 superintendents. QR/manual writes split 55/55.
  Separate all-QR and all-manual navigation bursts test complete cursor reads.
- Both Open and Youth must finish judging before either section is finalized. Four worker processes
  support 16 simultaneous renders. After judging, 135 sessions continue read
  activity until the report queue drains or its bounded deadline is reached.
- Stripe and Resend HTTP **provider responses** are emulated locally. Only their
  two URL literals change in temporary Edge copies; all auth, quote, webhook
  HMAC, finalization, file downloading and delivery-log code remains intact.
  `provider-boundary.json` records source hashes and those substitutions.
- The local receiver accepts only `@example.invalid` recipients and cannot send
  external messages. Real payment settlement, fees, deliverability and inboxes
  are outside this test.
- This is API concurrency, not 135 rendered browsers or proof of hosted capacity.
  Actual browser testing must be recorded separately.

## Preparation

From the application repository, with Docker and the Supabase CLI installed:

```sh
bash tool/local_supabase_e2e.sh /tmp/ringmaster-show-full-e2e-NEXT
```

In that new workspace's `supabase/config.toml`, set a **new unique project ID**
such as `ringmaster-show-full-e2e-next-20260911`. This gives the rehearsal new
Docker volumes; changing only the workdir does not create fresh volumes.
Do not link it. Start the local stack:

```sh
supabase start --workdir /tmp/ringmaster-show-full-e2e-NEXT \
  --exclude logflare,vector,supavisor,studio,postgres-meta,imgproxy
python3 tool/full_e2e/prepare.py /tmp/ringmaster-show-full-e2e-NEXT \
  output/full_e2e/NEXT
```

The original local baseline predates many historical contracts. `prepare.py`
restores selected inspected historical functions, columns, owner policies and
indexes from `supabase/local/e2e_historical_*.json`, then creates a **zero-entry,
zero-payment** show. Those JSON files contain only schema definitions inspected
read-only on September 10, 2026; no hosted data, credentials or identities.
They are not migrations or a complete production schema export.

`restore_catalog.py` installs the 44 inspected abbreviation records and five
explicit local prefixes for convention breeds whose fallbacks collided. These
five are synthetic fixture choices, not official national abbreviations. Coop
label uniqueness is checked before check-in. The restored account Edge Function
uses a loopback Club lookup provider that returns no match, exercising manual
account setup without calling the hosted Club database.

Compile the current real worker as described in `worker/closeout_renderer/README.md`
and place its executable at `output/full_e2e/closeout-renderer`.

## Running and preserving evidence

```sh
python3 tool/full_e2e/run.py /tmp/ringmaster-show-full-e2e-NEXT output/full_e2e/NEXT
```

Registration creates every exhibitor/animal/cart through an authenticated API;
entries and payments are created only by the signed payment callback. Retried
checkout and callback requests check duplicate prevention. `--registration-only`
and `--registration-limit 1` support a small contract smoke test first.

The runner stops after 20 failed tasks. Preserve `summary.json` under a phase
name before continuing. `--resume-after-checkin` is only for an interrupted
registration/check-in-to-judging run; it verifies existing Open placements.
It is not a generic reset or a replacement for a fresh rehearsal.

After an initial closeout failure, `continue_closeout.py WORKSPACE OUTPUT`
records failed tasks and retries only snapshot changes, expired leases and the
identified local breed-report contract error. It records single-artifact retry
errors before trying the same UI's report-type regeneration. Permanent report
errors remain. A drained queue does not convert the original run to a pass.

After rendering has stopped, use the following independent stages:

```sh
python3 tool/full_e2e/repeat_navigation.py WORKSPACE OUTPUT
python3 tool/full_e2e/reconcile.py WORKSPACE OUTPUT
python3 tool/full_e2e/deliver.py WORKSPACE OUTPUT
python3 tool/full_e2e/audit_files.py WORKSPACE OUTPUT
python3 tool/full_e2e/audit_official_reports.py OUTPUT
python3 tool/full_e2e/audit_deliveries.py WORKSPACE OUTPUT
python3 tool/full_e2e/backup_restore.py WORKSPACE OUTPUT
```

Both PDF audit scripts require `pypdf`. Use a Python environment with that dependency.
The executable paths supplied by the Codex workspace dependency runtime were
used for the September 10 run. Each stage saves a distinct summary; `summary.json`
alone is only the most recent stage. Full raw evidence stays in ignored `output/`.

`finish_arba.py WORKSPACE OUTPUT` supplies required synthetic ARBA contact details
through the administrative Data API after actual deliveries exist. Use it before
the file audits if the ARBA form was not completed earlier.

Delivery mirrors the sequential exhibitor bulk-send path and the four-at-a-time
club batch function. ARBA generation is attempted after delivery. Do not infer
delivery completeness from successful HTTP responses: compare receiver attachment
hashes, artifact IDs and database delivery records.

The PDF audit checks every generated file against its stored size/hash, compares
all exhibitor-report tattoos and leg certificate populations with independent
expected values, and writes a compressed report archive. The recovery stage
restores public/Auth/Storage tables into a separate database and compares table
contents, including the private report-revision schema; it restores each archived
PDF to disk and verifies its hash. Platform-owned ACLs and object ownership are
excluded from this data-recovery check. That database is never connected to live
services. Full hosted failover and permission restoration are untested.

`recovery.py WORKSPACE OUTPUT PID WORKER_ID` can interrupt one owned worker while
rendering. It records its claimed tasks, kills only the verified executable/PID,
advances only that worker's leases, then waits for a peer worker to recover and
complete the tasks automatically. The test does not call the recovery RPC or
manually requeue an interrupted task. It verifies the unchanged generation,
increased attempt count, completion replay and rejection of a changed checksum.
This accelerated lease test does not measure the normal ten-minute lease wait.

## Event sequence and arrival rush

`event.py WORKSPACE OUTPUT STAGE` runs each phase separately and preserves a
phase-specific summary. Use a fresh prepared workspace and output directory.
The ordered stages are `registration`, `preprint`, `checkin`, `judgeprint`,
`judging`, and `closeout`. Then run reconciliation, delivery, file/content
audits and backup restoration as above. A failed phase must remain failed even
if later phases are exercised to gather more evidence.

The September 10 event profile contains 25% of entries in days 1–14, 45% in
days 15–29 and 30% on day 30 (40% of the last two weeks' 75%). Daily purchaser
cohorts are indivisible, so entry percentages are rounded. It compresses the
calendar; it is not a 30-day soak. The assumed final-day peak is 250 concurrent
purchasers. The user specified the arrival distribution, not this concurrency.

Two check-in days use 30 sessions plus 10 admins and 15 superintendents.
Disjoint selections change 30% of tattoos, correct 5% of sexes and scratch 8%
of entries. Ear/sex changes cost an assumed $5 each, scratches are free, and
each exhibitor pays their combined changes once in cash. These fee amounts are
test inputs, not a statement of the event's actual fee policy. Two judging days
use 55 QR and 55 manual clerks, with both sections active on each day. A class
stays with one clerk and finishes within one day.

Only after both sections pass readiness does `closeout` finalize their combined
scope, matching the V2 browser screen, and start
the 7,200-second generation clock. One of four workers is intentionally killed;
the other three must recover its expired leases without a manual retry.
The timer includes finalization and automatic recovery, with 135 read sessions
continuing. ARBA reports are a separate post-delivery action; the checkout
generation measurement does not include physical printer time.

`preprint` and `judgeprint` run opt-in native Flutter tests of the real generator
widgets, authenticated reads and PDF builders. Only the file-save dialog is
redirected to a local path. They are not browser or physical printer tests.
`restore_print_reports.py` installs the inspected historical print projections,
two typed report RPCs, four read policies and the judge-management permission
helper that the old local baseline lacks. The separate local print view avoids
changing other fixture contracts.
The extra pure support-session model lets these widgets load without importing
the web-only superadmin UI through `AppSession`.

`audit_event_prints.py OUTPUT STAGE` checks animal coverage and coop/entry number
labels in the generated files. Render representative pages as well: a PDF can
contain the expected animals but omit essential fields visually. The optional
`coop-recheck` is explicitly a later diagnostic, not a replacement for a failed
pre-event print stage.

`registration-recovery` continues only after a recorded failed final-day burst.
It provisions missing accounts at bounded concurrency, recovers any unfinished
cart as its same owner, and exercises 250 signed-in purchases. Its success does
not change the result of the original account/sign-in burst.

## Targeted regression checks

The September 10 fixes were verified separately from the failed full rehearsal;
see `docs/national-rehearsal-fixes-2026-09-10.md`. On a retained local fixture:

```sh
python3 tool/full_e2e/verify_financial_fees.py WORKSPACE OUTPUT
python3 tool/full_e2e/verify_queue_contracts.py WORKSPACE OUTPUT
python3 tool/full_e2e/verify_account_setup.py WORKSPACE OUTPUT ORIGINAL_RUN_OUTPUT
python3 tool/full_e2e/verify_recovery.py WORKSPACE OUTPUT WORKER_EXECUTABLE
```

The fee and queue-contract probes roll back their database changes. Account
setup creates synthetic accounts, and recovery regenerates exactly one artifact;
retain their evidence. The Dart `bin/verify_national_reports.dart` utility in the
worker package renders the affected report types to disk using the local worker
environment. It requires a loopback URL and the synthetic test show. Then run:

```sh
python3 tool/full_e2e/audit_fixed_reports.py REPORT_OUTPUT ORIGINAL_RUN_OUTPUT
```

This verifies 112 affected PDFs against the independent fixture, including
animal counts, judge names, breed placings and financial totals. A successful
targeted audit does not replace a fresh registration-through-recovery run.

The event-sequence fixes have additional probes. Each accepts a retained local
workspace, a **new** evidence directory, and the original event directory:

```sh
python3 tool/full_e2e/verify_registration_rush.py WORKSPACE OUTPUT ORIGINAL_RUN_OUTPUT
python3 tool/full_e2e/verify_event_prints.py WORKSPACE OUTPUT ORIGINAL_RUN_OUTPUT
python3 tool/full_e2e/audit_event_prints.py OUTPUT repaired
python3 tool/full_e2e/verify_delivery_recovery.py WORKSPACE OUTPUT ORIGINAL_RUN_OUTPUT
python3 tool/full_e2e/verify_browser_contracts.py WORKSPACE OUTPUT ORIGINAL_RUN_OUTPUT
```

The registration probe creates a separate 250-purchaser show and exercises
public signup, sign-in, account lookup, checkout and signed payment callbacks.
It does not reuse preauthenticated purchasers. The delivery probe requires
generated exhibitor artifacts and verifies 250 sends, including acceptance
followed by a 16-second provider stall and an idempotent retry. Run it before
the browser-contract probe, which finalizes the combined scope and can queue
new report generations. That probe checks PIN isolation, staff delivery access,
and nonzero combined report totals; it does not render the queued reports.
The print audit rejects duplicate occurrences as well as missing animals.
For comment cards it checks the main card and the detachable runner separately:
each animal must appear once in each part. `audit_event_prints.py OUTPUT
remark-recheck` audits only the Open/Youth comment-card packs after a layout
change. Run the real generators first; the audit does not regenerate PDFs.

On a retained fixture, different finalization scopes can each have current
artifacts. To audit or deliver only one run, pass
`--finalize-run-id=UUID` to `audit_files.py`, `verify_delivery_recovery.py`, or
the worker's `verify_national_reports.dart`. Use the actual `finalize_run_id`
returned by finalization. Do not combine old separate-section artifacts with
the new combined scope when measuring completeness or delivery.
After a combined-scope file audit, run
`audit_official_reports.py OUTPUT --combined`; add `--checkout-only` when the
two ARBA reports are still deferred and are being tested separately. This
checks one combined judge/paid/unpaid report and 104 section/breed reports.

`Rehearsal.start()` bounds this disposable stack's Auth pool to 20 connections
(five idle) with `configure_capacity.py`. CLI 2.95.4 does not expose the GoTrue
pool setting in `config.toml`; the helper preserves the inspected container
configuration and replaces only local Auth, with rollback on startup failure.
It never changes hosted settings. Reapply it after the CLI recreates Auth.
Each run records its connection budget and waits for its own Edge process's
readiness message before sending requests. Signed webhook retries retain the
same event ID, body and signature and log every failed attempt.

For targeted repairs on a frozen event, retain the original migration manifest
and record separately every directly applied patch and its hash. This is a
patched-fixture test. A fresh event must bootstrap the complete current migration
set into a new project/volume; never label a repaired old event as a fresh pass.
See `docs/event-rehearsal-fixes-2026-09-10.md` for the results and remaining
deployment/rehearsal boundaries.

## Cleanup

Stop only processes started for this rehearsal. Stop this local Supabase project
without `--no-backup` so its named volumes and failed-run evidence remain. Never
run a production reset or delete unrelated projects/volumes. Commit only the
harness, local contracts and written results, not credentials, dumps or PDFs.
