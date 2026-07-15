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
