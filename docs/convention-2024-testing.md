# 2024 convention-count rehearsal

For the subsequent completeness fixes, repaired tests, and rerun results, see
[the September 10 follow-up](national-readiness-fixes.md). Earlier failures below
are retained as historical test evidence.

**All 15 local integration checks passed after fixing one newly exposed coop
class-count bug.** All 18 focused regression tests also passed, and Dart analysis
of the affected loader and new tests reported no issues.

Run: September 9, 2026, America/Indiana/Indianapolis. Base revision `55dc5b0`,
with the prior report-completeness fixes and this run's changes in the working
tree. No deployment was performed.

## Dataset and assumptions

The supplied `2024 Open.pdf` reports **18,867 entries**. `2024 Youth.pdf` reports
**6,844 entries**. The test therefore contains **25,711 entry records**, one
Open A section, one Youth A section, and the user's **2,528 exhibitors**.
The user approved a proportional synthetic exhibitor split: **1,855 Open and
673 Youth**, with no overlap.

Every one of the **56 breed/meat-class categories per section** reconciles with
the source tables. All **879 Youth class rows**, their variety/group subtotals,
and the Youth total reconcile exactly. Open class detail was not supplied, so
the generator scales each breed's Youth class proportions to its exact Open
total using integer largest remainders. The fixture has 1,758 occupied classes
across both sections.

Other modeled details are explicitly synthetic:

- Exhibitor ownership uses contiguous groups of 10 or 11 entries. Actual
  exhibitor identities, breed ownership, and cross-section participation were
  not supplied.
- Each entry has one synthetic animal record and one coop record. Meat pens
  remain entry records; 25,711 is not a count of individual physical rabbits.
- Coop numbering is separate for Open/Youth. Both section letters are A to
  exercise section separation independently of the letter.
- Placements run from 1 to the class size. One synthetic BOB is assigned to
  each breed in each section, excluding the four meat classes: 104 BOB awards.
  These are not historical convention winners.
- All entries are shown. There are no fur duplicates, scratches, DQs, or payment
  records in this particular fixture.

The source JSON preserves the PDF labels and includes page references and file
fingerprints. The fixture uses those labels without claiming full production
breed-directory or entry-validation parity.

## Results

| Check | Observed and required result | Local time |
| --- | --- | --- |
| Fixture and API cap | 25,711 entries/animal records/coops; 2,528 exhibitors; 104 awards; two sections; unpaged response remains capped at 1,000 | <1 s |
| Full result snapshot | 25,711 unique rows; all 112 breed totals, all 879 Youth class counts, and every placement reconcile | 6.0 s |
| Balance report entry read | All 25,711 unique entry IDs | 5.6 s |
| Entered-exhibitor lists | 2,528 overall; 1,855 Open; 673 Youth; exact exhibitor numbers | 1.3 s for all three reads |
| All coop cards | 25,711 unique cards; correct scope, class population, and exhibitor population on every card | 9.2 s |
| Open coop cards | 18,867 unique Open cards; correct populations | 9.1 s |
| Youth coop cards | 6,844 unique Youth cards; correct populations | 9.6 s |
| Six sampled exhibitor reports | Exact entries, placements, awards, earned-leg flags and class/exhibitor counts | 6.1–6.6 s each |
| All synthetic legs | 554 unique certificates: 455 FIRST and 99 BOB; exact qualifying populations and section sanctions | 8.2 s |
| Four simultaneous reads | Open results, Youth results, balance entries, and exhibitor list all complete | 5.7 s |

The six samples cover the first and last exhibitor in each section and the owner
of the first Netherland Dwarf entry in each section. Expected leg outputs were
calculated from the seeded FIRST/BOB winners, animal counts, distinct exhibitor
counts, and the current qualification thresholds. Lower qualifying awards for
the same animal are deduplicated. This verifies the application's output for
this synthetic case, not official historical leg entitlement or all award rules.

The suite finished in **116 seconds**, including assertions. Table timings
measure the loaders, except the concurrent-read and exhibitor-list measurements
which also include their reconciliation assertions. These are individual local
observations, not production capacity, latency guarantees, or controlled
comparisons with the prior stress scenario.

## Newly exposed issue and correction

The source Youth report uses `PREJUNIOR BUCK`. The coop loader recognized
`Pre-Junior` and `Pre Junior`, but the unseparated spelling fell through to
`Junior`. This merged distinct age classes and inflated card populations:

- Youth Californian Prejunior Bucks: **25 reported instead of 1** (the one
  Prejunior Buck was combined with 24 Junior Bucks).
- The proportional Open fixture: **58 instead of 2** (combined with 56 Juniors).

The coop loader now recognizes `prejunior` before checking for `junior`.
The new focused regression verifies that all three Prejunior spellings share
their own animal/exhibitor population and remain separate from Junior. The
full convention rerun confirms the correct class count on every coop card.

During harness development, test expectations were corrected for the RPC's
uppercase section labels, explicit ascending section ordering, and the display
label `Best of Breed`. These were test assumptions, not application failures.
The generated seed was also wrapped in one SQL block to keep temporary-table
creation and use together under the local CLI's statement batching.

## Scope and remaining rehearsal work

This runs the real Dart report loaders against the repository's local baseline
with Supabase CLI 2.95.4, local service-role access, and `api.max_rows = 1000`.
The baseline reconstructs reporting RPCs and lacks parts of the full migration
history. It does not reproduce production schema, indexes, triggers, auth/RLS,
or network conditions. The earlier [national-scale report](national-scale-testing.md)
documents that bootstrap limitation and the separate 60,000-entry stress case.

Four concurrent report reads are not simultaneous registration, check-in, or
judging writes. This run does not test payments, production entry validation,
all award types, PDF rendering/delivery, all 2,528 exhibitor reports in one
closeout, queued-worker recovery, interrupted saves, or backup restoration.
Sampled exhibitor reports still load the selected sections' results separately
for each exhibitor, so full-closeout throughput remains a measurement priority.
National-show readiness still needs that broader staging rehearsal.

## Reproduce and evidence

See [the scenario runner instructions](../tool/national_scale/README.md#2024-convention-count-scenario).
The retained workspace is `/tmp/ringmaster-convention-loader-lab-20260910`;
project ID `ringmaster-convention-loader-lab`. Local services were stopped after
verification; the synthetic fixture database is retained for reuse.

Files:

- Source counts: `tool/national_scale/convention_2024_counts.json`
- Reproducible PDF extraction: `tool/national_scale/extract_convention_2024.py`
- Fixture generator: `tool/national_scale/convention_2024.py`
- Integration checks: `test/convention_scale_local_integration_test.dart`
- Focused class regression: `test/coop_cards_class_population_test.dart`
- Local evidence (ignored by Git): `output/national_scale/convention_2024/tests.log`,
  `regressions.log`, `analysis.log`, and `initial-tests.log`

The full unrelated Flutter/worker suites were not rerun for this focused
addition. Their pre-existing failures remain documented in the prior report.

## Verified source breed counts

| Source category | Open | Youth | Combined |
| --- | ---: | ---: | ---: |
| American | 91 | 48 | 139 |
| American Chinchilla | 135 | 19 | 154 |
| American Fuzzy Lop | 314 | 78 | 392 |
| American Sable | 64 | 28 | 92 |
| Argente Brun | 82 | 28 | 110 |
| Belgian Hare | 112 | 40 | 152 |
| Beveren | 54 | 22 | 76 |
| Blanc De Hotot | 62 | 35 | 97 |
| Blue Holicer | 162 | 39 | 201 |
| Britannia Petite | 336 | 91 | 427 |
| Californian | 465 | 201 | 666 |
| Champagne Dargent | 225 | 83 | 308 |
| Checkered Giant | 138 | 27 | 165 |
| Cinnamon | 67 | 21 | 88 |
| Creme D Argent | 106 | 26 | 132 |
| Czech Frosty | 107 | 31 | 138 |
| Dutch | 860 | 308 | 1,168 |
| Dwarf Hotot | 159 | 83 | 242 |
| Dwarf Papillon | 166 | 31 | 197 |
| English Angora | 88 | 10 | 98 |
| English Lop | 309 | 130 | 439 |
| English Spot | 266 | 69 | 335 |
| Flemish Giant | 521 | 167 | 688 |
| Florida White | 381 | 116 | 497 |
| French Angora | 105 | 14 | 119 |
| French Lop | 310 | 84 | 394 |
| Giant Angora | 47 | 6 | 53 |
| Giant Chinchilla | 58 | 13 | 71 |
| Harlequin | 107 | 38 | 145 |
| Havana | 574 | 184 | 758 |
| Himalayan | 220 | 164 | 384 |
| Holland Lop | 1,201 | 469 | 1,670 |
| Jersey Wooly | 530 | 196 | 726 |
| Lilac | 94 | 34 | 128 |
| Lionhead | 277 | 124 | 401 |
| Meat Pen | 62 | 30 | 92 |
| Mini Lop | 734 | 390 | 1,124 |
| Mini Rex | 1,615 | 668 | 2,283 |
| Mini Satin | 885 | 294 | 1,179 |
| Netherland Dwarf | 2,010 | 686 | 2,696 |
| New Zealand | 938 | 344 | 1,282 |
| Palomino | 122 | 61 | 183 |
| Polish | 778 | 350 | 1,128 |
| Rex | 753 | 170 | 923 |
| Rhinelander | 112 | 33 | 145 |
| Roaster | 53 | 55 | 108 |
| Satin | 651 | 191 | 842 |
| Satin Angora | 84 | 14 | 98 |
| Silver | 220 | 66 | 286 |
| Silver Fox | 228 | 28 | 256 |
| Silver Marten | 164 | 63 | 227 |
| Single Fryer | 108 | 67 | 175 |
| Standard Chinchilla | 72 | 25 | 97 |
| Stewer | 47 | 38 | 85 |
| Tan | 292 | 162 | 454 |
| Thrianta | 146 | 52 | 198 |
| **Total** | **18,867** | **6,844** | **25,711** |
