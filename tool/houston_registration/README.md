# Houston registration requirements and shared contests

Release 1.00.29 adds a checkout form for shows owned by Kyle's account in the
Houston Livestock Show and Rodeo club. Every youth exhibitor in a cart must
provide school name, city, and a two-letter state (TX initially). The mixed Cavy
show uses the entry's Youth section, not the overall show name. Youth contest
registrations also require school details. Open-only entries need the agreement
but no school fields. Shows outside this owner/club scope are unchanged.

The agreement is unchecked. Release 1.00.37 links the supplied **2027 Open Show
Indemnity.docx** exactly as received, including every page and signature section.
The SHA-256 in its immutable URL and `indemnity_document.json` identifies the
original bytes. The checkbox refers to the full Release of Liability and
Indemnity; it does not replace the document with a summary. This changes the
agreement for all four Kyle-owned Houston shows, including Open and Youth.

Acceptance snapshots retain the document title, original filename, URL, SHA-256,
and extracted full text. Earlier handbook acceptances remain historical records
and are not converted into indemnity acceptances. A new checkout must accept
the current version. Completed entries are not retroactively marked accepted
and no acceptance is created by deployment. The link opens the original Word
file; this change retains the checkbox flow and does not collect the document's
separate exhibitor or guardian signatures.

Server-side guards cover online payment quotes, free checkout,
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

On November 16, Rabbit Judging (Individual) and Rabbit Judging (Team) were also
linked to the Cavy show. Their existing offerings remain under Youth Breeding
Rabbit, at $5 per individual and $20 per team, with Junior/Intermediate/Senior
divisions and the existing age rules. These judging contests do not require an
animal entry or animal selection; sharing them preserves that setting in both
portals. Costume and Showmanship still require an eligible Youth animal.

## Validation

Release 1.00.31 replaces the school-state text box with a searchable dropdown
of US states and DC. Typing a state name or abbreviation filters the options;
TX remains the default and existing selections are preserved. The form saves
two-letter codes and rejects partial or unrecognized values. Browser tests
cover filtering, each child's selection, retained values, invalid input, and
menu contrast; the actual checkout dialog was inspected at 390px width.

Release 1.00.30 displays School Information in Entry Management → View Exhibitor.
The read-only section includes school name, city, and state. Its RPC requires
the existing entry-management permission for the requested show and returns
only submitted checkout records belonging to that exhibitor's household.
An abandoned draft or another show's record cannot replace the school's details.
The Rabbit host can also read a registered Cavy contestant's school from that
contest's original submitted cart; other Cavy children remain outside its scope.
Open-only exhibitors and shows without school collection do not show the section.
Missing data and failed loads have distinct messages; failed loads offer Retry.

The staff-reader additions pass 16 authorization/data-isolation checks in the
disposable SQL suite (218 checks total, plus add-on deletion integration).
Run `flutter test --platform chrome test/exhibitor_school_information_test.dart`
for the actual View Exhibitor sheet at phone width, including contrast and errors.
The synthetic visual preview is `tool/houston_registration/preview_school.dart`.

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

For the indemnity update, deploy the web document and new link UI first, verify
the hosted DOCX SHA-256 against the supplied original, then apply
`houston_original_indemnity_agreement`. Older app versions also receive the
document URL through their existing handbook-link field so their agreement
points to the same original during rollout. New clients label it correctly as
the Release of Liability and Indemnity.

Hosted migrations `20261114074227_houston_checkout_requirements` and
`20261114074237_linked_youth_contest_registration`, and
`20261114074909_guard_houston_school_household` were applied on November 14.
Read checks confirmed all four Kyle-owned Houston shows are covered, both shared
contests appear in the Cavy catalog with the Rabbit host, and zero real consent
records were created by verification. The entry opening remains November 15 at
00:01 America/Chicago. Security advisor findings for the new private tables were
informational notices about intentionally absent client RLS policies.

Migration `20261114092521_staff_exhibitor_school_information` adds the staff
reader. Hosted read checks confirmed the owner can call it and anonymous users
cannot; private tables remain inaccessible directly. No production records were
created or changed during school-display verification.

The indemnity migration was applied as `20261116180918` on November 16, 2026,
after release 1.00.37 passed CI and the live DOCX matched the supplied original
byte-for-byte. Hosted reads confirmed the four scoped shows use the new version.
The local suite passed 225 database checks plus deletion integration, seven
checkout browser tests, and four contrast checks. Security advisor counts were
unchanged.

Migration `20261116183341_honor_shared_contest_animal_requirement` preserves the
configured animal-entry requirement when a contest is shared. The two live
judging links were inserted separately as show configuration, guarded by the
verified Kyle owner, Houston club, host/source show IDs, and offering names/IDs:

- Individual: `38771a52-312d-47e6-99df-0d4c52005797`
- Team: `3a08ca6e-5273-4f58-b27f-40be52118ef4`
- Host: `275bbfe9-6ef7-4c86-b914-23afee7ceffc`
- Source Cavy show: `62c1a1ea-da4d-4ac5-a23e-065d14dce251`

The authenticated live Cavy catalog returned both judging contests as open,
alongside Costume and Showmanship, with their original fees and Rabbit host.
The isolated suite passed 241 database checks plus deletion integration. The 16
new judging checks cover standalone entry from both portals, team registration,
fees, age/division rules, household authorization, duplicate prevention, local
checkout, and the single Rabbit roster. Security advisor counts were unchanged.
No production registrations, agreements, or payments were created for testing;
this server/configuration update does not require a new web app version.

## Shared category capacity per session

Release 1.00.38 adds **Maximum entries per category per session** under Contest
Setup → Categories when the contest has sessions. The optional
`category_session_capacity` defaults to 0 (unlimited). It counts all exhibitors
and all linked entry portals together for the canonical offering, category, and
session. It is separate from the existing per-exhibitor category limit, full
contest capacity, and session capacity.

On November 16, migration `20261116185000_contest_category_session_capacity`
was applied and Kyle's existing Rabbit/Cavy Costume Contest
(`d7d7a597-8964-4ef3-aad6-556ccd8de6b6`) was set to 20. Each of the five categories
has 20 places on March 6 and a separate 20 on March 8. The Rabbit and Cavy
portals share those places through the original offering; each session retains
its 100-place total and the existing one-registration-per-exhibitor limit.

Submitted registrations and active payment reservations hold places. Drafts in
other carts do not reserve places indefinitely; checkout rechecks availability.
Offering locks serialize competing checkouts. The isolated suite passes 266
database checks plus deletion integration and a two-checkout race proving only
one can take the twentieth place. The 25 new database checks cover shared counts,
stale drafts, payment holds, category/session isolation, and disabled limits.
Twenty-five model/widget/contrast checks pass, and the actual editor's normal
and validation states were visually inspected at 390px width. Security advisor
counts were unchanged. No live registrations or payments were created to test.

The isolated editor preview is
`tool/houston_registration/preview_contest_capacity.dart`.
