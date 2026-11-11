# Houston custom class premiums

Built for shows eligible under the existing `best_of_best_opposite` feature
allowlist, shared with Wave Schedule. The UI and new save RPC both check that
entitlement. It does not add any account to the allowlist.

## Saved Open Rabbit review — November 10, 2026

Production show `232b7ed8-8032-4c05-aa87-db8e00de7dc2`, Open A section
`dbacdf12-d70b-4253-8c2f-cd3d501032df`, schedule
`27782ed4-03a1-4994-aef0-cae7028fba9f` contained five payout rows:

| Shown | First | Second |
|---|---:|---:|
| 2 | $2 | — |
| 3 | $4 | $2 |
| 4 | $4 | $2 |

These agree with Kyle's emailed Open Rabbit table. No class premiums were saved
for 5+ animals. The reviewed Youth Rabbit, Cavy, and Youth Meat Pen shows had no
saved class payout rows. Production schedules were not changed during this work.

## Presets transcribed from Kyle's email

Blank cells mean no premium. Amounts are dollars. The final bracket has no upper
limit. Existing report eligibility rules still determine the number shown.

Open Rabbit and Open Cavy:

| Shown | First | Second | Third | Fourth | Fifth |
|---|---:|---:|---:|---:|---:|
| 2 | 2 | | | | |
| 3–4 | 4 | 2 | | | |
| 5–6 | 6 | 4 | 2 | | |
| 7–8 | 8 | 6 | 4 | 2 | |
| 9+ | 10 | 8 | 6 | 4 | 2 |

Youth Rabbit:

| Shown | First | Second | Third | Fourth | Fifth |
|---|---:|---:|---:|---:|---:|
| 1–3 | 10 | | | | |
| 4–5 | 12 | 11 | 10 | | |
| 6–7 | 14 | 13 | 12 | 11 | |
| 8–9 | 15 | 14 | 13 | 12 | 11 |
| 10–14 | 18 | 16 | 15 | 14 | 13 |
| 15+ | 23 | 21 | 20 | 19 | 18 |

Youth Cavy:

| Shown | First | Second | Third | Fourth | Fifth |
|---|---:|---:|---:|---:|---:|
| 1–3 | 10 | | | | |
| 4–5 | 12 | 11 | | | |
| 6–7 | 14 | 13 | 12 | | |
| 8–9 | 15 | 14 | 13 | 12 | |
| 10+ | 18 | 16 | 15 | 14 | 13 |

Choose a show letter, open **Houston premium tables**, review a preset, and choose
**Use this table**. This changes only that species' class premiums in the current
editor. **Save** persists the selected section. Other species and Special Money
are preserved. No preset applies automatically to any show, including Meat Pen.

## Local preview and checks

```sh
flutter run -d web-server --web-port 8092 --target tool/custom_payback/preview.dart
flutter test --platform chrome test/class_payback_test.dart test/custom_payback_widget_test.dart test/accessibility_color_contrast_test.dart test/payback_report_loader_test.dart
```

Preview uses the actual editor with an in-memory HTTP fixture and no production
connection. It starts with the five reviewed Open Rabbit values; refreshing
resets edits. The SQL tests independently run the real payout report for every
class size 1–30 and all four tables, as well as save validation, authorization,
and default-schedule uniqueness. Run `supabase/tests/custom_payback_ranges.sql`
against a locally migrated test database with pgTAP. All fixtures roll back.

Deployment requires migration `20261111031509_custom_payback_ranges.sql` and the
Flutter web build. The migration introduces an authenticated save RPC but does
not replace any payout data. Apply selected presets separately after reviewing
the appropriate show and section. Do not apply a blanket migration push if the
production migration ledger differs from the checkout.
