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
`POST /work`). `/work` requires `Authorization: Bearer $WORK_TRIGGER_TOKEN`;
Cloud Run IAM should also restrict ingress.

Required environment variables outside `--dry-run` are `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`. Optional variables are `WORKER_ID`,
`TASK_BATCH_SIZE`, `POLL_INTERVAL_SECONDS`, `MAX_CONCURRENT_RENDERS`,
`STORAGE_BUCKET`, `ASSET_ROOT`, `WORK_TRIGGER_TOKEN`, `PORT`, and
`BUILD_VERSION`. There are no production defaults.

Build from the repository root:

```sh
docker build -f worker/closeout_renderer/Dockerfile -t closeout-renderer:local .
```
