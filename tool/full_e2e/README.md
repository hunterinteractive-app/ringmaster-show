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

For a doubled rehearsal, pass `--scale 2 --staff-scale 2` to `prepare.py`.
This prepares 51,422 expected entries and 5,056 expected exhibitors, with
37,734/3,710 Open and 13,688/1,346 Youth. Every historical breed/class count
is doubled. Registration peaks at 500 purchasers; check-in uses 60 clerks,
20 admins and 30 superintendents; judging uses 220 tables split evenly
between QR/manual, plus the same 50 supporting staff. The local Auth pool,
four render workers and two-hour checkout deadline stay unchanged.
`--staff-scale` defaults to `--scale`; omitting both retains historical sizes.

The extreme profile uses `--scale 4 --staff-scale 4`: 102,844 entries and
10,112 exhibitors, 1,000 purchasers, 440 judging tables, 120 check-in sessions,
40 admins and 60 superintendents. Percentages, server resources and the
7,200-second checkout deadline stay the same. PDF audits accept the six-digit
synthetic animal identifiers while still requiring exact expected populations.

Preparation creates configuration, judges and expected files only: the show
still has zero exhibitors, entries and payments. It does not run `event.py`.
Offline harness validation is `python3 tool/full_e2e/test_workload.py`.
Preserve the prepared source, migration hashes and expected files before
waiting to start; start the workload only when requested.

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
contents, including the private report-revision and judging helper schemas and function definitions; it restores each archived
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
each exhibitor pays their changes in cash. New profiles defer one already
planned charged change for up to one returning exhibitor per check-in clerk
from day one to day two. These exhibitors pay again after their earlier
balance was paid. This preserves the original change percentages and total
fees while exercising the later-fee fix; reconciliation includes the extra
payment/cart and verifies earlier payment records remain unchanged.
These fee amounts are
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

## Interrupted registration and 500-purchaser diagnosis

`recover_incomplete_registration.py WORKSPACE ORIGINAL_EVENT NEW_OUTPUT
--dart-client COMPILED_CLIENT` recovers the seven failures from the first doubled
event using the original local Auth accounts and carts. Compile
`registration_client.dart` with the app's Dart package first. It exercises the
actual app write helper, a lost response after a committed insert, write replay
and cross-owner denial. Credentials travel over stdin and are never logged.
Use this dedicated recovery driver for that fixture; the older event recovery
stage predates partial account/animal/cart recovery.

`verify_500_purchase_burst.py WORKSPACE ORIGINAL_EVENT NEW_OUTPUT --rest-pool 20`
adds 500 new diagnostic purchasers to the retained populated show, alongside
20 admins and 30 superintendents. It uses the final-day Open/Youth cohort and
approximately ten entries per purchaser. Save-response validation and bounded
retry rules match the Dart helper; signup and login have no client semaphore.
Pool gauges, connection counts, API events and query-statistic snapshots are
recorded. Each invocation requires a new output directory.

These diagnostics deliberately change the retained local fixture. Preserve the
original failed evidence and start the next full event in a new workspace and
Docker project. Do not continue that fixture as if it were a fresh event. The
September 12 repair and retest report is in
`docs/registration-recovery-and-500-purchaser-retest-2026-09-12.md`.

`verify_coop_assignment.py WORKSPACE EVENT NEW_OUTPUT` compares the coop lookup
optimization against the restored historical function across the populated
event. It checks separate/combined numbering, blank and manual labels, retries,
NULL/true overwrite flags and authorization, then rolls back both data and
function changes. Candidate operations retain the eight-second timeout. Run it
on the stopped preprint fixture before applying the optimization. Full fixture
preparation reapplies migration `20260912125700` after historical restoration.

## Dashboard queue-growth regression

`verify_dashboard_queue_growth.py` reproduces the empty-to-11,693-task dashboard
transition on the retained doubled fixture. It warms all 20 REST backends before
copying the queue into private diagnostic tables, with 20 admins and 30
superintendents reading concurrently. Only these copies disable autoanalyze;
there is no service restart or manual statistics refresh during the transition.
The original baseline must time out and the fixed version must complete every
request with identical dashboard contents. Access checks, migration idempotency,
function permissions and hashes of the original event rows are also verified.

```sh
python3 tool/full_e2e/verify_dashboard_queue_growth.py \
  /tmp/ringmaster-show-full-e2e-double-r6-20260912 \
  output/full_e2e/dashboard-fix-20260912/regression/.staff.json \
  output/full_e2e/dashboard-fix-20260912/REPEAT \
  --baseline-functions output/full_e2e/dashboard-fix-20260912/regression/before-functions.json
```

Use a new evidence directory and the latest saved staff credentials on each
repeat. Omit `--baseline-functions` only when testing an unpatched local fixture.
This probe applies the candidate migration to the selected guarded local
database, removes its private diagnostic schemas/RPCs, and preserves the original
entries, payments and queue. It does not render reports or turn the original
failed full event into a pass.

## Local gateway capacity after restarts

Run `configure_capacity.py WORKSPACE --rest-pool 20` after every CLI stack
recreation and before a load burst. `Rehearsal.start()` and standalone
`repeat_navigation.py` do this automatically. This restores the bounded
Auth/REST pools and sets the local gateway's single worker to 4,096 connections
with an 8,192 open-file limit. The helper verifies the effective Nginx settings;
it does not change database connection limits or gateway worker count.

The pinned local Kong image exhausted its default 512 connection slots during
the doubled 270-session navigation barrier. Those slots cover both clients and
upstream connections. Gateway limits are separate from the database pool
budget. Preserve the failed burst evidence and use a fresh output directory
when retesting a changed capacity configuration.

The fresh R8 sustained final-day run later exhausted 2,048 slots with 500
purchasers despite a successful single-burst test. The 4,096-slot gateway
budget is held constant for the next 51k and 102k comparisons. Auth/REST pools
remain 20 each and report-worker resources remain unchanged. Explicit REST
pool selections are saved to `rehearsal-capacity.json` and survive startup.

Event judging writes `expected-judges-by-section.json` from the planned class
assignments before results are saved. The official ARBA audit requires this
plan when auditing an event profile: working both days does not imply a judge
served both Open and Youth. For an older preserved event, reconstruct the plan
from its frozen source and expected entry inputs, then verify it against saved
assignments; do not derive an expected roster from the PDF being audited.
# Focused contact and judging retests

Manual navigation follows the app's breed index and selected-breed cursor
reads, with 250 rows per manual page. `repeat_navigation.py` also accepts
`--largest-breed` after its workspace and output arguments to concentrate
clerks on the largest Open and Youth breeds. Preserve each run in a fresh
output directory with copies of the fixture manifest and expected entries.

`verify_judging_scopes.py WORKSPACE OUTPUT` reconciles every breed and both
full sections with saved entry identities, awards, species, and scratches.
It compares staff readiness with the canonical validator and checks access
denials. `verify_contact_report.py WORKSPACE OUTPUT WORKER ARTIFACT_ID`
regenerates only the selected synthetic contact artifact and checks the
stored file hash plus unchanged entry/exhibitor/award/coop fingerprints.
Use `--allow-generated` only when deliberately testing another generation
of an already-generated contact report. Contact content and visual audits
must follow the generation/hash check.

See `docs/contact-and-judging-fixes-2026-09-12.md` for the measured 51,422-entry
results and local Storage-policy limitations.
