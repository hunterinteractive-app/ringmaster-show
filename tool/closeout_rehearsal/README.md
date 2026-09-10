# Local closeout and staff rehearsal

This harness uses the 2024 convention counts and the **full reconstructed local
schema**. It runs 40 independently signed-in Auth users: 16 check-in staff,
20 judging staff, and four administrators. Staff use the application's RPCs.
Four unchanged compiled workers claim tasks, render PDFs, and upload to local
Storage, with four simultaneous renders per worker.

The September 10 run **failed full closeout**. Successful staff writes do not
mean the show is ready for national use. See
[`docs/closeout-staff-rehearsal-2026-09-10.md`](../../docs/closeout-staff-rehearsal-2026-09-10.md).

## Next workload

The user's revised workload is recorded in `workload.json`: a **55-session
check-in phase** (30 check-in, 10 admins, 15 superintendents), followed by a
**135-session judging/closeout phase** (110 judging tables, 10 admins,
15 superintendents). QR and manual entry must both be exercised. Check-in and
judging do not overlap. Payments are primarily synthetic online payments, with
occasional small cash change fees; $5 is an adjustable test assumption.

`run.py` preserves the historical 40-session diagnostic. It is not the runner
for that next workload and requires `--historical-40-session-replay` explicitly.
Update the phased runner and payment reconciliation from `workload.json` before
the next full rehearsal. The five-fix checks do not launch that rehearsal:

```sh
python3 tool/closeout_rehearsal/fix_regressions.py <local-workspace>
```

This focused probe reads the preserved synthetic fixture, renders five reports,
and checks immutable upload recovery with a temporary object removed afterward.
It never claims queued tasks, finalizes, sends mail, or contacts payment providers.

## Guards and limits

- Only `ringmaster-show-local-e2e`, no linked project, loopback HTTP URLs, and
  exactly 25,711 synthetic convention entries are accepted.
- Every copied production migration must match the current repository bytes.
- The runner refuses pre-existing closeout evidence and another show's pending
  queue. Global workers must never be pointed at a shared or hosted project.
- Credentials are obtained from local CLI status, kept in memory, and passed
  only to local child processes. They are not printed or persisted in logs.
- No payment provider or email provider is called. The 64 cash payments are
  synthetic records. `no_receipt` is used for staff check-in.
- The test has a configurable diagnostic time limit, defaults to 45 minutes,
  and stops early at 50 failed tasks. The measured run used ten minutes because
  layout stalls and dashboard timeouts already demonstrated failure. Shutdown
  allows each worker 30 seconds before killing it.
- A failed render stage or failed request makes `run.py` exit nonzero. Full
  verification exits nonzero when any check fails; expected red results must
  not be presented as a passed test.

## Fresh setup

Run from the repository root with Docker, Supabase CLI, Python, Dart, and the
worker's existing dependencies installed. Use the full local bootstrap described
in [`supabase/local/README.md`](../../supabase/local/README.md).

```sh
tool/local_supabase_e2e.sh /tmp/ringmaster-closeout-rehearsal
supabase start --workdir /tmp/ringmaster-closeout-rehearsal \
  --exclude edge-runtime,logflare,vector,supavisor,studio,postgres-meta,imgproxy
python3 tool/closeout_rehearsal/fixture.py output/closeout_rehearsal
docker exec -i supabase_db_ringmaster-show-local-e2e \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres \
  < output/closeout_rehearsal/seed.sql
```

The project ID determines Docker volumes: a different workspace path alone does
not create a fresh database. The seed refuses an existing convention fixture.
Preserve prior evidence before resetting a disposable local database. A local
reset, when needed, is `supabase db reset --local --workdir <workspace>`; it erases
the contents of that local test database.

The fixture adds historical judging audit columns, `shows.is_closed`, and the
unique `(entry_id, award_code)` index expected by the tracked result-save RPC.
These additions stay outside production migrations. Staff use `reporting_clerk`
and `admin`; the ordinary `clerk` role has no check-in permission.

The fixture preserves exact Open/Youth breed totals and source Youth class
counts. It adds deterministic BIS/RIS winners, national/state club sanctions,
and balances of 500 cents per entry. Exactly 1,000 Youth placements start empty.
Class labels retain the source's sex suffix, and the historical local judge
schema is incomplete; those display details do not establish production parity.

## Run and verify

Compile from `worker/closeout_renderer`:

```sh
dart compile exe bin/closeout_renderer.dart \
  -o ../../output/closeout_rehearsal/closeout-renderer
```

Then, from the repository root:

```sh
python3 tool/closeout_rehearsal/preflight.py /tmp/ringmaster-closeout-rehearsal
python3 tool/closeout_rehearsal/run.py --historical-40-session-replay /tmp/ringmaster-closeout-rehearsal \
  --workers 4 --max-minutes 10
python3 tool/closeout_rehearsal/verify.py /tmp/ringmaster-closeout-rehearsal
python3 tool/closeout_rehearsal/recovery.py /tmp/ringmaster-closeout-rehearsal
supabase stop --workdir /tmp/ringmaster-closeout-rehearsal
```

`verify.py` needs `pypdf`. It reconciles every entry, placement, award, balance,
exhibitor, and artifact owner; downloads every generated object to check its
stored byte size and SHA-256; and saves two generated PDFs per type for inspection.
Rendering all files is a separate check from creating a complete manifest.

`recovery.py` requires workers to be stopped. It tests exact completion replay,
rejects changed checksums, and advances **only synthetic running leases** to
verify recovery without waiting ten minutes. It preserves completed artifacts.
`reset_after_preflight.py` is specifically for a failed, payment-free setup pass;
it refuses a fixture containing payments and retains run logs before clearing
that show's queue. It is not a general database cleanup tool.

## Focused diagnostics

```sh
python3 tool/closeout_rehearsal/probe.py /tmp/ringmaster-closeout-rehearsal details_by_breed
python3 tool/closeout_rehearsal/probe.py /tmp/ringmaster-closeout-rehearsal \
  checkin_sheet --upload-replay
```

The upload probe calls the worker's actual immutable upload method against an
existing synthetic object. It never overwrites or marks a task complete.

The layout-only probe needs no database. From `worker/closeout_renderer`, run:

```sh
dart --enable-asserts run bin/rehearsal_probe.dart --layout-only 10
dart --enable-asserts run bin/rehearsal_probe.dart --layout-only 100
```

Ten short rows render; 100 rows in one class currently throw
`TooManyPagesException`. Keep assertions enabled for this probe: the release
worker can instead consume CPU indefinitely without yielding its heartbeat.

This remains a reconstructed fixture. Historical show scoring is a no-op,
legacy rabbit scoring is simplified, and some historical columns/catalogs are
absent. The harness does not certify scoring, judge labels, immutable result
versioning, browser interaction latency, registration checkout, live email
delivery, or backup restoration.
