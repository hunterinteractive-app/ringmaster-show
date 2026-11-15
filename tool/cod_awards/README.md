# COD breed awards

Release 1.00.36 permits BOV, BOSV, BOB and BOSB for any COD breed or
variety, including rabbit and cavy results. These are show-level awards;
they do not make an entry recognized. Normal placement, result-status,
variety-source, opposite-sex and duplicate-winner checks still apply.
COD rabbit breed winners skip the group-award prerequisite because COD group
awards remain unavailable. BOV/BOSV is still required where applicable.

COD entries remain excluded from legs, final awards (including reserves and
Best of the Best Opposite), and the eligible final-award reporting population.
Recognition continues to use the section judging date, with show start as the
fallback. No recognition timelines or existing results are changed.

The production Velveteen Solid timeline becomes recognized December 1, 2026.
Broken remains COD. Other CODs retain their own recognition timelines; December 1
is not a universal automatic recognition date.

Regression commands:

```
python3 tool/cod_awards/test.py supabase_db_ringmaster-show-full-e2e-convention
python3 tool/qr_results/test.py supabase_db_ringmaster-show-full-e2e-convention
flutter test test/cod_award_eligibility_test.dart test/recognition_timeline_test.dart test/rabbit_results_rules_test.dart test/cavy_results_rules_test.dart test/report_population_regression_test.dart test/sweepstakes_cod_population_test.dart
flutter test --platform chrome test/qr_results_save_widget_test.dart test/accessibility_color_contrast_test.dart
```

Both SQL runners only accept the synthetic local fixture and roll back their
changes. QR tests flush deferred constraints before resetting the writer role.
Apply the database migration before deploying the frontend. Production migration
version matches the timestamp assigned by Supabase when applied.
