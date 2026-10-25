# Agreement persistence

The show-list agreement belongs to the signed-in account, independently of
household selection or support impersonation. Read its receipt from `profiles`
on navigation. Concurrent checks share one pending dialog. No browser-only flag
substitutes for a saved server receipt.

The dialog closes only after an account-bound save returns the matching receipt.
On an uncertain write response, read the receipt before asking the person to
retry. A failed save stays in the dialog with the checkbox preserved and an
inline retry message. A failed status read offers a retry instead of requiring
agreement again. Agreement writes leave the existing display name and email alone.

Root owns the normal sign-in transition; the login screen does not push another
show list in that case. Same-account token refreshes and repeated sign-in events
do not remount the show list under a pending dialog. Other login destinations,
including returning to the convention sale, retain their own navigation.

The private `preserve_profile_acceptance` trigger protects existing receipts and
their original times from older or null submissions by older open tabs. It does
not create or backfill acceptance. RLS still limits profile writes to the account.
The trigger has no browser execution grants and runs without elevated privileges.

When publishing a genuinely new policy, update `LegalConfig`'s current version
and ordered version list and extend the migration trigger's matching list with
a new migration. Wording corrections without changed data practices need not
change the acceptance version. This fix does not alter either current policy ID.

Verification:

- `flutter test test/legal_acceptance_service_test.dart test/accessibility_widget_test.dart`
- `flutter test --platform chrome test/legal_auth_navigation_test.dart` in browser CI
- `python3 tool/legal_acceptance/test_database.py --container <local supabase_db_ container>`

The database command creates and removes a separate disposable database and
uses no hosted account data. The browser test uses fixture authentication,
mocked profile storage and an actual token-refresh event; it accepts no real
person's agreement. Never click a real user's agreement as part of verification.
