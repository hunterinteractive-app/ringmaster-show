# Control-sheet scan pilot

The report and scan review are visible only to super admins. Both scan RPCs
also require an authenticated super admin; a secretary or anonymous caller
cannot use the save endpoint. Support-mode screens cannot submit scans.

In Results Entry, open **Scan control sheets (pilot)**, upload sheets, resolve
red conflicts, and confirm yellow review items. **Save reviewed results**
validates against the current show and opens a confirmation naming the show
and entry count. **Back to review** makes no changes. **Confirm and save**
records the reviewed placements, NP, specials, scratches, No Show, and DQs.
Unmarked and skipped entries remain unchanged. Results Entry refreshes after
the batch succeeds. Existing conflicting results require correction through
normal Results Entry.

`control_sheet_scan_snapshot` captures the selected sections before validation.
`save_control_sheet_scan` acquires the same breed locks as normal Results Entry,
checks the snapshot again, and saves the entire batch in one transaction using
`save_results_entry` and `set_entry_scratch_state`. A failed row rolls back the
batch. A retry whose results are already saved makes no additional writes.
Locked shows cannot save. Review edits remain available if saving fails.

Validation:

```sh
flutter test test/control_sheet_scan_test.dart test/accessibility_color_contrast_test.dart
flutter test --platform chrome test/control_sheet_pilot_access_web_test.dart test/qr_results_save_widget_test.dart
python3 tool/control_sheet_scan/test.py supabase_db_ringmaster-show-full-e2e-convention
```

The database runner accepts only the local synthetic full-e2e database and
rolls back all fixtures, function changes, results, and audit events. It covers
super-admin enforcement, every outcome, saved awards and staff attribution,
repeat imports, stale snapshots, cross-show sections, locked shows, and batch
rollback for invalid rows and duplicate placements. The phone widget test
covers cancellation, save failure/retry, and controls disabled while saving.
