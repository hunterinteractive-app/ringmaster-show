# Other Reports CSV downloads

Close Show/Reports V2 → Reports & Distribution → Other Reports now offers
Download CSV alongside the existing PDF download. The option is available to
all users with access to this report screen; it does not use the BBOS, wave,
or one-time exhibitor fee allowlist. Existing access restrictions on the print
pack and Michelle's special report still apply.

All eleven standard menu reports are covered. CSV reads use the existing PDF
data loaders and the signed-in user's Supabase client. Existing artifacts retain
their section scope; when no artifact exists, enabled show sections are used.
Unpaid balances retain their existing whole-show behavior. Downloads read current
data and do not modify stored PDFs, generate certificates, finalize shows, or
send email. Print pack exports require the same generated source reports as the
PDF pack, and include separate Result and Leg records.

Each CSV is a rectangular UTF-8 table with a BOM, quoted fields, and numeric
amounts in currency units. Section details replace repeated aggregate totals
where appropriate to avoid double-counting. Labels honor the selected contents,
eligibility, and sort order. The browser exporter uses a typed byte buffer.

Validation: `other_reports_csv_test.dart` covers mappings, paging,
deduplication, exact section scope, permission failures, and currency units.
`other_reports_csv_web_test.dart` checks actual browser download bytes and
ordinary-user button visibility. Existing closeout screen and special CSV
tests also pass. No database or report-worker deployment is required.
