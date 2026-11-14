# Show Finances validation

Show Settings → Show Finances is available to staff who can manage entries or
show settings. It records external receipts (Cash, Check, PayPal, Venmo, Zelle,
Other), applies documented credits, displays payment/allocation history, and
exports paid/unpaid exhibitor reports. Recording a receipt does not charge a
payment provider or send email. Unsubmitted carts are excluded.

The database migration maintains one authoritative entries balance per exhibitor.
Payment allocations follow transferred entries using the original checkout
snapshot, preserving receipt totals and original prices. Credits reduce charges;
they are not receipts. Writes are serialized and use idempotency keys. Unclear
historical allocation data fails for review rather than guessing a payment split.

## Tests

Run from the repository root:

```sh
python3 tool/show_finances/test.py supabase_db_ringmaster-show-full-e2e-convention
flutter test --platform chrome test/show_finances_test.dart
flutter test test/print_reports_service_test.dart test/unpaid_balances_report_loader_test.dart test/accessibility_color_contrast_test.dart
flutter build web --no-pub --release --output /tmp/ringmaster-show-finance-release
```

The SQL runner creates and removes a separate temporary database. It does not
modify the container's main database or production. Coverage includes 29 existing
balance checks, 69 new allocation/refund/access/provenance tests, and three two-connection
concurrency tests. Five browser widget tests cover input validation, receipt retry,
credits, mobile keyboard insets, contrast, filters, and history/load recovery.
Ten native tests cover the existing PDF/report loader and contrast behavior.

All these suites and the release web build passed on November 14, 2026.
The combined Chrome run also passed 13 finance, checkout-preview, discount, and
entry-edit tests. The database total is 101 checks including concurrency. A PDF
generation test exceeded the Chrome runner's 30-second timeout; the full PDF
suite passed under the native runner. This is not an end-to-end production payment
provider test. No payment provider integration is changed.

## Local review

```sh
flutter build web --no-pub --release --target tool/show_finances/preview.dart --output /tmp/ringmaster-show-finance-preview
python3 -m http.server 8089 --bind 127.0.0.1 --directory /tmp/ringmaster-show-finance-preview
```

The preview uses the real screen with an in-memory sample gateway. Reload resets
its balances. It cannot charge, email, or change live records; PDF export is tested
separately. Browser review confirmed readable phone controls and a sample receipt
updating the exhibitor and overall balance.

## Deployment

Apply the four migrations in filename order before publishing the application.
They were applied to production on November 14, 2026. Live read checks confirmed
Show Finances loads the show and the corrected balances. A transaction that was
rolled back validated external receipt creation, idempotent retry, a credit, and
zero provider fees against the real production schema.

Separately authorized corrections to the reported Gold Jacket balances were
applied and audited, preserving original receipts. Pius's six recreated Youth
entries were linked to their exact original paid Open checkout items; an obsolete
unpaid $5 cart line absent from the completed checkout was zeroed with its prior
state retained in the audit. The result is six entries, $30 paid, and $0 due.
Sibling balances, original checkout snapshots, and receipt rows were verified
unchanged. Lindy and Sara remain at $0 due.

Open/Youth moves update entries in place and retain original prices and payments.
A database guard prevents clearing or replacing existing checkout links. The
remove confirmation directs staff to Move when retaining an entry's payment.
Do not run a blanket historical balance backfill: ambiguous transfers need review.

Post-deployment advisors: added exhibitor foreign-key indexes. Private tables
intentionally have no client RLS policies or grants. Public finance RPCs use
explicit show authorization before accessing the private ledger.
