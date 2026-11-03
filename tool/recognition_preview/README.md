# Dated recognition preview (local only)

This entry point uses the real Super Admin catalog/status screens against a
separate local Supabase database. It refuses non-local browser/backend URLs.
It does not deploy, send email, or modify production.

## Start

1. Start the existing local Supabase project
   `ringmaster-show-full-e2e-convention` (API port 55321).
2. Apply pending application migrations **to that local database**, including
   `20261103055857_catalog_recognition_timelines.sql`.
3. Run `python3 tool/recognition_preview/prepare.py`. This creates a synthetic
   local administrator, sample catalog transitions, and a temporary define file.
   Never commit the generated define file. The fixture uses only the named local
   Docker stack and localhost API.
4. Run:

   ```sh
   flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8087 \
     -t tool/recognition_preview/main.dart \
     --dart-define-from-file=/tmp/ringmaster-recognition-preview-defines.json
   ```

## Review

- Open an example and compare judging dates `2026-11-30` and `2026-12-01`.
- Velveteen Lop Solid becomes recognized; Broken remains COD. Both the breed
  and variety must permit recognition.
- Add a future Retired transition with a reason. Reopen the screen, and preview
  the day before/on its date. Future changes can be cancelled; effective history
  cannot be deleted. Changes overlapping judged results require separate review.
- COD permits class placements, BOV, and BOSV, but no higher awards or legs.
- Existing reports resolve status by section judging date (show-start fallback),
  rather than today's date. Retired subjects cannot be newly entered for a
  retired judging date. Existing saved animals and historical results remain.
- Catalog and animal-editor labels add/remove `(COD)` according to the effective
  status. Stored source names and entry identities are retained for historical
  matching. Status history changes eligibility; it does not rename entries or configure AOV/classification groups.

The sample January 1 COD start dates and any retirement examples are synthetic
test data. No recognition announcements are seeded into production by the
migration. Production scheduling should use the approved dates and source notes.

## Regression checks

Run the recognition timeline pgTAP suite in a transaction against the local
database, along with the existing COD award suite. Relevant Dart tests:

```sh
flutter test test/recognition_timeline_test.dart test/cod_award_eligibility_test.dart \
  test/report_population_regression_test.dart test/sweepstakes_cod_population_test.dart \
  test/report_order_loaders_test.dart test/report_data_reader_test.dart
flutter test --platform chrome test/qr_results_species_widget_test.dart
```

Worker regression: `dart test test/none_shown_club_report_test.dart` from
`worker/closeout_renderer`.
