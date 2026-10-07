# Contests and Show Add-Ons

All show secretaries and administrators who can manage a show’s settings can
configure these features. They do not use the Houston feature allowlist.
Both are disabled by default. With no available offerings, Enter Show continues
directly to the existing cart.

**Contest Settings** appears in Show Settings, with **Show Add-Ons** immediately
below it. Each contest has a name, instructions, optional entry fee, availability
switch, and an independently configurable animal-entry requirement. The
requirement applies to the same exhibitor in the same full show, including an
animal being checked out in the current cart. Scratched or removed animals do
not qualify. It is checked again when checkout starts.

Contest Setup offers 21 editable templates, grouped as Individual, Teams,
Projects, and Applications. Royalty is Individual. Secretaries can search templates,
start with a custom contest, or duplicate an offering. Templates are general
starting points inspired by Houston, ARBA, ISRBA, and PaSRBA contest types; they
are not official rulebooks. Names, divisions, questions, age rules, and awards
remain editable. Applying a template preserves fee, availability, and registration
dates and does not save or publish anything.

Optional configuration includes individual/team/project format; per-exhibitor and
category entry limits; overall/session capacities; divisions and age ranges using
show start, show end, or a custom cutoff; team size, alternates, oldest/all-member
age policy and individual-contest prerequisites; multiple animal roles using
entered, exhibitor-supplied, or organizer-provided animals; sessions, check-in and
material deadlines; and approval status. A team coordinator attests to permission
and registers the roster together. Each project or team is one registration and
one fee. Animals selected from the show must belong to that exhibitor; references
are revalidated at checkout. No extra animal entry is created by a contest.

Questions support short/long text, numbers, dates, checkboxes, dropdowns,
multiple selection, web/video links, and private PDF/PNG/JPEG uploads up to 10 MB.
Questions can depend on category or division, and text limits are configurable.
Incomplete applications can be saved as drafts and resumed from the same cart.
Drafts do not create a fee or reserve capacity. Required details are enforced when
adding a registration and again at checkout. Submitted application edits and
cross-household invitation workflows are not part of this coordinator-based flow.

**Manage Contests** has Registrations, Check-In, and Results views with contest,
division, category, session, and name filters. Secretaries can accept, hold,
waitlist, or decline registrations and check contestants/teams in separately from
payment and animal check-in. Optional walk-up registration looks up an existing
exhibitor number and creates the normal outstanding balance, even after online
registration closes. It does not issue a charge or mark a paid fee as collected.
Capacity is checked when registration is saved and again at checkout; other
households' ordinary carts do not reserve places. Waitlist status is a manual
secretary review status, not an automatic queue or promotion mechanism.

Results use manual places, named awards, ribbon ratings, finalist/callback,
absence, withdrawal, and disqualification. Unique places are enforced within
contest/division/category/session unless ties are enabled. Named award recipient
limits can span the contest or apply within those groups. Award limits per
exhibitor/category remain independent from entry limits. A team award belongs to
the team. There are no score calculations, rubrics, totals, or brackets.

Results stay private until published. Each accepted registration must have a
recorded status before publication; unrecorded never silently becomes unplaced.
Published results must be reopened with a reason before corrections. Corrections
also require a reason, with staff identity and change history retained. Optional
result entry can be disabled per contest. Published results appear alongside the
exhibitor's registrations in My Entries.

PDF/CSV exports cover contestant rosters, team rosters, check-in lists, project
labels, and placings/awards. Result exports include team member names but omit
birthdates, email addresses, answers, and attachments. Draft result exports are
marked DRAFT. The management screen's roster exports include contacts for staff.
Animal awards, legs, sweepstakes, and wave eligibility are not changed.

**Other Reports** in Close Show/Reports V2 includes **Add-On Purchases** and
**Contest Registrations**, with on-demand PDF and CSV downloads for the entire
show. They are available before finalization and report generation, and read
current submitted registrations/orders on every download. Staff can see who
ordered each item, quantities and saved prices, and contestant divisions,
entry/team/project details, animals, team members, approval and check-in status.
Both include exhibitor numbers, contact emails, and order payment status so
unpaid/pay-at-show records are identifiable. Deleted offerings remain in the
purchase history; cart drafts and private application answers are excluded.
These reports need no additional database or worker deployment.

Show Add-Ons offers suggested names for extra coops, parking passes, banquet
tickets, and tour tickets, along with arbitrary custom names, descriptions,
prices, and a maximum quantity per exhibitor across the full show. These items
are purchases; they do not automatically allocate physical coop numbers, parking
spaces, or reserved seats.

The exhibitor’s optional **Contests & Add-Ons** step follows adding animal entries
and precedes the cart. Enter Show also provides a shortcut for people registering
without animals. Household members select the exhibitor associated with each
registration or order. Items can be edited or removed before checkout. The cart
shows contest/extra amounts separately and uses the existing show payment choices.
Free contest/extra-only carts can be confirmed without an online payment provider.

Secretaries see submitted registrations and answers from each setup screen.
Exhibitors see their submitted records from **My Entries → Contests & Add-Ons**.
Pay-at-show registrations show their outstanding payment status. Draft cart items
are not presented as submitted registrations. Hiding an offering preserves past
records, while blocking new checkout of that offering. Registration follows the
show’s existing entry window and locked/finalized state.

Contests default to **Use show entry dates**. A secretary can turn that off for
an individual contest and set both opening and closing dates and times; closing
must follow opening. The editor displays local time and stores UTC instants.
Inherited dates follow later changes to the show schedule. Custom dates can
extend before or after animal entry dates, while locked/finalized shows remain
closed. Exhibitors see the applicable dates and cannot register outside them;
checkout revalidates the window. Shows remain discoverable while a custom contest
is open, even after animal entries close. Mixed carts still enforce animal entry
dates. Show Add-Ons continue to use the show's entry window.

Show Add-Ons offer **Delete** in each item’s three-dot menu, with confirmation.
Deletion removes the item from setup and new orders while retaining submitted
orders, balances, and payment history. It does not cancel or refund purchases.
Only authorized show-settings staff can delete, and locked/finalized shows are
protected. Unsubmitted carts must remove deleted items before checkout; removing
the final add-on leaves an empty cart with no obsolete balance. Stale editors
cannot restore a deleted item. Contest deletion is outside this add-on change.

Prices, names, and form questions are snapshotted when added or edited in the
cart. Animal discounts do not reduce contest or extra fees. Existing one-time
exhibitor fees continue to apply to animal entry; buying only extras does not
create an animal entry or add the animal-entry exhibitor fee. Checkout receipt
lines include the individual names, quantities, and prices. Internal cart carrier
rows provide payment context but never materialize as animals or count toward
entry totals, judging, waves, or animal discounts.

The database enforces secretary permissions, household ownership, answers,
eligibility, per-exhibitor limits, and payment-state restrictions. Private tables
have RLS enabled and no direct client access. Guarded RPCs are the only write
path. Support viewing remains read-only. Online provider completion and retries
reuse the existing payment finalization and idempotency protections.

Deploy `20260916223850_add_show_contests_and_extras.sql` **before** the Flutter
frontend because the cart reads the new carrier column. The migration checks the
shape of existing checkout functions and fails rather than silently skipping an
integration. No Edge Function changes are required. This migration was applied
to the hosted project on September 16, 2026, for testing with the local Flutter
app. Both features remain disabled on every show until a secretary enables them.
Post-deployment checks confirmed the new RLS and RPC permissions, and the security
advisors reported no new findings. The production frontend has not been deployed.

`20260916233021_add_contest_registration_windows.sql` and Square checkout version
16 were deployed on September 16, 2026, for custom contest window testing at
localhost. JWT verification remains enabled. Validation added 30 rolled-back SQL
assertions for custom dates, permissions, discovery, and checkout; all 59 original
contest assertions, 18 Chrome tests, and 14 accessibility checks passed. Flutter
analysis, Deno type checking, and private-schema lint passed; hosted security
advisors reported no new findings.

Validation: complete migration replay in a rolled-back local transaction;
59 contest/add-on SQL assertions, including mocked online completion and replay;
existing exhibitor-fee and refund SQL suites; 14 Chrome model/form/cart tests;
the repository’s 14 accessibility checks; Flutter analysis; and private-schema
database lint. All payment tests use synthetic data and no external charge.

## Contest expansion deployment and verification

`20260917013828_expand_contest_registration_and_results.sql` was applied to the
hosted backend on September 16, 2026 (September 17 UTC), and the local Flutter
preview was refreshed. The local filename matches the version recorded by the
migration API. The CLI dry run found pre-existing history differences, so only
this exact new migration was applied through the API; older history was not
altered. The production frontend has not been published.

Validation: 64 expansion SQL assertions, 59 original checkout/add-on assertions,
and 30 registration-window assertions, all using rollback fixtures and no live
payments; 20 Chrome model/form tests; a PDF generation test covering all five
report types with pagination and long names; visual inspection of generated reports;
and targeted Flutter analysis. Tests cover
category/session limits, birthday boundaries, team duplication, file privacy,
walk-up balances and replay, unpublished result privacy, duplicate placings,
award limits, publishing and corrections, and existing free/online/offline
checkout. Private attachment tests also simulate a broad legacy Storage policy.

The hosted database confirms RLS on all three new private tables with no direct
client reads. The private upload bucket has a 10 MB limit. The security advisor
reports expected informational “RLS enabled, no policy” notices for those private
tables: guarded RPCs are deliberately the only access path. No warning/error
finding concerns the new contest objects. See the
[Supabase RLS advisory](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

The refreshed localhost preview was checked on the existing signed-in demo show:
the searchable template groups load, Royalty appears under Individual, and applying
a template remains an unsaved draft. The demo show’s contests remain disabled
until the secretary enables them.

Contest setup now hides unused controls by default. Categories appear when
configured (including project template defaults); animal selection appears when
used, and advanced animal options appear only when configured. Age cutoff and
team age rules follow the active age requirements. Project award limits and
submission deadlines appear where relevant. “Additional setup options” reveals
the remaining controls for custom contests without changing their saved rules.
Existing category, animal, division, and other configured values are retained.

Division names are selected with chips (standard age divisions or Royalty titles)
instead of typing a list. Custom names remain supported, with duplicate checks;
divisions referenced by age rules or conditional questions cannot be removed
until those rules are updated. Capacity is labeled as a full-contest registration
limit, separate from per-exhibitor and per-category limits. Setup explains the
staff-only contest check-in location, optional session time slots, special award
titles, and exhibitor registration questions. Session, age-range, and award
dialogs use white surfaces with dark text; schedule instructions and long labels
wrap on narrow screens. These are frontend changes with no database deployment.
All 20 existing contest checks passed, and narrow-screen browser inspection
confirmed the time-slot and special-award dialogs are readable.
