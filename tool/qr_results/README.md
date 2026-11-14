# Breed QR results regression

Printed breed links are intentionally account-free. They identify one show,
section, and breed. The writer supplies their name and phone before saving.
Staff reporting endpoints remain private; QR responses omit exhibitor contact
information and carry species, coops, recognition, and awards in one projection.

The database save path validates the writer and published/unlocked show, then
serializes saves for the breed/section. First BOB starts a 20-minute deadline.
Resaving/removing BOB cannot reset it. Breed and fur saves, bulk judge changes,
and QR correction requests reject expired QR edits. Staff result corrections remain available.
Existing BOB award timestamps and legacy lock records are honored.

Run against the synthetic local fixture (all DDL/data changes roll back):

```
python3 tool/qr_results/test.py supabase_db_ringmaster-show-full-e2e-convention
flutter test --platform chrome test/qr_results_species_widget_test.dart test/qr_results_save_widget_test.dart test/accessibility_color_contrast_test.dart
```

Deploy the migration before the frontend that calls the new QR RPCs. Existing
printed links require no changes. Do not grant public access to staff reporting
functions to restore QR access.

## Verification (November 14, 2026)

- Synthetic database regression suite passed with all changes rolled back.
- QR scan/name-and-phone widget tests passed (2 tests).
- Phone-width QR save tests passed (3 tests): BOB attribution, expired save,
  and anonymous fur eligibility/placement.
- Accessibility contrast tests passed (4 tests); targeted Flutter analysis and
  `git diff --check` passed.

The installed Flutter browser test host required a temporary missing `#play`
control workaround outside the repository. It was restored after testing.
The final save suite ran separately using Chromium; combined runs intermittently
closed before loading a suite. No test assertions or app behavior were bypassed.

Production release: 1.00.32. Apply the QR migration before deploying the web build.
