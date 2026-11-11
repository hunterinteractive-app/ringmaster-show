# Exhibitors without email

Staff can select **No email address** when manually creating an exhibitor. This
creates an unowned provisional record tied to the show; normal postal-address
requirements remain. Existing payment rules are unchanged.

Duplicate suggestions require a matching name plus email, phone, ARBA number,
or street address and ZIP. Staff must confirm the suggested record. This is not
an automatic account claim: later account ownership still requires verified
linking, preserving the existing exhibitor ID, animals, entries, and results.

## Report distribution

Send Results opens a print/mail review when selected exhibitor reports have no
current email. Current blank emails override stale report metadata. The review
can also be reopened from Send Results and Report Delivery Status.

- Prepare a combined PDF of exhibitor reports and legs, or check-in sheets.
- Print/preview or download the packet and download mailing labels.
- Explicitly mark each exhibitor's reports mailed, handed out, or outstanding.
- Printing/downloading does not record delivery. Delivery is tied to report
  generation, so regenerated reports become outstanding again.
- Current contact changes and regenerated source files invalidate old packets.
- Missing contacts fail closed; missing postal addresses are flagged for review.

## Release components

Deploy migration `20261111100021_no_email_exhibitor_delivery.sql`, the closeout
worker (including `python/print_pack.py`), and the Flutter web app together. The
existing scheduled print-pack worker handles these jobs; no new identity or
worker is needed. Existing account-restricted full-show print packs retain their
original restrictions.

## Verification

- SQL: `supabase/tests/no_email_exhibitor_delivery.sql` (transaction rolls back).
- Browser tests: `test/manual_report_delivery_widget_test.dart`,
  `test/manual_exhibitor_information_policy_test.dart`, `test/report_recipient_test.dart`.
- Worker: `python -m unittest test_print_pack.py` in the worker Python directory.
- Local synthetic preview: `flutter run -d web-server --web-port 8093 -t tool/no_email/preview.dart`.
  This preview uses mocked requests and cannot send email or change production.
