# National rehearsal fixes — September 10, 2026

All seven failures from the [full local rehearsal](full-e2e-rehearsal-2026-09-10.md)
have implemented fixes and passing targeted regression checks. The local catalog,
account setup and automatic worker recovery prerequisites were also addressed.
These changes are local and have not been deployed. This is not a new full
end-to-end pass or a certification of hosted national-show capacity.

The next rehearsal will finish **all Open and Youth judging before finalizing
either section or starting report workers**. Check-in remains separate from
judging. Admins and superintendents continue using the application during both
phases; report generation can overlap subsequent read/support activity. This is
the rehearsal sequence, not a new restriction on every show's Closeout UI.

## Application repairs

| Original failure | Implemented fix | Verified result |
| --- | --- | --- |
| ARBA animal count capped at 1,000; only 12 judges printed | Exact database counts; paginated judge attachment retaining the official form's first 12 slots | Open 18,867 / Youth 6,844; all 110 judges in each three-page PDF |
| American rabbits treated as cavies | Hydrate explicit entry species before filtering results and awards; reject missing species for the ambiguous American name | All 104 breed detail PDFs match expected top-five placings and known BIS/RIS winners |
| Manual navigation and superintendent timeouts | Bound and enrich each judging page in one RPC; index show/section cursors and catalog lookups; replace repeated client hydration reads | 135-session QR and manual bursts complete with zero errors |
| Four financial reports fail on cash change fees | Persist each fee's section; remove the bookkeeping carrier from animal counts; recognize balances entirely covered by the requested sections | All four paid/unpaid PDFs render and reconcile; $128,555 online plus $150 cash, zero due |
| Two judge PDFs exceed the two-minute deadline | Make the overview table a directly spanning PDF widget; resolve judge identities from the master judge records | Both complete in about 1.2–2.6 seconds including loading, with all 110 named judges and exact entry totals |
| Youth edits invalidate stable Open snapshots | Separate entry revisions by section while retaining show-wide and shared-data invalidation | SQL checks cover same-section changes, section moves, unrelated sections, shared profiles and whole-show compatibility |
| Single breed retry targets ARBA | Restrict canonical ARBA identity repair to ARBA requests; validate requested artifact/type before mutation | Exactly one requested artifact changes generation; invalid requests leave other artifacts untouched |

The fee work also exposed a timestamp comparison that skipped non-default fees
when recalculations shared one transaction timestamp. Fee adjustments now derive
their desired total from the underlying breakdown and remain safe to repeat.
Transactional tests cover $2.50 and $7.50 Youth changes, repeated charge calls,
cash payment, one charge per request, no added animals and no leakage into Open.
Paid-report summaries count distinct exhibitors and visibly label fee-only rows.
Financial safety checks use complete paginated reads.

True partial selection of a payment spanning multiple sections still fails
visibly if its payment/discount allocation is unknown. The implementation does
not invent a split. The tested single Open/single Youth fixture uses the approved
1,855/673 exhibitor split with no overlap.

## Additional prerequisites

- Restored 44 inspected reference abbreviation records and five explicit local
  fallback prefixes. All **25,711 coop labels are unique within their scope**.
  The five supplemental prefixes are synthetic fixture choices, not official
  national abbreviations. The full harness checks uniqueness before check-in.
- Restored the existing `claim-or-import-exhibitor` Edge Function source and its
  local lookup prerequisite. Tests pass for new-account manual setup, matching
  account confirmation, rejection of another account's claim, successful claim,
  repeated lookup and absence of duplicate accounts. The Club lookup provider is
  emulated locally; the complete browser journey still belongs in the next run.
- Expired render tasks now requeue automatically below their attempt limit.
  A real worker was killed; its peer recovered and completed the same artifact
  generation on attempt two without a test-driven recovery RPC or manual retry.
  Completion replay passed and a changed checksum was rejected. Exhausted tasks
  remain failed for review. The test advanced the killed worker's lease, so its
  **8.38-second recovery does not measure the normal ten-minute lease wait**.

## Validation

The report and concurrency probes reused the retained synthetic 25,711-entry,
2,528-exhibitor convention from `output/full_e2e/run-20260910-v6/`. A separate
fresh local database successfully replayed the migration history and prepared
a zero-entry, zero-payment convention for the next run.

| Check | Result |
| --- | --- |
| Targeted PDF rendering and semantic audit | **112 passed:** 104 breed, two ARBA, two judge, two paid and two unpaid |
| PDF visual inspection | ARBA form and attachment continuations, judge table pages and financial fee rows inspected |
| Database regression suite on fresh setup | **104 assertions across 10 files passed**, including clerk access and foreign-account denial |
| Focused Flutter tests | **45 passed** |
| Worker tests, including 110-judge PDF layout | **70 passed** |
| Static analysis of changed Dart paths | No issues |
| Fresh local database security advisor | No error-level issues |
| Financial, single-artifact retry, exhausted retry and account probes | Passed |

The repeated navigation workload uses 110 reporting clerks, 10 admins and 15
superintendents. Manual navigation now matches the selected-section screen and
includes species, animal IDs, coop labels and awards in its pages. The earlier
burst requested the whole show and omitted that hydration, so the timing figures
are not an identical-query before/after benchmark. The pool remained at 10 slots.

| Operation | Calls | Errors | p95 |
| --- | ---: | ---: | ---: |
| Manual judging pages | 5,878 | 0 | 2,029 ms |
| QR judging pages | 224 | 0 | 823 ms |
| Admin dashboard | 188 | 0 | 1,973 ms |
| Superintendent dashboard | 289 | 0 | 2,232 ms |

These are API sessions, not 135 rendered browsers. A manual page peaked at about
6.0 seconds; the entire unpaced manual navigation burst took 46.75 seconds.
The targeted PDF probe renders through the production loaders/builders to disk;
it does not repeat the previous 6,447-artifact closeout and delivery workload.

## Next gate and rollout order

Repeat the same-size **fresh full rehearsal** before increasing the population:
registration, online payment emulation, separate check-in and judging peaks,
both sections completed, finalization, all report generation, delivery, content
reconciliation and recovery. Include browser workflows now that the account
function is available. Real payment settlement, mail deliverability and hosted
capacity remain outside this local test.

Migrations `20260910213537_fix_national_report_scopes_and_recovery.sql` and
`20260910213930_attribute_checkin_fees_to_report_sections.sql` must precede the
updated app/worker wherever it is deployed. Apply only the regular migrations;
files under `supabase/local` are disposable test prerequisites. No production
database, function or worker was changed during this repair session.

Raw verification evidence is retained under
`output/national-fixes-20260910/`, including `reports/content-audit.json`,
`navigation/navigation-with-indexes-summary.json`, `recovery/worker-recovery.json`,
fee and queue checks, account setup results, test logs, generated PDFs and visual
QA images. Output artifacts and credentials remain excluded from source control.
