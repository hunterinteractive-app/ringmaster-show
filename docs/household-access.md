# Household access

Each login retains its own identity and staff permissions. `AppSession.effectiveUserId` continues to drive show administration, role checks, licenses, and legal acceptance. Only exhibitor data screens use `AppSession.householdOwnerUserId`.

Owners create invitations to a login email in Account Settings → Household Access. The recipient signs in with that verified email and accepts in the same screen. Invitations expire after seven days. Saving a changed email for an eligible active exhibitor sends an invitation email through `household-send-invitation`. Manual invitations use the same endpoint. Adults and youth aged 14 or older with a recorded birth date are eligible; groups, younger youth, and youth without birth dates are not. The backend enforces eligibility during invitation and acceptance. Email delivery uses a stable provider idempotency key and private delivery bookkeeping. Failures preserve the saved exhibitor and show instructions to retry. Opening the app does not send invitations to existing contacts. Accepted members can select their personal household or the shared household, including exhibitors, animals, entries, carts, and past exhibitor reports. No records are merged or renumbered. Only the original owner can invite into that household; members can leave and owners can revoke access.

Membership lives in a private schema, with no client table grants. Public RPCs validate the authenticated identity. Contact email on an exhibitor is not an access credential. Revocation is evaluated against current database membership, not a cached JWT claim. Payments attribute the initiating actor to the verified login, while entries retain the cart household owner. Existing deadlines, breed/species validation, and payment finalization guards remain in place.

## Deployment

1. Apply `20260913221718_household_access.sql` to the intended backend. It aborts if existing checkout authorization clauses have changed; inspect and reconcile rather than removing the guards.
2. Apply `20260913231444_hide_inactive_exhibitors_from_account_view.sql`.
3. Deploy `payment-quote-preview`, `square-create-payment`, and `square-payment-attempt-status`, including their shared household helper. Also deploy `household-send-invitation` with `RESEND_API_KEY` and `RESEND_FROM_EMAIL`.
4. Deploy the Flutter app.
5. Verify with two distinct test logins: owner invitation, recipient acceptance, switching households, editing an animal, cart checkout, report download, revocation, and independently assigned staff rights. Do not charge real cards as a test.

The existing localhost Flutter preview uses the configured hosted backend. The invitation workflow requires the backend migration; frontend hot reload alone does not enable it.

## Validation

- `flutter test --no-pub test/household_session_test.dart test/account_exhibitor_welcome_test.dart`
- `flutter analyze --no-pub`
- Deno check of the three changed checkout endpoints using the checked-in lockfile.
- `supabase/tests/household_access.sql` uses synthetic accounts and rolls back its fixtures. It covers owner access, pending/accepted/expired invitations, unauthorized acceptance/revocation, shared animal edits and carts, separate show administration, immediate revocation, retained personal ownership, and API/table privilege restrictions.
- Migration and SQL tests validated in an isolated local database. Security advisors reported no household-related findings. Existing unrelated baseline advisories remain outside this change.

Accounts with two or more active exhibitors see an announcement once per login on each browser, with a shortcut to Household Access. The household owner sees it; shared members and support/demo sessions do not.
