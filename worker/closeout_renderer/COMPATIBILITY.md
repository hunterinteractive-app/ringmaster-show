# Closeout renderer compatibility audit

All manifest dispatch uses the explicit keys in `ReportRegistry`; filenames and
display labels are never parsed. The worker injects `SupabaseClient` and
`FileSystemReportAssetLoader`, while Flutter injects
`FlutterReportAssetLoader`. Shared builders do not import Flutter services.

| Manifest report type | Loader scope | Builder status | Worker status |
|---|---|---|---|
| `arba_report` | Artifact `section_id` and sanction | Asset-injected pure Dart | Ready |
| `exhibitor_report` | Exhibitor plus `section_ids` | Asset-injected pure Dart | Ready |
| `checkin_sheet` | Exhibitor; one scoped RPC per section | Asset-injected pure Dart | Ready |
| `legs` | Exhibitor plus `section_ids` | Fonts/logos/certificate art injected | Ready |
| `sweepstakes_report` | Structured scope, letter, breed, club | Asset-injected pure Dart | Ready |
| `breed_results_detail_report` | Structured scope, letter, breed, club | Asset-injected pure Dart | Ready |
| `details_by_breed` | Resolved section from scope and letter | Asset-injected pure Dart | Ready |
| `exh_by_breed` | Resolved section from scope and letter | Asset-injected pure Dart | Ready |
| `best_display_report` | Scope, letter, and species | Asset-injected pure Dart | Ready; staging comparison required |
| `entered_exhibitors_contact_report` | Direct `section_id in (...)` query | Noto theme injected | Ready |
| `ribbon_payout_report` | Exact selected section IDs | Noto theme injected | Ready |
| `payback_report` | One scoped RPC per selected section | Asset-injected pure Dart | Ready |
| `judge_report` | Direct `section_id in (...)` query | Asset-injected pure Dart | Ready |
| `breed_judged_totals_report` | Direct `section_id in (...)` query | Asset-injected pure Dart | Ready |
| `paid_exhibitor_report` | Exact section-aware balance RPC | Asset-injected pure Dart | Ready when allocations are exact |
| `unpaid_balances_report` | Exact section-aware balance RPC | Asset-injected pure Dart | Ready when allocations are exact |

The worker deliberately fails paid/unpaid balance artifacts with
`unsupported_scoped_balance_report` only when a partial scope contains a
whole-balance payment, discount, refund, or adjustment that cannot be allocated
to a section. Exact partial scopes and Entire Show scopes render normally. This
prevents cross-scope financial output without silently prorating money.

`coop_cards` is not created by the Closeout manifest and remains Flutter-only.
No manifest builder uses `BuildContext`, Flutter widgets, `dart:html`,
`Printing.layoutPdf`, browser downloads, or `AppSession`.

The production-readiness harness covers clean migration replay, authorization,
exact-scope manifests, immutable upload, completion replay, regeneration,
concurrent claims, stale-lease recovery, financial ambiguity, and representative
Flutter-versus-worker PDF parity. Run that harness again whenever a shared
loader, builder, migration, or worker dependency changes.
