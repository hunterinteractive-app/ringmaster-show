# Disposable local Supabase bootstrap

Production predates the checked-in migration history. This directory reconstructs
its prerequisites for local database tests. The original SQL bootstrap was built
without a hosted export. The separate `e2e_historical_*.json` fixtures added for
the full workflow rehearsal contain selected schema definitions inspected
read-only on September 10, 2026; they contain no hosted records or credentials.
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

See `tool/full_e2e/README.md` for the isolated full workflow test, its additional
historical contracts and its remaining catalog/browser parity limitations.

`e2e_breed_abbreviations.json` contains 44 reference catalog records inspected
read-only on September 10, 2026. The full rehearsal's `restore_catalog.py` also
uses five explicitly synthetic fallback prefixes to avoid convention coop-label
collisions; these are not official breed abbreviations. The fixture contains no
hosted exhibitor or payment records. `e2e_account_lookup.sql` restores the
service-only unclaimed-exhibitor lookup used by the account Edge Function.
`legacy_foundation.sql` includes the historical reporting-clerk permission helper
so the database tests can run without first invoking the full-show preparation.

The event-sequence rehearsal also restores inspected print-view projections,
typed print RPCs, four SELECT policies and the judge-management permission helper
from `e2e_historical_print_*.json` and
`e2e_historical_browser_permissions.json`. `prepare.py` includes the historical
show timezone and entry-opening columns used by the management screen. These
are local fixture contracts only. The `e2e_historical_staff_pins.json` and
`e2e_historical_validate_staff_pin.json` definitions restore caller-specific PIN
generation, reading and validation through `restore_staff_pins.py`.
`e2e_historical_delivery_policy.json` restores the inspected authenticated
delivery-history read policy. Those additional contracts were inspected on
September 10–11, 2026, without reading hosted records or changing production.

The local balance report returns cart-level rows; production's inspected
contract returns exhibitor-level rows. The local print restoration therefore
aggregates balances by exhibitor before joining check-in entries. This prevents
cash-change carts from duplicating check-in rows and comment cards. The full
production balance calculation is still not claimed as part of this fixture.
