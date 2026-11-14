# Houston registration requirements and shared contests

Release 1.00.29 adds a checkout form for shows owned by Kyle's account in the
Houston Livestock Show and Rodeo club. Every youth exhibitor in a cart must
provide school name, city, and a two-letter state (TX initially). The mixed Cavy
show uses the entry's Youth section, not the overall show name. Youth contest
registrations also require school details. Open-only entries need the agreement
but no school fields. Shows outside this owner/club scope are unchanged.

The agreement is unchecked and links to the supplied 2027 V2 handbook and the
Houston website. Server-side guards cover online payment quotes, free checkout,
and pay-at-show submission. Private records retain the authenticated accepting
user, timestamp, exact agreement version/text/links, school snapshot, and cart
signature. A changed cart requires another acceptance. Pending payment retries
can record consent without editing the payment or its charges. No historical
acceptance is fabricated. Private tables intentionally have RLS enabled and no
client table grants/policies; household-authorized RPCs provide the form access.
Malformed carts referencing another household’s youth exhibitor are rejected
before names or school details are read, saved, or accepted for checkout.

The existing Rabbit/Cavy Costume and Showmanship offerings accept Youth Cavy
animals. They appear in the Cavy entry flow, use the same offering IDs and
limits, and keep all registrations/check-in/results in the Youth Breeding Rabbit
portal. The charge remains in the originating cart; no second Rabbit cart or
extra show fee is created. The rabbit portal also accepts completed Youth Cavy
entries. Another unpaid cart, Open-only cavy entries, other households, and
unlinked shows do not qualify. The host contest controls its registration window,
age date, capacity, fees, and publication state.

## Validation

```sh
python3 tool/houston_registration/test.py supabase_db_ringmaster-show-full-e2e-convention
flutter test --platform chrome test/cart_registration_requirements_test.dart test/show_addons_widget_test.dart test/cart_payment_preview_test.dart
flutter test test/accessibility_color_contrast_test.dart
flutter analyze --no-pub
flutter build web --no-pub --release --pwa-strategy=none
```

The SQL runner clones only the local rehearsal schema into a disposable DB,
creates synthetic fixtures, and drops the DB afterward. It never uses a hosted
connection, invokes a payment provider, or sends email. On November 14, 2026,
202 database checks plus the add-on deletion integration checks passed, as did
17 browser widget tests and four contrast checks. Full analysis and the release
build passed. The isolated preview was visually inspected with the production
gradient/dialog themes at narrow width, including missing-field errors.

```sh
flutter run -d web-server --web-port 8096 --target tool/houston_registration/preview.dart
```

The preview's Save callback is local only and never records a real agreement.

## Deployment

Hosted migrations `20261114074227_houston_checkout_requirements` and
`20261114074237_linked_youth_contest_registration`, and
`20261114074909_guard_houston_school_household` were applied on November 14.
Read checks confirmed all four Kyle-owned Houston shows are covered, both shared
contests appear in the Cavy catalog with the Rabbit host, and zero real consent
records were created by verification. The entry opening remains November 15 at
00:01 America/Chicago. Security advisor findings for the new private tables were
informational notices about intentionally absent client RLS policies.
