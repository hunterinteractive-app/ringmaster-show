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

## Automatic scratch/replacement offsets

Migration `20261118030022_automatic_scratch_replacement_offsets.sql` automatically
offsets a staff-added replacement against a fully paid, unrefunded checkout entry
that was scratched. Matching stays within the same exhibitor, show section,
species, and class/fur entry type. Each original covers at most one active
replacement. It uses the lesser of the original discounted charge and the new
discounted charge; original payment receipts and checkout links are retained.

The migration records its activation time. Both the scratch and replacement
addition must be after activation. A replacement can be added after the scratch,
or up to 15 minutes before it to support add-then-scratch editing. Entry closing
does not prevent staff replacements. These offsets do not retroactively alter
historical balances or duplicate Trisha's separately authorized $10 credit.

Unscratching the original restores the charge while both animals are active.
Scratching/removing the replacement removes its offset. Pair IDs, amounts, and
changes appear in the private financial audit. Refunded, partially paid,
reassigned, malformed, test, and commercial originals are excluded; new online
cart checkouts are not covered by this staff/manual-addition patch. A scratch by
itself does not issue a refund or create spendable credit.

Local verification on November 17: 170 checks passed (29 legacy, 69 finance,
25 summary, 42 replacement, and five concurrent-write scenarios). This includes
discount cent rounding, closed-show replacement editing, report agreement,
payment preservation, duplicate-credit rejection, and simultaneous additions
competing for one scratch. The fixture uses the production rabbit/cavy enum.
Tests run in a disposable local database. Applied to production November 17, 2026
at 10:00:22 PM Eastern (November 18 at 03:00:22 UTC). Before/after production
balance totals were unchanged. The calculator is inaccessible to client roles.

Post-deployment advisors: added exhibitor foreign-key indexes. Private tables
intentionally have no client RLS policies or grants. Public finance RPCs use
explicit show authorization before accessing the private ledger.

## Check-in sheet timeout fix (November 20, 2026)

`20261121012054_checkin_current_balances_read_only.sql` changes the interactive
`report_checkin_entries` RPC to read maintained balances using the same selection
as Show Finances. Previously every report page invoked the legacy balance writer,
whose updates triggered current payment allocation again and timed out. Entry,
payment, and credit writes already maintain the authoritative balance; generating
a report does not need another refresh. Submitted-cart fallback totals are summed
once when no authoritative entry balance exists. Contact/balance access is limited
to authorized show staff and server workers. The return shape is unchanged.

The isolated SQL suite now includes 19 check-in assertions (184 SQL assertions
plus five concurrency checks overall). It verifies immediate payment/credit
freshness, entry changes, filtering, fallback carts, access, and unchanged
balances/audit records after repeated reads.

The opt-in PDF rehearsal runs the actual combined check-in screen and builder
against a captured read-only query result, with native save and HTTP replayed:

```sh
CHECKIN_REPORT_FIXTURE=/tmp/checkin-fixture.json \
CHECKIN_REPORT_OUTPUT=/tmp/check-in.pdf \
flutter test test/checkin_full_report_rehearsal_test.dart
```

The JSON snapshot has `show` (one-row list), `sections`, `exhibitors`, `entries`
(id/animal_id/is_fur/class_name), `coop`, `wave` (schedule object), and `report`
(the complete replacement RPC query result). Keep snapshots outside Git because
they contain exhibitor contact details. This rehearsal cannot send email or write
production data. Database function tests run separately in the isolated SQL suite.

Southern Adirondack validation: 3,176 active entry rows, eight sections, 148
exhibitors, 288 PDF pages. The replacement SELECT ran in approximately 132 ms on
the production data; the PDF rehearsal took approximately two seconds after
snapshot capture. All 148 printed balances matched current Show Finances totals,
and the printed entry totals summed to 3,176. These are database/render timings,
not an end-to-end browser download measurement.
