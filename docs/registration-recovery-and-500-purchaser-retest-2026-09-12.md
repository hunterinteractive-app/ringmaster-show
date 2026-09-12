# Registration repair and 500-purchaser retest

All seven interrupted registrations recovered, and the final 500-purchaser test
passed. A separate fresh 51,422-entry event then started from an empty database.
The first full event remains recorded as failed.

## Fixes

Checkout now preserves transient database errors such as `PGRST003` and returns
a retryable 503 instead of a validation-style 400. Account lookup and registration
saves use at most three attempts with backoff and jitter. New records retain their
IDs after uncertain responses. A retry reads those IDs under the original owner's
RLS, verifies submitted fields and inserts missing records without overwriting a
collision. Definite validation rejections still allow correcting the form.

The local database retains its 100-connection maximum. Auth and REST each have a
20-connection budget, reserving 25 for other services and 35 spare. Internal REST
metrics record waiting requests and pool timeouts. No production changes were made.

Validation passed: 12 focused Dart tests, 7 Edge tests, 4 workload tests, Flutter
analysis and checkout Edge type checking. The recovery exercised the application's
actual compiled Dart helper against local APIs, including a deliberately lost
response after a real commit, replayed writes and denied cross-owner access.

## Recovery and burst evidence

The original seven accounts and both existing carts were reused. The missing 71
entries reconciled to 51,422 paid entries, 5,056 purchasers and $257,110 in simulated
payments, with zero balances due. Every entry field matched. Payments were unique
per cart and session, and hashes confirmed that previously completed entry and
payment rows were unchanged. Original failure evidence remains preserved.

Each burst used 500 new signups/logins, the final-day Open/Youth mix, 5,061 entries,
real local account/cart/checkout APIs, signed simulated payments and 50 support
staff on the populated show. The retained fixture received these diagnostic
cohorts; the fresh full event uses a separate database.

| Trial | REST pool | Purchases completed | Workload time | Peak DB connections | Pool timeouts |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline diagnostic | 10 | 500 / 500 | 20.38 s | 47 | 0 |
| Capacity comparison | 20 | 500 / 500 | 18.89 s | 57 | 0 |
| Final app save-response protocol | 20 | 500 / 500 | 20.38 s | 57 | 0 |

The baseline completed all requests and integrity assertions, then failed in its
final success log because `elapsed_s` was supplied twice. That harness bug was
fixed; its failed summary was retained. Both later trials exited successfully.
The final trial also requests and validates inserted rows as the Dart client does.

The final trial had zero failed actions, 500 provider sessions, exactly 5,061 paid
entries and $25,305 in simulated payments. All 176 admin and 265 superintendent
requests succeeded. Peak queued REST requests were 514. These sequential local
measurements support testing the bounded 20-connection pool in the full event;
they do not establish an optimal production setting or unlimited spare capacity.
See the [PostgREST connection pool documentation](https://docs.postgrest.org/en/stable/references/connection_pool.html)
for the distinction between acquisition waits and query execution time.

Evidence lives in `output/full_e2e/registration-repairs-20260912/`: the readiness
gate, recovery summary, final burst summary, request events, connection samples
and before/after query statistics. The original failed full-event evidence lives
in `output/full_e2e/double-event-20260912/`.

## Fresh full-event run

Project: `ringmaster-show-full-e2e-double-r2-0912`; workspace:
`/tmp/ringmaster-show-full-e2e-double-r2-20260912`. Frozen source, input and worker
hashes, all 229 local migrations, and phase results are under
`output/full_e2e/double-event-r2-20260912/`. The preflight verified zero entries,
payments and queued reports.

The profile remains 5,056 exhibitors; 37,734 Open and 13,688 Youth entries; 500
purchasers; 60 check-in clerks; 220 judging sessions; 20 admins; 30 superintendents;
30% ear changes, 5% other changes and 8% scratches; and a two-hour final report
deadline. Both sections finish judging before finalization. Four report workers
and 16 concurrent renders remain unchanged, with the planned worker interruption.

Full-event results are recorded separately. Payments and email are simulated.
Physical printing, hosted capacity, real provider settlement and simultaneous
rendered browser sessions are outside this local rehearsal.

## Follow-up: coop preparation timeout

The restarted event completed all 30 registration days: 51,422 entries, 5,056
purchasers and $257,110 in simulated payments reconciled exactly. The final day
completed all 1,518 purchasers and 15,417 entries at concurrency 500 in 57.23
seconds. All 3,574 support requests succeeded. One webhook 502 recovered on its
normal provider retry; there were no failed user actions or pool timeouts.

The run then stopped at coop assignment: the RPC exceeded its eight-second
statement timeout. The transaction left zero coop assignments. Full-function
rollback diagnostics took 7.70–8.13 seconds. Moving the overwrite condition inside
the existing-assignment exclusion reduced a diagnostic to 0.67 seconds while
preserving all 51,422 assignments. The shipped rewrite also treats a NULL
overwrite flag like false, preserving the original behavior.

Migration `20260912125700_optimize_coop_assignment_existing_lookup.sql` changes
only that predicate in the installed function, retaining its permissions,
security checks and numbering rules. It fails on an unfamiliar definition.
Full local preparation reapplies it after restoring the historical function.
Ten regression checks passed under the original eight-second candidate timeout:
exact separate and combined numbering, blank-only filling, retries, NULL flags,
manual labels, regeneration, unrelated-user denial, function metadata and
migration idempotency. All comparison changes were rolled back.

The failed run and diagnostics remain in `double-event-r2-20260912`. A new clean
run with the coop repair uses `double-event-r3-20260912`; the timeout is not
relabelled as a successful printing stage.

The third run stopped on day 23 because its Python account-lookup retry helper
classified an Edge HTTP 500 by the text `code` in its body. The Dart client
already classifies FunctionException by HTTP status and would retry that error.
The harness now distinguishes FunctionException-style requests from database
errors. Four Python parity tests and an additional Dart test cover this exact
worker-retirement response, retry bounds, permissions and rate limits. Eight
Python tests and thirteen focused Dart tests pass. That failed run remains
preserved; `double-event-r4-20260912` is the next clean full event.

The fourth run again passed registration and assigned all coop numbers through
the real API in 688 ms. Both check-in sheet files generated. Coop-card loading,
however, hit its 90-second deadline: offset queries repeatedly rechecked earlier
assignments. The loader now uses an animal/scope cursor, preserving both cards
when one animal has Open and Youth assignments across a page boundary. Repeated
or invalid cursors fail visibly. Loading and rendering deadlines are unchanged.

The focused real-UI retest, with 50 support sessions, produced a 44,146,122-byte
PDF in 92.85 seconds. Its 12,856 pages contain all 51,422 tattoos, coop labels,
entry labels and section footers exactly once. First and last pages were visually
checked. Assignment-query execution fell from 46.43 seconds for just 35 offset
pages before timeout to 4.84 seconds for all 53 cursor pages. Sixteen focused Dart
tests, eight Python tests and Flutter analysis pass. A verified active-cart lookup
also releases an uncertain creation draft before a later intentional purchase.

The fourth run remains failed in its original evidence. The next clean run is
`double-event-r5-20260912`, including the cursor loader and all preceding fixes.

The fifth run passed registration (174.29 seconds), preprint generation
(167.40 seconds), the complete 17,912-page preprint audit, and both check-in
days (280.11 seconds total). All 22,112 changes and both days' cash-payment
flows completed. Open judging sheets then failed because a single class
table exceeded the PDF package's default 20-page spanning guard in the
assertion-enabled Flutter integration test. This guard is disabled in release
builds; the fix allows valid large classes to pass development/test generation
without disabling assertions. Youth
judging sheets and both comment-card files generated successfully. The
largest Open class has 481 animals.

The control-sheet generator now sets a finite allowance proportional to the
largest class's row count. It preserves the table, layout, QR codes, and
existing generation deadline. The failed fifth run remains preserved; its
focused real-UI retest and full printed-population audit are recorded in
`registration-repairs-20260912/control-pagination-ui`. The next clean event
uses `double-event-r6-20260912`.

The focused Open-sheet retest passed in 173.89 seconds: 2,406 pages, all
34,741 active entries exactly once. The combined judging-pack audit passed
all 27,318 pages, including both copies on every comment card.
Fifty support sessions had no failed actions during the retest; class-start
and continuation pages were visually inspected. Flutter analysis and
`git diff --check` passed.

The sixth fresh run passed registration, preprint generation/audits, both
check-in days, judging packs/audits, and both judging days. Finalization succeeded,
but the immediately following dashboard read and 18 admin refreshes timed out.
Report workers did not start. Post-failure data reconciliation passed all 16
checks. See `doubled-full-event-results-2026-09-12.md` for the preserved failure,
read-only diagnostics and remaining work. This full run is not marked passed.
