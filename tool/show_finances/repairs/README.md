# Reviewed financial corrections

## Southern Adirondack, November 20, 2026

The owner authorized $4 per active class entry and $2 per active fur entry,
excluding unpaid scratched and removed entries. The live database had no show
payment records, payment sessions, discounts, or finance credits. Submitted
zero-price cart quotes had been marked paid and were retained by the normal
checkout freeze. Later fee settings did not repair those historical quotes.
The audit does not establish why the original quotes were zero.

The guarded SQL correction was rehearsed against a private full-show snapshot,
then executed on production in a transaction that was rolled back, before the
successful committed execution. Do not rerun it: it rejects an existing repair,
changed entry counts, fee changes, payments, sessions, discounts, or credits.
The SQL file must be enclosed in an explicit transaction.

Original cart rows and balance snapshots are retained in the private
`cart_quote_corrections` table. Original entry payment flags are retained in
finance allocation audit events. Original cart items, entry IDs, ownership, and
checkout provenance were preserved. Corrected quote items exclude the scratches
and removed items present at correction time. Like other submitted quotes,
this is a frozen financial baseline; it is not ongoing automatic repricing.

The allocation reader uses this reviewed baseline for later transfers. The
replacement-credit reader uses the same item membership, so excluded original
cart items cannot invalidate a legitimate paid-entry replacement credit.
Ordinary checkouts retain their existing pricing and allocation behavior.

Verified outcome:

- 148 active exhibitors with positive balances.
- 3,145 class entries at $4 = $12,580.
- 31 fur entries at $2 = $62.
- Total balance due: $12,642; recorded payments and credits: $0.
- All 3,176 active entry payment flags are unpaid.
- Repeated production balance maintenance reproduced those totals.
- 198 financial SQL assertions and the existing concurrency suite passed.
- Actual check-in and unpaid-report loaders/PDF builders passed full-show tests.
- Every report row was reconciled to an independent active-entry calculation.
- Every printed check-in amount, unpaid subtotal, and unpaid balance matched.
- Corrected check-in PDF: 288 physical pages; unpaid balances: 13 pages.
- No report emails or payment-provider charges were sent.

The private audit table intentionally has RLS enabled without client policies or
client grants. The resulting informational RLS/no-policy advisor notice reflects
the intended deny-all client access.

Private live snapshots and generated PDFs are excluded from source control.
The opt-in report rehearsals take local fixtures via `CHECKIN_REPORT_FIXTURE`
and `UNPAID_REPORT_FIXTURE`, with corresponding `*_REPORT_OUTPUT` paths.
