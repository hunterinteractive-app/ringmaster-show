# Local Supabase baseline

The production project predates the checked-in migrations. Its foundational
schema was created outside this repository, most likely through Dashboard or
SQL Editor changes. `baseline.sql` is a schema-only reconstruction for new,
non-production environments; it is intentionally outside `supabase/migrations`.

Prepare a disposable local project:

```sh
tool/local_supabase_e2e.sh /tmp/ringmaster-show-local-e2e
supabase start --workdir /tmp/ringmaster-show-local-e2e
```

The generated project applies the baseline as migration `00000000000000`, then
copies and applies every normal migration unchanged, followed by the synthetic
seed. It has a distinct project ID and Docker resources. It contains no real
Auth users, exhibitors, shows, payments, email records, Storage objects, API
keys, or secrets.

Production continues with its existing `supabase_migrations.schema_migrations`
history and never sees the bootstrap file. Future migrations remain in the
normal repository migration directory and are copied identically into new
local/staging workspaces. A new staging project should apply the baseline first,
mark only the baseline version as local/staging-specific, and then apply every
normal migration normally.

Never run the bootstrap against an existing or production database.
