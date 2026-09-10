# National readiness follow-up — September 10, 2026

This follow-up addresses report completeness, the disposable full-migration
bootstrap, and the pre-existing Flutter/worker test failures. All work is local;
no hosted schema, data, reports, payments, or email deliveries were changed.

## Report completeness

The remaining large row collections now read to an empty page, advancing by
actual rows received. This includes contacts, breed-detail and exhibitor-by-breed
reports, sweepstakes standings, best display, special reports, paybacks, judges,
mailing labels, ribbon payouts, and additional ARBA/exhibitor/leg lookups.
One-to-many enrichments paginate even when the input ID batch is small.
Optional address, point, and award fallbacks now allow missing legacy schema
fields but propagate transport/authorization failures; points cannot silently
become zero after a failed read. Check-in entry/coop enrichment uses batches of 100 UUIDs to bound request URLs.

Read-only set-returning RPCs use the shared page reader. Mutating calculation
RPCs, scalar JSON responses, single-record lookups, and intentionally bounded
summaries retain their own contracts. This does not provide a database snapshot
across simultaneous staff edits; that still needs a workload/recovery rehearsal.

Manual report regeneration now filters by the exact artifact identity in the
database. The previous first-200-artifacts search could miss an existing
exhibitor report and attempt a conflicting insert.

New HTTP-level regressions check:

- 2,528 contacts, with repeated entry rows crossing pages capped at 37;
- 501 check-in entries and their exact coop numbers with bounded URLs;
- 2,501 paybacks totaling 312,625 cents, including retry after a later page fails;
- all 2,528 best-display standings across server pages.

## Full migration bootstrap and database regression

A fresh local reset now applies **215 repository migrations** (the original 214
plus the diagnostic-update fix), **three local bootstrap steps**, and the
synthetic seed. All copied repository migrations match byte-for-byte. The local
migration history contains **218 applied versions**.

All **72 assertions across eight database suites pass**. They cover payment
hardening, authenticated manager/non-manager boundaries, artifact identity,
scoped dashboards, zero placements, species inference, club-manifest rebuilding,
and legacy failed-artifact diagnostics. The security advisor reports no
error-level findings in the local schema.

The full replay exposed a real regression: the JSON-export migration had replaced
the artifact trigger and removed the diagnostic-only exception for current failed
legacy reports. New migration
`20260910041559_restore_closeout_failed_diagnostic_updates.sql` restores that
exception. Twenty existing assertions verify diagnostic updates/repair and keep
identity changes, scope changes, and failed-to-queued transitions subject to
canonical validation. The migration is prepared and tested locally, not deployed.

The database test fixtures now use current section scopes and real show-scoped
role assignments. The club-manifest test's missing CTE parenthesis and incorrect
TAP plan were corrected; all eleven assertions are retained.

The full-migration environment remains a reconstruction with simplified historic
calculators and incomplete reference data. It is suitable for these local
regressions; production-equivalent scoring and full closeout capacity remain to
be demonstrated. See `supabase/local/README.md` for the exact limitations.

## Existing test failures

The previous eleven Flutter failures and one worker failure were reviewed.
The grouped specialty test now includes the already-supported Jersey Wooly.
The obsolete Flutter counter test is replaced with a real report-card interaction.
Closeout contracts now verify pre-show versus finalized identities, current
queue APIs, readiness guards, and regeneration behavior. A mistyped historical
migration filename was corrected. The worker contract preserves the existing
whole-show unpaid report and scoped paid report behavior.

The final Flutter suite passed **360 tests**, with **26 opt-in integration tests**
excluded from the ordinary run. The worker suite passed **48 tests**. The convention
suite was run separately and passed **all 16 tests** in 122 seconds.

## Convention recheck

The retained 2024 fixture still reconciles 18,867 Open and 6,844 Youth entries,
with 1,855 Open and 673 Youth exhibitors and no exhibitor overlap. Breed totals,
879 Youth classes, placements, coops, and 554 synthetic legs remain correct.
Contact counts now reconcile for the entire show and each section.

| Check | Elapsed |
| --- | --- |
| Contact report, entire show | 1.15 s |
| Contact report, Open | 0.67 s |
| Contact report, Youth | 0.17 s |
| Four simultaneous complete report reads | 5.73 s |

These are local synthetic loader measurements, not national-show capacity
certification. The loader lab still uses its deliberately small baseline and
service-role access. Actual simultaneous staff writes, full report rendering
and delivery, worker interruption, and restoration remain the next rehearsal.

## Reproduction and evidence

Logs are under `output/national_scale/readiness_fixes/`: `flutter-final.log`,
`worker-final.log`, `completeness.log`, `convention.log`, `full-reset.log`, `database-tests-final.log`,
`database-advisors-final.log`, and `analysis-final.log`.
The convention database is retained in its original marked workspace and stopped.
See `tool/national_scale/README.md` for the guarded local runner.

The full-migration workspace is separate from the loader lab. See
`supabase/local/README.md` for bootstrap prerequisites and limits.
