# Disposable local Supabase bootstrap

Production predates the checked-in migration history. This directory reconstructs
its prerequisites for local database tests without exporting hosted schema or data.
It is intentionally outside `supabase/migrations` and must never be applied to an
existing or production project.

```sh
tool/local_supabase_e2e.sh /tmp/ringmaster-show-local-e2e
supabase start --workdir /tmp/ringmaster-show-local-e2e
supabase test db --local --workdir /tmp/ringmaster-show-local-e2e
```

The preparation script refuses an existing workspace and uses the distinct
`ringmaster-show-local-e2e` project ID. It copies these local-only prerequisites:

- `baseline.sql`: the smaller schema and synthetic report/payment fixture;
- `legacy_foundation.sql`: historical table/type/function contracts required by
  the complete migration history, plus reference catalog prerequisites and the
  actual local `pg_cron` extension;
- `readiness_format_compat.sql`: a whitespace-only step immediately before the
  September 3 zero-placement migration. The August 25 function puts its predicate
  on the FROM line; September 3 expects a newline. This step preserves behavior
  while allowing the original migration to apply its intended fix.

All regular migration files are copied byte-for-byte. The final synthetic seed
contains only test shows and example addresses. Local Auth/Storage are supplied
by Supabase itself. Two disabled, synthetic Auth rows satisfy fixed-ID foreign
keys in the tracked print-pack migration; they contain example.invalid addresses
and cannot sign in. No hosted keys, identities, payments, or delivery records are
copied. Edge Functions can be excluded when running database-only tests:

```sh
supabase start --workdir /tmp/ringmaster-show-local-e2e \
  --exclude edge-runtime,logflare,vector,supavisor,studio,postgres-meta,imgproxy
```

## Scope of the fixture

A successful replay demonstrates that the checked-in history can bootstrap a
fresh local database. It does **not** establish schema or scoring parity with
production. Historical scoring/catalog data is incomplete in Git; the local
baseline has simplified rabbit scoring, reporting, and payment calculations.
The obsolete three-argument scoring overload fails explicitly in this fixture.
The full closeout rehearsal must reconcile known expected scores and payments
before this environment is used as evidence of national-show readiness.

The national/convention loader labs remain separate and deliberately apply only
`baseline.sql`. Their results measure complete reads and population calculations,
not full migrations, authentication, hosted latency, or production throughput.
See `docs/national-readiness-fixes.md` for the latest verified results.

Future regular migrations stay in `supabase/migrations`. Do not use these local
fixture definitions as a production migration or staging parity dump.
