# Local national-scale loader tests

This is a **report completeness lab**, not a national-show capacity certification.
It seeds 30,000 synthetic animals, 3,000 exhibitors, two Open sections (A/B),
60,000 entries, 30,000 combined coop assignments, and four known breed winners.
Every exhibitor owns ten animals entered in both sections. Each section has
24,000 Mini Rex and 6,000 Jersey Wooly, deliberately concentrated into large
classes to expose missing rows and expensive aggregation. Synthetic ARBA
sanction values allow leg qualification to run.

The lab uses the checked-in `supabase/local/baseline.sql` and actual application
loaders. It does **not** apply the complete migration history. The initial full
bootstrap attempt failed at `20260718164151_add_national_club_sanction_links.sql`
because the baseline lacks `breed_club_sanction_links` and related legacy tables.
The baseline also reconstructs legacy reporting RPCs with simplified queries.
Local timings must not be used to size production or promise throughput.

## Run

Run from the repository root, with Flutter, Python 3, Supabase CLI, and Docker
available. The initial run used Supabase CLI 2.95.4 and `api.max_rows = 1000`.

```sh
flutter pub get
python3 tool/national_scale/prepare.py /tmp/ringmaster-national-loader-lab
supabase start --workdir /tmp/ringmaster-national-loader-lab --exclude edge-runtime,logflare,vector,supavisor,studio,postgres-meta,imgproxy
python3 tool/national_scale/run.py /tmp/ringmaster-national-loader-lab
```

Preparation refuses an existing directory and uses the fixed, isolated Docker
project ID `ringmaster-national-loader-lab` for the original scenario. Stop a
previous lab before starting another one, since they use the same local ports.
Nothing links to a hosted project. No customer data, hosted keys,
payment providers, or email delivery services are copied or invoked. Supabase's
local Mailpit service captures local mail; these tests only read report data.

`run.py` requires the lab marker, verifies the project ID and loopback API URL,
obtains local credentials without printing or saving them, and propagates test
failures as a nonzero exit status. Tests are skipped in an ordinary `flutter test`
run unless explicitly enabled. Each test has a five-minute timeout in the runner.

Run only matching tests after a targeted change:

```sh
python3 tool/national_scale/run.py /tmp/ringmaster-national-loader-lab 'breed winner'
```

Stop the local services while retaining the fixture database:

```sh
supabase stop --workdir /tmp/ringmaster-national-loader-lab
```

## Coverage and interpretation

- Independently verifies fixture counts with exact database counts.
- Reconciles all balance-entry IDs, all entered exhibitors, and all coop animals.
- Checks two exhibitors at different positions in the result ordering.
- Expects 20 entries per exhibitor and known class population counts.
- Expects four legs for exhibitor 1, with known breed and exhibitor populations.
- Checks the application ID reader with 100 and 500 UUIDs; it must return all
  requested entries through bounded batches.
- Prints observed counts and elapsed milliseconds, even when assertions fail.

The nine tests assert complete output and pass after the loader fixes. Do not
change expected counts to match truncated output or raise the API limit to hide
it. The reader splits large ID lists into batches of 100, fetches every result
page, and propagates errors. Population counts are built once per load. Each
exhibitor report reuses its results for its leg check; repeated reads across
thousands of separate reports still need throughput testing.

Not covered: production query plans and schema parity; authenticated RLS;
registration, payments, check-in writes, simultaneous judging; full PDF rendering
and delivery; queue recovery, interrupted saves, or backup restoration. These
require a subsequent faithful staging rehearsal with the actual show structure.

See `docs/national-scale-testing.md` for the initial and corrected results.

## 2024 convention count scenario

The additional scenario uses the user's `2024 Open.pdf` and `2024 Youth.pdf`
count tables: **18,867 Open + 6,844 Youth = 25,711 entries**, with one Open A
and one Youth A. The user supplied 2,528 total exhibitors and approved the
proportional synthetic split of 1,855 Open and 673 Youth with no overlap.
The original 30,000-animal scenario is retained separately.

```sh
python3 tool/national_scale/prepare.py /tmp/ringmaster-convention-loader-lab --scenario convention-2024
supabase start --workdir /tmp/ringmaster-convention-loader-lab --exclude edge-runtime,logflare,vector,supavisor,studio,postgres-meta,imgproxy
python3 tool/national_scale/run.py /tmp/ringmaster-convention-loader-lab
supabase stop --workdir /tmp/ringmaster-convention-loader-lab
```

This uses project ID `ringmaster-convention-loader-lab`. The runner recognizes
that ID and requires the generated `convention_manifest.json` before enabling
`test/convention_scale_local_integration_test.dart`. Both scenarios retain the
loopback-only guards and API cap of 1,000. Tests only read seeded application data.

`convention_2024_counts.json` contains the verified source counts, original
labels, Youth page references, and SHA-256 fingerprints of both PDFs. The 56
category totals in each section and all 879 Youth class rows reconcile with
the source totals. Open classes are allocated in the same proportions as Youth
within each breed using integer largest remainders, preserving the exact Open
breed totals. The convention generator uses only Python's standard library.

The extraction can be reproduced separately with Python and `pdfplumber`:

```sh
python3 tool/national_scale/extract_convention_2024.py '/path/2024 Open.pdf' '/path/2024 Youth.pdf' /tmp/convention-counts.json
```

Exhibitor ownership is synthetic: contiguous groups of 10 or 11 entries. Each
entry gets its own synthetic animal and coop record. Meat pens are represented
as entry records, so 25,711 is not a claim about individual physical animals.
Coop numbering is separate by Open/Youth. Placements and 104 BOB awards are
synthetic; no real exhibitor identities, results, or payment data were provided.

The 15 integration tests check exact fixture counts and the API cap, every
breed total, every Youth class count, all entry IDs and placements, all entered
exhibitors, all/scoped coop cards and populations, six sampled exhibitor reports,
all expected synthetic FIRST/BOB legs, and four simultaneous report reads.
This remains a baseline-only report lab. It does not exercise registration,
authenticated staff writes, payment reconciliation, production entry validation,
all award types, PDF rendering/delivery, or a full closeout for 2,528 exhibitors.

See `docs/convention-2024-testing.md` for measured results and the class-count fix.
