# Convention closeout and 40-staff rehearsal — September 10, 2026

**Result: staff writes and data reconciliation passed; full closeout failed.**
The application needs further work before this scenario can be considered ready.
This run used commit `36e50a0`, synthetic local data, the full 215-migration
bootstrap, and the real compiled report worker. No production schema, data,
payments, deployments, or email deliveries were changed.

## Workload

- One Open A: 18,867 entries and 1,855 exhibitors.
- One Youth A: 6,844 entries and 673 exhibitors.
- Total: 25,711 entry records and 2,528 exhibitors, with no overlap.
- 40 signed-in API sessions: 16 check-in, 20 judging, four closeout/admin.
- Four worker processes, each allowing four simultaneous renders.
- Local Docker allocation: 10 CPUs and 8,214,851,584 bytes of memory.
- API row cap remained 1,000.

Judging staff filled 1,000 initially missing Youth placements using
`save_results_entry`. Check-in staff completed all exhibitors, recorded 64 cash
payments, and retried 16 committed check-ins after discarding their responses.
Judging staff similarly retried 20 saves. Administrators polled closeout and
check-in dashboards. Open was finalized while Youth judging was active; Youth
was finalized only after its pending results were complete.

These were concurrent application API operations, not 40 browser windows. Staff
used one-second think time; admin sessions used two-second think time after
responses. As staff finished their work, their sessions stopped writing while
the administrators and workers continued. Later read/layout diagnostics added
some local load after staff writes finished. This is a diagnostic rehearsal,
not a controlled production throughput benchmark.

## Successful checks

Every one of the 25,711 entry records matches the independently generated
expected section, exhibitor, breed, variety, class, tattoo, and placement. All
108 award rows match their expected identities. All 2,528 check-in records are
completed with exactly one record per exhibitor.

All 2,528 balances reconcile individually to a fixed 500-cent entry fee:

| Financial check | Expected and observed |
| --- | ---: |
| Synthetic charges | 12,855,500 cents |
| 64 cash payments | 325,500 cents |
| Remaining balance | 12,530,000 cents |

Both closeout manifests also match the complete expected artifact counts and
exhibitor owners. Open has 4,541 artifacts and Youth has 1,906, totaling 6,447:
2,528 exhibitor reports, 2,528 check-in sheets, 1,161 potential leg files, 104
sweepstakes reports, 104 breed-detail reports, and 22 other reports. Potential
leg artifacts include first-place owners who may not meet leg population rules;
1,161 is not a count of earned certificates.

Open finalization took **3.00 seconds** and Youth took **3.31 seconds**. Attempting
Youth finalization with 1,000 missing placements was rejected. After the saves,
Youth reported no missing placements, judges, duplicate placements, or invalid
final awards.

## Staff response times

These percentiles include failed requests where present and are measured at the
API client. They do not include Flutter UI rendering or staff think time.

| Operation | Requests | Failures | Median | 95th percentile | Slowest |
| --- | ---: | ---: | ---: | ---: | ---: |
| Check-in save | 2,528 | 0 | 35 ms | 1.44 s | 7.06 s |
| Judging save | 1,000 | 0 | 230 ms | 2.01 s | 5.20 s |
| Manual cash payment | 64 | 0 | 11 ms | 1.67 s | 3.64 s |
| Check-in dashboard | 41 | 0 | 19 ms | 158 ms | 591 ms |
| Closeout dashboard | 317 | **111** | 5.51 s | 8.32 s | 10.49 s |

All 16 check-in retries and 20 judging retries succeeded, and reconciliation
found no duplicate check-in records or award identities. Those retries modeled
a lost acknowledgement by discarding a successful response; they were not
actual network disconnects.

## Failures requiring work

### 1. Staff reads omit records

The check-in roster returned **500 of 2,528 exhibitors**. Its SQL implementation
has a hard `LIMIT 500` and the roster screen has no continuation parameter.
Searching can locate additional exhibitors, but the complete list is unavailable.

The mobile QR judging screen's section read returned **1,000 of 18,867 Open
entries**. It loads `report_results_entry_rows` once and then filters breeds in
memory. In this fixture the response covered only nine breeds; breeds outside
that response cannot be made complete by client-side filtering.

Relevant sources:

- `supabase/migrations/20260803185200_fix_checkin_roster_balance_lookup.sql:57`
- `lib/screens/admin/show_checkin_roster_screen.dart:48`
- `lib/screens/admin/judging/mobile/qr_results_entry_screen.dart:304`

Both paths need explicit complete reads or proper server pagination with a
visible continuation. The successful write workload used known fixture entry
IDs, so it does not establish that staff can navigate to every animal in the UI.

### 2. Details by Breed cannot paginate a large class

The real release worker stalled on `details_by_breed` for over five minutes,
used about 850 MiB resident memory in one observation, and did not yield its
heartbeat. Other tasks in that worker's claimed batch also remained unfinished.

An assertion-enabled render of the actual artifact raised
`TooManyPagesException`. A database-free control isolates the layout problem:

| Layout-only input | Outcome |
| --- | --- |
| One class, ten short rows | Rendered in 176 ms |
| One class, 100 short rows | `TooManyPagesException` in 261 ms |

The builder nests class tables inside columns within breed sections. The PDF
library's pagination guard is inside an assertion; release builds do not retain
that guard. Fix the spanning layout and provide an independently enforceable
render timeout. A timeout on the same blocked event loop cannot protect worker
heartbeats.

Relevant sources: `details_by_breed_report_pdf.dart:41`, `_breedSection`, and
`_classPlacements`; `lib/reporting_core/rendering/closeout_worker.dart:120`.

### 3. Closeout dashboard polling times out

**111 of 317 requests failed with PostgreSQL statement timeout (`57014`).**
The failing operation was `get_closeout_dashboard_scoped_for_species` with a
200-artifact page. Increasing client waits does not fix database statement
timeouts. Profile and simplify the scoped dashboard queries and their RLS work
against a faithful schema before retesting simultaneous polling.

### 4. Repeated section reads make exhibitor rendering expensive

The report repository loads an entire section for each individual exhibitor or
leg report. Sharing a snapshot inside one report fixed duplicate internal reads,
but thousands of separate reports still reload the same section.

| Completed report type | Files | Median data loading | Median PDF build |
| --- | ---: | ---: | ---: |
| Check-in sheet | 68 | 56 ms | 16 ms |
| Exhibitor report | 55 | **38.82 s** | 332 ms |
| Legs | 24 | **35.79 s** | 225 ms |
| Judge report | 2 | 25.67 s | 24 ms |

The planned ten-minute run was stopped, then workers were allowed to shut down;
the complete session lasted 678 seconds. Only **149 of 6,445 queued render tasks**
completed. Another two ARBA artifacts were intentionally deferred until report
delivery. After shutdown, 6,285 tasks were queued and 11 still held interrupted
leases. This is a failed full rendering attempt, not a successful closeout or an
estimate of production completion time.

A reusable snapshot tied to a finalized results version, or smaller queries that
return the individual exhibitor plus exact precomputed populations, needs testing.
Do not introduce an unversioned cache that can serve stale judging results.

### 5. Upload retry cannot reuse regenerated report bytes

The same unchanged check-in artifact rendered twice produced different SHA-256
hashes. Calling the worker's actual immutable upload method against its existing
object returned **409 Duplicate**. No object was overwritten.

`SupabaseRenderQueue.upload` accepts an existing immutable object only when its
bytes exactly match the rerender. The check-in builder includes
`DateTime.now().toLocal().toString()` in its footer, which changes on each render.
Thus a worker interrupted after upload but before completion cannot rely on
rerendering an identical file. Preserve the authoritative uploaded object and
its verified metadata during recovery, or make the whole artifact deterministic.

Relevant sources: `lib/reporting_core/rendering/render_queue.dart:117` and
`lib/screens/admin/closeout/pdf/builders/check_in_sheet_report_pdf.dart:101`.

## File integrity, recovery, and limits

All **149 generated objects** downloaded successfully, matched their stored sizes
and SHA-256 hashes, and contained PDF headers: 67,638,726 bytes in total. Eight
sample PDFs opened successfully. Sampled exhibitor reports and check-in sheets
contained every expected tattoo. Representative check-in, exhibitor, leg, and
judge pages were visually inspected. The synthetic fixture exposes imperfect
class/sex labels and an unknown judge in the judge report; those are not evidence
of production label correctness.

Exact completion replay by the same worker succeeded, while changing the checksum
was rejected. All five tasks from the initial killed worker and all 11 remaining
interrupted tasks from the corrected run were recovered without losing completed
tasks or creating duplicate artifact tasks. Lease expiry was advanced locally;
waiting out the real ten-minute lease interval was not tested.

The initial setup pass used the wrong check-in staff role and lacked a unique
award index. It is preserved separately and excluded from the successful write
counts above. Local fixture additions supplied the historical result-audit
columns, `shows.is_closed`, and the unique award identity required by the save RPC.

The full migration bootstrap is still a reconstruction. Its show scoring RPC is
a no-op, legacy scoring is simplified, and other historical fields such as
`shows.finalized_at` remain absent. Scoring, production-equivalent judge catalogs,
and result-version invalidation are not certified. The closeout RPC was called
directly after checking the initiating admin's permission; the Edge Function
transport was not exercised. Full delivery and final ARBA generation could not
be reached because rendering did not complete. No live email, registration
checkout, real network outage, or backup restoration was tested.

## Evidence and next rehearsal

The reproducible tools are in `tool/closeout_rehearsal/` and the PDF diagnostic is
`worker/closeout_renderer/bin/rehearsal_probe.dart`. Evidence remains under the
ignored `output/closeout_rehearsal/` directory:

- `run-20260910-054950/summary.json`, `events.json`, worker logs and metrics;
- `verification.json`, `artifact-manifest.json`, `object-verification.json`;
- `staff-read-checks.json`, `layout-10.log`, `layout-100.log`, `details-probe.log`;
- `upload-replay.log`, `preflight-recovery.json`, `recovery.json`;
- `pdf-samples/` for the inspected files and rendered previews.

The local security advisor reported no error-level findings. Python compilation
and Dart analysis of the new tools passed. Final graded verification exits 1
because full rendering is incomplete, while its other eight checks pass. The
local services are stopped, with their data retained in Docker volumes.

Fix the complete staff reads, PDF pagination/worker isolation, dashboard query
cost, repeated population reads, and immutable upload recovery. Then rerun the
same counts and 40-session workload to completion, followed by captured local
delivery and a faithful staging rehearsal with real scoring and role policies.
