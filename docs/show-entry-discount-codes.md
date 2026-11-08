# Show-entry discount codes

Release: 1.00.15. Approved after local review on November 8, 2026.
Production migration applied and calculation/access checks passed on November 8.
The exact migration was applied through the Supabase API because pre-existing
remote/local history differences prevent a blanket CLI push. The filename matches
the recorded production version; older history was not changed.

## Behavior

Show Fees & Payments → Discounts lets authorized show staff add or edit a code,
choose their own code or generate one, label it, and enable/disable it. Each code
saves independently of the surrounding fee dialog. Locked/finalized shows cannot
change codes.

Supported amounts: dollars off per entry, percentage off entry fees, a reduced
entry rate, or an overall dollar/percentage discount per exhibitor for the show.
Code percentages are literal (0.5 means 0.5%). Codes ignore letter case and leading
or trailing spaces.

The cart applies a code to a selected exhibitor. It remains associated with that
exhibitor for that show across checkouts. Multiple accepted codes can be active,
but only the best cumulative savings among codes, volume, and Canada Special
applies. Previously received savings are subtracted; no stacking or retroactive
refund occurs. New savings cannot exceed the current eligible entry fees.

Example: MEMBER20 gives $20 overall. A first $12 entry is free; a later $12 entry
receives the remaining $8, leaving $4 due. Further entries receive no additional
savings from that code. A better per-entry alternative can take over as cumulative
entries grow. Fur, per-show fees, one-time exhibitor fees, add-ons and payment
processing costs are outside the entry discount.

Draft carts calculate again before confirmation/payment. Pending payment quotes
reserve their savings and keep frozen amounts; submitted payments are unchanged.
An active pending attempt must be cancelled/terminal before its reserved savings
are released. Refunds do not automatically restore discount entitlement. Code
edits affect future calculations, not already frozen payments. Zero-total carts
have a server-validated free confirmation path, without contacting a provider.

## Implementation

Migration: `20261108172336_show_entry_discount_codes.sql`.

Private tables have RLS enabled and no direct client privileges. Public RPCs check
show-management/cart-household permissions. Invalid redemption attempts are
limited to 20 per actor in ten minutes. Sorted transaction advisory locks serialize
checkout calculations for the same show/exhibitor. No historical data backfill.

The cart uses authoritative server balances and blocks checkout if pricing fails.
Apply the migration before deploying the client. No provider API changes or new
secrets are required.

## Validation

- `supabase/tests/show_entry_discount_codes.sql`: normalized/random codes, carryover,
  reapplication, cumulative volume, best-discount replacement, independent family
  members, disabled codes, percentage/fixed-rate calculation, fur/other-fee
  exclusions, free confirmation/retries, pending reservations, frozen quotes,
  simulated payment finalization/retries, authorization and private-table access.
- `tool/entry_discounts/test_concurrency.py`: two simultaneous $12 free-confirmation
  attempts against $20 overall. One succeeds; the other must pay $4. Uses temporary
  fixtures in a local Supabase Docker database and removes them afterward.
- Existing Canada Special suite: 9 assertions passed.
- Existing exhibitor-fee suite: 31 assertions passed after mirroring existing
  production fee-setting write policies inside the rolled-back local test
  transaction. The old local fixture had only SELECT permission; the same failures
  reproduced with the original calculator before those policies were supplied.
- Existing exhibitor-fee payment integration suite passed.
- Browser widget tests cover code generation, percentage validation, per-exhibitor
  selection, 390px layout, cart-button contrast under the gradient theme, and a
  failed payment preview preventing checkout. Included in deployment CI tests.
- Flutter analyzer and local web build passed.

All database tests used an isolated local database. Payment completion was
simulated at the database finalization boundary; no real processor charge or
production email was sent.

## Local review

`tool/entry_discounts/preview.dart` is a separate local-only entry point using the
real widgets, cart screen and database RPCs. It rejects a non-loopback Supabase URL.
Provide local-only build defines: SUPABASE_URL, SUPABASE_ANON_KEY,
DISCOUNT_PREVIEW_EMAIL, DISCOUNT_PREVIEW_PASSWORD, DISCOUNT_PREVIEW_SHOW and
DISCOUNT_PREVIEW_CARTS (JSON array of objects with id and label). Never build this
entry point with production credentials or publish it.

The current review server is `http://127.0.0.1:8089/`. Its synthetic show has MEMBER20
($20 overall) and PERENTRY ($3 off per entry), an Alex carryover scenario, and a
Sam/Taylor cart for independent code application. The fixture uses pay-at-show to
exercise confirmation without contacting a payment service.
