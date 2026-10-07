# Contest expansion — reference design

Status: the registration, check-in, manual results, publishing, and report
implementation is available in the local preview. See `contests-and-extras.md`
for the delivered capabilities, operational choices, and validation. The optional
ideas below are a reference for future variations, not a claim that invitations,
external membership verification, anonymous judging packets, or automatic waitlist
promotion are implemented. The latest direction is registration, check-in,
and staff-entered placings/awards. Score calculation is deferred. Royalty belongs
under Individual. Houston, ARBA, ISRBA, and PaSRBA are reference examples for
customizable settings, not rules imposed on every show. Contest features remain
available to all authorized show secretaries, independently of the Houston
feature allowlist.

## Starting point

The current implementation provides editable contest templates, household
exhibitor selection, named divisions, optional selection of an entered animal,
custom questions, fees, registration windows, checkout, and registration lists.
Its one-registration-per-exhibitor rule and simple division labels need to grow
to support teams, multiple projects, eligibility rules, and results.

Keep the existing exhibitor flow: animal entries → optional Contests & Add-Ons →
cart. Continue offering direct access for contestants who are not showing animals.
Saved contest entries and results belong under My Entries.

## Templates

Offer a searchable template picker with a Custom Contest choice. Selecting a
template fills an editable draft; the secretary reviews it before saving and
enabling it. Preserve the existing fee and date choices when replacing a draft.

| Group | Suggested templates | Main capabilities |
| --- | --- | --- |
| Individual | Royalty, Rabbit/Cavy Showmanship, Individual Judging, Breed Identification, Skill-a-Thon, Costume Contest, Presentation, Individual Quizbowl | Exhibitor, division, optional animal, customizable requirements, placings/awards |
| Teams | Team Judging, Team Breed Identification, Team Quizbowl | Team roster, alternates, team division, placings/awards |
| Projects | Educational Exhibit, Art/Craft, Photography, Creative Writing, Illustrated Talk, T-Shirt Design | Category, project details, uploads or video link, multiple entries where allowed |
| Applications | Rabbit Management, Cavy Management, Achievement, Youth Breeder Award | Individual applicant, questions, documents, optional shortlist, placings/awards |

Template grouping and entry format are independent. An Individual contest can
have several activities; that does not move Royalty out of Individual. Quizbowl
can use individual or team registration. Secretaries can rename a template,
change requirements, add/remove divisions and questions, or start with Custom
Contest. Duplicating a contest should copy its configuration for reuse, with
dates and availability reviewed for the new event.

Templates should identify their reference and revision when based on published
rules. Keep generic starting points available. Never copy a past event's calendar
dates into a new show's default dates. A reference template is not an official
ARBA submission or membership verification service. Each show saves its own
configuration; later reference/template changes do not alter existing contests.

## Secretary setup

Use expandable sections. Show only the sections applicable to the selected
contest, so a basic contest does not require a large form.

### 1. Contest details

- Name, instructions, availability, optional rules attachment/link.
- Entry format: individual or team; optionally one or more named project entries.
- Fee: free, per contestant, per team, or per project/category entry.
- Optional overall, session/day, or division/category capacity and waitlist.
- Optional approval or shortlist before participation; payment, eligibility, and
  selection remain separate.

### 2. Divisions and eligibility

- Editable division names and optional age ranges. Age uses show start, show end,
  or a custom cutoff date. Suggest the eligible division and validate selection.
- Separate categories from divisions: Junior is a division; Photography is a
  category. Allow rules and limits for each combination where necessary.
- Optional non-age criteria, such as experience, rabbitry size, club, state,
  district, or membership. Collect supporting evidence only when configured.
- Optional membership number, accepted membership types, membership-as-of date,
  expiration date, and proof for one or more organizations, for secretary review.
- Limits per person, category, team, or represented organization as appropriate.
- Keep entry limits separate from award limits: multiple projects can be accepted
  even if only one may place within a particular category.
- Local eligibility and selection for a later event/team remain separate. Collect
  interest/availability and record qualifiers without entering an external event.
- Authorized eligibility exceptions require a reason and remain recorded.

### 3. Animals, teams, and entry questions

Animal participation and show entry are separate settings. A contest can require
an entered animal, allow an exhibitor-supplied animal that is not entered in the
show, offer an organizer-provided animal, or need no animal. Rabbit/cavy choices
and animal rules can differ by contest or activity. Allow multiple animals with
named roles when necessary, such as a parent and two offspring. Optional show
entry prerequisites can specify species and qualifying sections.

For team contests, configure active member count, alternates, age policy,
represented club/state/district, coordinator contact, and roster lock date.
Support members from different households through invitations/confirmation or
authorized secretary entry. Prevent duplicate membership within the same contest.
Record active members at check-in. Teams may use a common age division or the
oldest member's division when explicitly configured. Team participation can
optionally require individual contest registration, with any additional fee
clearly shown before checkout. Individual and team awards are recorded separately.

Keep existing custom fields and add multiple choice, file uploads, and video/link
fields. Fields can depend on category or division. Configure allowed file types,
file counts/sizes, and applicable document/response limits. Provide save-and-return
for longer applications, plus required acknowledgments or guardian consent.
Optional questions can collect assistance requests, guardian/event contacts,
prior-winner declarations, or supporting records. Reuse shared participant
answers across selected contests only with the entrant's review.

Included participant items, such as a supplied shirt, can collect a size as a
registration question. Additional merchandise purchases belong under Show
Add-Ons with their own price and quantity.

Allow judge copies identified by contestant number for anonymous application
review. Identity and membership documents stay outside the judging packet.
Uploads containing identifying information need review; hiding a name in the
screen does not remove it from a submitted document.

### 4. Dates and check-in

Registration continues to inherit show opening/closing dates unless overridden
per contest. Optional additional dates cover material submission, edits/roster
changes, contest check-in, activity sessions/callbacks, and project drop-off/pickup.
Display the applicable timezone clearly. Multi-day contests can require exactly
one selected session, permit multiple sessions, or offer several drop-in windows.
Enforce a person's overall entry limit across sessions alongside each session's
capacity.

Support secretary-entered walk-up registrations when enabled. Check-in records
the contestant/team's presence, active roster, and any project receipt separately
from payment and animal check-in. Animal wave restrictions must not inadvertently
block a contest that does not require animal entry.

### 5. Placings and awards

Offer an optional **Record contest results** setting. The secretary records the
judges' decisions by selecting a registered contestant, team, or project and
assigning a place and/or award. No points or scorecard are required.

- Numbered placings: first, second, third, and as many places as the show offers.
- Named awards: customizable titles such as King, Queen, Champion, Reserve,
  Best Overall, or Honorable Mention.
- Optional ribbon ratings can be recorded independently of numbered placings.
- Results are scoped to contest, division, category, and session where relevant.
  Overall awards may span those groups when configured.
- Configure how many recipients an award permits and whether tied places are
  allowed. Prevent accidental duplicate unique places/awards within their scope.
- A contestant may receive both a placing and a named award. Team awards belong
  to the team, with its roster shown; they do not become individual placings.
- Support entry/award limits independently, including a maximum number of placed
  projects per exhibitor in a category. Flag violations for secretary review.
- Keep an unplaced entry distinct from one whose results are not yet recorded.
  Also record absence, withdrawal, or disqualification separately.
- Optional callback/finalist status can identify who advances without computing
  advancement from points. Record a reason for authorized result corrections.
- Keep draft results private until the secretary reviews and publishes them.
  Preserve edit history and require reopening finalized results for corrections.

Activities within Royalty or another contest can have editable instructions and
completion requirements, including different activities for different divisions.
Organizers determine scores and winners using their own method. Automatic score
totals, weighting, team calculations, rubrics, tie-break calculations, and match
brackets are outside this version's scope.

## Staff and exhibitor screens

Add a **Manage Contests** destination for Registrations, Check-In, and Results.
Filter by contest, division, category, session, or team. Secretaries and above
manage setup, eligibility, placings, corrections, and publishing. Any separately
assigned check-in staff have only their assigned operational permissions.

Results progress through draft, review, and published states. Exhibitors see
their own registration, submission status, schedule, and published results.
Public results expose only configured participant/team names, divisions,
placings/awards. Birthdates, contact details, membership proof, private
applications, and unpublished results remain restricted.

Provide PDF/CSV exports for contestant rosters, team rosters, check-in lists,
project labels, placings, and winners. Include exhibitor/contestant
numbers. Contest results remain separate from animal breed/show awards, legs,
and sweepstakes reporting.

## Source-driven distinctions

- ARBA's individual contests have different age ranges and use an age cutoff at
  the end of the convention. Showmanship also permits organizer-provided animals.
  This supports configurable eligibility and animal source.
  [Individual contest rules](https://arba.net/wp-content/uploads/2026/02/2026YouthIndividualContests.pdf)
- Team Judging distinguishes active members from alternates and totals the
  counting members' scores. Quizbowl instead uses pools and elimination rounds.
  Organizers can record the resulting placings with either method.
  [Team Judging](https://arba.net/wp-content/uploads/2026/02/2026NationalTeamJudgingContests.pdf),
  [Quizbowl](https://arba.net/wp-content/uploads/2026/02/2026TeamQuizBowl.pdf)
- Educational contests allow entries in multiple classes, with a limit per class;
  physical exhibits and recorded talks have different submission needs. Ribbon
  ratings and ranked winners coexist. The document contains inconsistent senior
  age wording and a prior-year date for illustrated talks, so those details need
  organizer confirmation before becoming enforced ARBA-specific presets.
  [Educational contest rules](https://arba.net/wp-content/uploads/2026/02/2026EducationalContests.pdf)
- Rabbit Management divides contestants by rabbitry size; Cavy Management groups
  all sizes together. Division configuration must support criteria beyond age.
  [Rabbit Management](https://arba.net/wp-content/uploads/2026/02/2026YouthRabbitManagementContests.pdf),
  [Cavy Management](https://arba.net/wp-content/uploads/2026/05/2026-Youth-Cavy-Management-Contests.pdf)
- Royalty combines application and in-person activities and requests separate
  application, biography, and photo submissions. This motivates multiple uploads
  and configurable activities within an Individual contest.
  [Royalty rules](https://arba.net/wp-content/uploads/2026/02/2026YouthRoyalty.pdf)
- Achievement uses application scoring; T-Shirt Design permits two categories.
  Both fit editable templates with configurable submissions and entry limits.
  [Achievement](https://arba.net/wp-content/uploads/2026/02/2026NationalYouthAchievement.pdf),
  [T-Shirt Design](https://arba.net/wp-content/uploads/2026/02/2026YouthTShirtContest.pdf)

## Additional reference examples

The links below are design evidence. ISRBA's linked files are labeled 2022;
PaSRBA's landing page says 2025 while the reviewed contest PDFs say 2026. Their
dates, fees, divisions, and eligibility rules must not become universal defaults.

| Example reviewed | Configuration it demonstrates |
| --- | --- |
| Houston judging and costume contests | Individual/team entry; a custom age cutoff; different requirements by division; per-day capacity with one entry across all days; qualifying animal-show entries |
| ISRBA Royalty and individual contests | An Individual Royalty contest with age-dependent activities; different preregistration/walk-up policies; an age cutoff tied to another event; reading/writing assistance requests |
| ISRBA Quizbowl and educational contests | Individual Quizbowl; interest in future team selection; multiple projects with a separate limit on how many may place |
| PaSRBA Royalty | An Individual contest with configurable application/photo requirements and activities that differ by division |
| PaSRBA Team Judging | Team size and individual-registration prerequisites; team results recorded independently of individual results |
| PaSRBA Youth Breeder Award | Application review and a shortlist; several animals with specified roles; supporting records; prior-winner declarations |

Sources:

- [Houston 2026 handbook, printed pages 130–132](https://www.rodeohouston.com/wp-content/uploads/2026/03/2026-Exhibitor-Handbook_V7.pdf)
- [ISRBA youth page](https://www.isrba.com/youth.html) and its
  [linked general rules](https://www.isrba.com/uploads/1/7/8/7/17872527/2022_youth_contest_general_rules__1_.docx)
  and [entry form](https://www.isrba.com/uploads/1/7/8/7/17872527/2022_youth_contest_entry_form__1_.xlsx)
- [PaSRBA forms](https://www.pasrba.org/youth-forms),
  [Royalty](https://www.pasrba.org/_files/ugd/e51fea_ffeb31d72e5f435891ecf7a1d7e24afd.pdf),
  [Team Judging](https://www.pasrba.org/_files/ugd/e51fea_56799bb9121546048a122bc4c6f38bb4.pdf),
  and [Youth Breeder Award](https://www.pasrba.org/_files/ugd/e51fea_654d9053d2454615888c221e1caed215.pdf)

## Acceptance examples for the build

- A basic custom contest needs only a name, entrant, optional fee, dates, and
  optional divisions/questions. Advanced sections can remain unused.
- Royalty appears under Individual; its divisions and named awards are editable,
  and it can publish winners without any numeric scores.
- One exhibitor can enter several permitted project categories and receive
  results for the correct project. Award limits do not erase accepted entries.
- A contest with two dates can enforce one entry per person across both dates
  while honoring separate session capacities.
- A team requiring individual registration identifies missing registrations before
  checkout and does not charge twice for an existing registration.
- A contest can collect multiple animal roles and a required document without
  requiring an unrelated animal-show entry.
- Draft results are private. Unique placings reject accidental duplicates;
  explicitly permitted ties and awards with several recipients remain possible.
- A participant can receive a division placing and a named award. A team's award
  remains associated with its roster and does not overwrite individual results.
- Publishing produces consistent exhibitor results and PDF/CSV reports; private
  applications and contact details never appear in public result exports.
- Existing basic contests, fees, entry windows, and saved registrations continue
  working with the optional additions unused.

## Suggested implementation sequence

1. Extend entry types, divisions/categories, eligibility, and template selection.
2. Add team rosters, project/application submissions, and contest check-in.
3. Add manual placings, named awards, and draft result review.
4. Add review/publishing, reports, and test the full exhibitor-to-winner flow.

All four steps belong to the requested scope. Existing registrations and contests
retain their settings; optional new capabilities are enabled per contest.
