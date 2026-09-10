# Full local workflow rehearsal

This harness exercises the actual Auth, Data API, RPCs, payment Edge Functions,
closeout workers, PDF builders, Storage and report-email Edge Functions. It uses
25,711 synthetic entries and 2,528 synthetic exhibitors, derived from the 2024
Open/Youth convention counts. It never operates on a linked or hosted project.

The `Local` guard requires a disposable `/tmp` workspace, the exact project ID
`ringmaster-show-full-e2e` (optionally followed by a unique lowercase suffix),
loopback API URLs, and byte-identical production
migrations. Production migrations and application code are not altered by this
harness. Existing test evidence is retained; there is no automatic destructive
reset. Stop older local stacks before starting this stack on the default ports.

## Workload and boundaries

- Open: 18,867 entries / 1,855 exhibitors; Youth: 6,844 / 673; no overlap.
- Registration: 12 concurrent synthetic purchasers, $5 per entry, absorbed fees.
- Check-in: 30 staff, 10 admins, 15 superintendents. Thirty approved tattoo
  corrections each incur a $5 cash payment. All exhibitors complete check-in.
- Judging: 110 clerks, 10 admins, 15 superintendents. QR/manual writes split 55/55.
  Separate all-QR and all-manual navigation bursts test complete cursor reads.
- Open closeout starts while Youth judging continues. Four worker processes
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

The breed abbreviation/reference catalog remains incomplete. The September 10
test found duplicate coop-label prefixes across breeds. Resolve catalog parity
before using a fresh fixture to certify coop labels or browser behavior.

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
advances that worker's leases, then invokes the real stale-recovery RPC. This
accelerated lease test must be distinguished from waiting a real lease duration.

## Cleanup

Stop only processes started for this rehearsal. Stop this local Supabase project
without `--no-backup` so its named volumes and failed-run evidence remain. Never
run a production reset or delete unrelated projects/volumes. Commit only the
harness, local contracts and written results, not credentials, dumps or PDFs.
