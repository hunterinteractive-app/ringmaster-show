# Closeout renderer

Trusted Dart worker for the database-backed Closeout render queue. It reuses
the same loaders and PDF builders as Flutter without starting a Flutter engine.
The package's narrow `lib/` links point to the repository's shared reporting,
Closeout, and cavy-rule sources; the container build copies those same sources
into the build stage, so no builder is duplicated.

From this directory:

```sh
dart pub get
ASSET_ROOT=../../assets dart run bin/closeout_renderer.dart --dry-run
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_SERVICE_ROLE_KEY=local-service-role-key \
ASSET_ROOT=../../assets dart run bin/closeout_renderer.dart
```

The default command processes one bounded batch and exits. Use `--continuous`
for polling or `--serve` for Cloud Run (`GET /health`, authenticated
`POST /work`, and authenticated `POST /dispatch`). Both POST routes prefer
`X-Work-Token: $WORK_TRIGGER_TOKEN` and retain
`Authorization: Bearer $WORK_TRIGGER_TOKEN` as a manual fallback. Cloud Run IAM
should also restrict ingress.

`/dispatch` fans out bounded, parallel `/work` requests to the same Cloud Run
service and never renders a report itself. Set `WORKER_BASE_URL` to the Cloud
Run service URL. The dispatcher requests a Google identity token from the
Cloud Run metadata server with `WORKER_BASE_URL` as its audience, sends that
token in `Authorization`, and sends the application token in `X-Work-Token`.
Grant the service's runtime service account `roles/run.invoker` on the service
so these authenticated self-invocations succeed.

For horizontal scaling, schedule `POST /dispatch`, configure Cloud Run request
concurrency to `1`, allow at least `DISPATCH_CONCURRENCY + 1` instances (one
dispatcher plus the worker requests), and start with
`DISPATCH_CONCURRENCY=25`. `DISPATCH_MAX_ROUNDS` can perform additional bounded
waves when work remains. With four concurrent renders per worker, 25 worker
requests can process approximately 100 reports concurrently.

Dispatch responses keep report-render `failed` counts separate from internal
HTTP `request_failures`. `remaining` is the minimum successful global queue
snapshot from the final observed round; it is never summed across workers.

### Immediate Sweepstakes portal downloads

The `sweepstakes-download-reports` Edge Function queues fresh artifacts before
invoking the private report worker's `/dispatch` endpoint directly. The existing
scheduler identity has `roles/run.invoker` only on this service. No Scheduler
run permission is required, and no refund scheduler is invoked.

The Edge Function uses `EdgeRuntime.waitUntil` to keep the authenticated HTTP
request alive after returning the queued response. `/dispatch` holds its response
until the bounded render batch finishes. A wake-up is attempted for every committed
request, with a 120-second bound and sanitized failure logging. The database queue
is durable; the one-minute scheduled worker recovers work if the Edge instance
shuts down or direct invocation fails. Polling does not reset or requeue work.

Deployment order:

1. Apply `20261023091948_deduplicate_portal_report_regeneration.sql`.
2. Reuse the approved scheduler identity's service-specific `roles/run.invoker`.
   Do not grant Scheduler run permissions or project Editor/Owner.
3. Set server-only Edge secrets `CLOSEOUT_WORKER_URL` to the private Cloud Run
   service origin, `CLOSEOUT_WORKER_TRIGGER_TOKEN` to its application work token,
   and `CLOSEOUT_WORKER_GOOGLE_CREDENTIALS` to the approved account's JSON key.
   Transfer through protected temporary files, delete them afterward, and never
   expose credentials in browser variables, logs, source control or arguments.
4. Deploy the Edge Function and portal. Keep the scheduled backup enabled.
5. Verify fresh artifact generations finish after Download, including concurrent
   requests. `worker_trigger: requested` means a background wake-up was initiated,
   not that rendering has completed. Verify actual artifact status before download.

Cloud Run remains private and requires both Google OIDC and the application token.
Full show generation and the individual PDF build timeout are unchanged.

Required environment variables outside `--dry-run` are `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`. Optional variables are `WORKER_ID`,
`TASK_BATCH_SIZE`, `POLL_INTERVAL_SECONDS`, `MAX_CONCURRENT_RENDERS`,
`STORAGE_BUCKET`, `ASSET_ROOT`, `WORK_TRIGGER_TOKEN`, `WORKER_BASE_URL`,
`DISPATCH_CONCURRENCY` (default `1`, range `1`–`25`),
`DISPATCH_MAX_ROUNDS` (default `1`, range `1`–`5`), `PORT`, and `BUILD_VERSION`.
`WORKER_BASE_URL` is required only when `/dispatch` is used. There are no
production defaults for credentials or service URLs.

Build from the repository root:

```sh
docker build -f worker/closeout_renderer/Dockerfile -t closeout-renderer:local .
```

Restricted exhibitor print packs use a separate `exhibitor_print_packs` queue
and private Storage bucket. When the ordinary queue is idle, the container
claims one pack and merges its current source PDFs with pinned `pypdf`.
The manifest is checked before and after merging; changed or unfinished sources
require a new request. Each exhibitor's report precedes their legs, and bookmarks
retain the source labels. Pages and images are preserved without rasterizing.
Placeholder pages containing only "No leg certificates earned." are omitted
from legs PDFs in the pack; exhibitor reports and actual certificates remain.

Only account IDs in `exhibitor_print_pack_accounts` can request or download
packs, subject to their existing show permissions. Account access is administered
through trusted database operations, never client writes. Packs do not enter
the email delivery queue. Regenerate a pack after regenerating source reports.

Python tests: `python -m unittest discover -s worker/closeout_renderer/python -v`
from the repository root, with `python/requirements.txt` installed in a venv.
The SQL fixture and security test in `supabase/tests/exhibitor_print_pack_*`
are for an isolated PostgreSQL database only; run fixture, migration, then test.

Report rendering now claims at most `min(TASK_BATCH_SIZE,
MAX_CONCURRENT_RENDERS)` tasks, so claimed jobs start immediately. Each PDF
build runs in a disposable isolate with a two-minute hard deadline; expiration
terminates the isolate and records a permanent `render_timeout` requiring
review. Queue handling and lease heartbeats stay outside the PDF isolate.

Worker result snapshots are shared across simultaneous exhibitor/leg reports
for at most four scopes, with database revision checks before and after reads.
Entry, section, exhibitor number, profile, and catalog INSERT/UPDATE/DELETE
statements invalidate the relevant revision. Interactive repositories do not
reuse snapshots. Section caches now use `get_report_result_revision_scoped`:
entry edits invalidate their own sections, while shared profile/catalog and
show-structure changes still invalidate all affected scopes. Deploy migrations
`20260910101746`, `20260910102054`, `20260910105106`, `20260910213537`, and
`20260910213930` before the corresponding app/worker version. The latter two
also provide the optimized judging read and check-in fee section attribution.

Expired tasks below their attempt limit return to the queue automatically when
a worker next claims work. Recovery retains the artifact generation and its
immutable upload path. Exhausted tasks remain failed for review; workers must
continue polling or be dispatched for automatic recovery to run.

The national rehearsal completes both Open and Youth judging before either
section is finalized or any worker is started. Section revision isolation
remains a defensive correctness guarantee rather than a requirement to overlap
judging with final report generation.

Immutable uploads now atomically store a receipt in Storage object metadata.
Before rendering, a retry validates the existing object's artifact, run, scope,
generation, size, MIME type and SHA-256, then completes using that original
receipt. A duplicate upload also returns the verified original receipt even
when a new PDF has different timestamps. Objects without a verifiable receipt
fail visibly; recover those older orphaned uploads through a new artifact
generation instead of overwriting their immutable paths.
