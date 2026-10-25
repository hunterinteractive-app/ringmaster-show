# Convention token sale

The public sale page is `https://show.ringmasterone.com/#/convention-sale`.
Super Admin → **Convention Token Sale** controls the venue, center point, radius,
date, local hours, time zone, and all three bonuses. The same settings can be
updated for the next convention each year. Changes are protected against
overwriting another administrator's newer edits.

The initial schedule is October 26, 2026, midnight through 11:59 PM Pacific at
Reno–Sparks Convention Center, 4590 S Virginia St, Reno, Nevada. The center is
39.4861, -119.7911 and the radius defaults to one mile. The server stores the end
as exclusive midnight on October 27, so the last minute is included. Full-day
schedules follow the selected IANA time zone across daylight saving changes.

| Purchase | Current regular price | Convention bonus | Total |
| --- | --- | --- | --- |
| 1 show token | $50 | 1 token | 2 tokens |
| 4 show tokens | $150 | 2 tokens | 6 tokens |
| 12-month unlimited | $250 | 2 months | 14 months |

Prices come from the regular Stripe Payment Links used by the public pricing
page, rather than the separate introductory-price links. These prices currently
include tax. The checkout retains existing automatic-tax behavior and requires
an active tax registration if that behavior is enabled. This feature does not
create registrations or change tax settings.

## Using the controls

- Enter the venue name and address. Pan/zoom the map and tap to set the center,
  or enter coordinates. The OpenStreetMap lookup button opens the venue search
  in a separate page; entering an address alone does not move the center.
- Drag the radius slider (0.1–25 miles). The circle updates while dragging and
  the map fits the area when the drag ends. Coordinate edits also update the pin.
- Choose the date and convention time zone. Full-day mode includes midnight
  through 11:59 PM; turning it off exposes separate start/end date and time controls.
- Edit bonus tokens for each token package and bonus months for unlimited.
- Save, preview the page with checkout disabled, and copy the public sale link.
- Turning off the sale pauses new eligibility checks. Previously issued offers
  and already-started payments retain their original terms.

An announcement appears on the sign-in and show-list screens while an enabled
sale is upcoming or open. Existing check-in, judging, and demo routes are unchanged.

## Eligibility and fulfillment

The buyer signs in with a verified email and explicitly presses the location/
purchase button. The browser requests a single high-accuracy location reading.
There is no background location subscription. The server requires a reading at
most 60 seconds old, an accuracy radius no greater than the smaller of 250 meters
or half the eligible radius, and the entire reported accuracy circle inside the
sale area. Failure or denied permission directs the buyer to the booth; it does
not automatically grant a bonus. Self-reported browser locations can be spoofed,
so this is a deterrent to casual link sharing, not guaranteed proof of attendance.

Each successful location check creates a private offer for that verified user,
package, canonical Stripe Price, currency, bonus, and sale revision.
Precise visitor coordinates are not saved. The offer can create one checkout
within 15 minutes, or before the sale closes, whichever is earlier. Stripe allows
30 minutes from verification to submit payment. Delayed payment methods can
settle later; fulfillment waits for paid confirmation.

Stripe metadata binds the offer to the checkout and the user who was verified.
Forwarding the checkout cannot redirect the credits to a friend's account.
Every separate qualifying purchase earns a bonus. Webhook retries, duplicate
deliveries and concurrent purchases are handled with row locks and a single
transaction for the balance, offer, and processed-session ledger. Tax-inclusive
prices are verified against the total, exclusive prices against the subtotal.

Unlimited purchases add 12 plus the configured bonus calendar months from the
later of payment confirmation and existing expiration. Existing lifetime access
is preserved. The confirmation page and purchase email include the awarded offer.

## Deployment

1. Apply the new `convention_token_sale` migration to the Show project only.
   It adds private settings/offer tables and restricted public RPCs; it does not
   rewrite existing user balances or historical purchases.
2. Deploy `convention-sale-checkout` with `verify_jwt=false`. The catalog is
   public; checkout authenticates the user's JWT with `auth.getUser`. Include its
   handler, `_shared/convention_sale.ts`, `_shared/request_fetch.ts`, and the
   function Deno configuration.
3. Deploy the updated `stripe-license-webhook`, retaining its existing signature
   secret, payment processing behavior, and email dependencies.
4. Keep `checkout.session.completed` and add
   `checkout.session.async_payment_succeeded` on the **license** webhook endpoint.
5. Deploy the normal Flutter entry point `lib/main.dart` (generation 1.00.07).
   Never deploy the local preview entry point.
6. Verify the anonymous catalog/settings, failed unauthenticated checkout,
   sale route, and Super Admin settings. No live charge is necessary for these checks.

The endpoint reuses `STRIPE_SECRET_KEY`, `SUPABASE_URL`, and
`SUPABASE_SERVICE_ROLE_KEY`. Existing purchase receipts use the existing license
webhook and Resend configuration. Use a restricted Stripe key with the required
read/payment permissions when managing keys; never put a secret in the client.

Optional deployment overrides:

- `CONVENTION_SINGLE_SHOW_PAYMENT_LINK_ID`
- `CONVENTION_FOUR_SHOWS_PAYMENT_LINK_ID`
- `CONVENTION_UNLIMITED_PAYMENT_LINK_ID`
- `CONVENTION_SITE_ORIGIN` (defaults to the Show site's HTTPS origin)

## Verification and local preview

`tool/convention_sale/test_database.py --container <local supabase_db_ container>`
creates and removes an isolated database. It checks permissions, geography,
date/time changes, daylight saving time, bonuses, offer snapshots, duplicates,
renewals, lifetime access and receipt isolation, then delivers eight distinct
purchases twice concurrently and verifies exactly sixteen credited tokens.

The Deno tests cover authentication, canonical price/account binding, tax
registration checks, request retries, paid-session validation and email content.
The Flutter test covers the one-day schedule and all three offer totals.

For a local interactive preview using only an in-memory settings fixture:

```sh
flutter build web --release --pwa-strategy=none \
  --target tool/convention_sale/preview.dart --output /tmp/ringmaster-convention-sale-preview
python3 tool/convention_sale/preview_server.py /tmp/ringmaster-convention-sale-preview
```

Open `http://127.0.0.1:58620`. This preview cannot process payments. Its settings
do not reach Supabase. The Super Admin map uses normal interactive
[OpenStreetMap tiles](https://operations.osmfoundation.org/policies/tiles/) with
visible attribution and a browser referrer, without bulk downloads or public
geocoding API calls.
