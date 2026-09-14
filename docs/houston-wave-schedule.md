# Houston wave schedule

## Behavior

Show Settings has a **Wave Schedule** button immediately below **Show Fees & Payments**. It uses the existing BBOS secretary entitlement and normal show management permissions. The initial eligible account remains `3e8dddf9-3a17-4ebb-aeab-9b51d31e7871`; an administrator does not gain access to unrelated shows merely by being an administrator.

The dialog starts with three waves and supports adding or removing waves. Its **Breed Assignments** tab lists only rabbit and cavy breeds entered anywhere in the show, alphabetically, with a wave dropdown for each. Assignments apply across all sections, including Open and Youth. Rabbit and cavy breeds remain separate choices even when their names match. Saved assignments for breeds with no remaining entries are retained when saving but hidden from the list. Both tabs use the app’s purple background and white text, with light input fields. The **Schedule** tab sets check-in start and end, show date, check-out date, and when automatic sheets are sent: 1, 2, 5, 10, 15, 20, 24, 48, or 72 hours before check-in. The default is 24 hours. Dates and times use the show's configured timezone.

Disabled schedules can be saved as drafts. Enabling requires complete dates, nonoverlapping check-in windows, and an assignment for every entered breed. Cart-only and catalog-only breeds do not appear in the list or block activation. New breeds may be added to carts and entered after waves are enabled; they then appear in Breed Assignments and must receive a wave before they can check in or appear on wave sheets. The secretary can assign additional entered breeds later. Existing assignments cannot move after automatic sheet preparation or check-in has begun.

Enabling a schedule turns on automatic check-in sheets for that show. The existing email-disable control is respected. The check-in portal must also be enabled through its existing settings. A wave is active at its start time and closes exactly at its end time. Portal sessions are pinned to their wave and every portal API enforces that wave, including edits, additions, payment context, and completion. The same exhibitor checks in separately for each wave. Staff review and rosters display the active wave's animals and completion status.

Automatic email groups all the exhibitor's entries in a single wave into one sheet. Exhibitors without entries in that wave receive nothing. Delivery receipts and provider retry keys are separate per exhibitor and wave. Manual check-in reports have a wave selector and include the wave in filenames. Archived closeout packets retain separate sheets for each entered wave, even after all check-in windows have closed.

Each wave sheet includes:

> This check-in sheet includes only your animals in this wave. If you have animals entered in other waves, you’ll receive a separate check-in sheet as each wave’s check-in approaches. You can view all your entries anytime in the Entries tab of your account.

## Release

Deployed on September 14, 2026 with the secretary's approval. The localhost Flutter preview uses the live Supabase project `yzjoycrvqkyfrksmaixf` and has been hot-restarted.

- Migration: `20260914072828_add_show_wave_schedule.sql` (the MCP-assigned production version; local filename aligned afterward).
- Email function: `auto-email-checkin-sheets` version 31, with its previous custom authentication and runtime configuration preserved.
- Report worker: `ringmaster-closeout-renderer-00046-c6w`, image/build version `waves-abe5cfa3f2d5`, serving 100% of traffic. Authenticated health returned this version. Existing credentials, service account, and resource limits were preserved.
- The automatic email cron job (ID 4) was paused during the database/mail-service transition and restored to its previous active every-minute schedule.
- All wave schedules remain disabled by default. The existing 100 check-in records and 76 delivery receipts were preserved during deployment.
- The existing Test Show's ordinary report retained all 10 entries and the identical report-data hash. An authenticated email dry run returned 10 entries, 4 exhibitors, and a generated PDF without sending mail.
- Follow-up migration `20260914075020_show_wave_entered_breeds.sql` limits the dialog to entered breeds while preserving hidden assignments and allowing new breeds to be entered for later wave assignment. Test Show now returns six alphabetized entered breeds with scheduling disabled. The dialog uses purple with white text. Five browser tests, eleven model/report tests, and 47 database assertions passed; the analyzer was clean. No mailer or report worker redeployment was needed for this follow-up.
- Security advisors: 428 existing findings before and after, with no newly introduced findings.

The coordinated release procedure is:

1. Preserve the current `auto-email-checkin-sheets` cron job configuration without printing its credential-bearing command. Temporarily pause that job and wait for any active email lease to finish.
2. Apply only `20260914072828_add_show_wave_schedule.sql`, after the existing BBOS migration. The wave migration creates no enabled schedules and sends no emails. It changes the delivery uniqueness key, so the older mailer must not run during the transition.
3. Deploy `auto-email-checkin-sheets`, including its `helpers.ts` and `pdf.ts` modules. Preserve the deployed authentication settings and secrets. Use its authenticated `dry_run` for a read-only ordinary-show check.
4. Rebuild/deploy the Closeout renderer from the shared sources. Its archived check-in packets now split by wave. Verify worker health, then restart the local Flutter preview (or release the app).
5. Restore the cron job's prior active state, inspect advisors, and verify entitlement, disabled-by-default behavior, and an ordinary show's reports. Configure a test schedule only with the secretary's chosen dates and assignments; enabling it can cause real scheduled mail once the lead window is reached.

## Verification

- Database assertions cover entitlement, direct-write rejection, overlap, timezone conversion, cart and entry assignment, fee carriers, report scope, preparation locking, portal API restrictions, separate wave completion and deliveries, exact closing boundaries, and ordinary shows.
- Flutter tests cover date validation, report scope and archive grouping, large ordinary reports, dialog editing and read-only behavior, and existing BBOS/result rules.
- Deno tests cover pagination, retry protection, per-wave delivery keys, and PDF generation. Both generated PDF layouts were rendered and inspected, including continued pages.
- Analyze the affected Dart files and compile the headless renderer before deployment. Run local Supabase advisors; unrelated existing findings are outside this feature.

No production wave schedules were configured, and all release email checks used dry-run mode. Shows without an enabled wave schedule retain their existing check-in, email timing, entry selection, and report layout.

## Emailed exhibitor numbers

On September 14, the secretary confirmed that wave sheets should retain the normal automatically emailed check-in sheet layout, rather than the Print Packs layout. The mailer now batches exhibitor account-number lookups by the actual exhibitor ID and includes `Exhibitor #: <number>` beside the name in the gray bar for ordinary and wave sheets. Long names can wrap without covering the entry count. Wave scope, scheduling, note, delivery receipts, and retry keys are unchanged.

Deployed as `auto-email-checkin-sheets` version 32 with the existing authentication and runtime settings. Ten Deno tests passed, type checking and lint passed, and both normal and two-page wave PDFs were rendered and checked for the account number, full names, counts, and complete entries. Existing emailed attachments remain unchanged; newly generated sheets use the corrected template.

## Check-in links in email

Deployed migration `20260914082508_persist_checkin_links_for_email.sql` and `auto-email-checkin-sheets` version 33. Both ordinary and wave emails include **Open the check-in page** when the portal is enabled and its current link is stored. Advance emails include the link before check-in opens, with a reminder to use the scheduled window. Existing portal verification and wave restrictions still apply. The PDF layout is unchanged.

Generated links are now retained in a private table with RLS and no ordinary client table access. Email-link retrieval is service-only. A stored link is returned only when its token matches the current portal hash, so disabled, missing, and stale links are omitted. Regenerating a link retains the existing permission checks and session revocation and saves the replacement automatically.

Older links could not be reconstructed from their hashes. The secretary supplied Test Show’s existing URL; its token was verified against the current hash and saved without rotating it or changing the QR code. Other older links can be imported the same way if supplied.

Twenty database link assertions, 47 existing wave assertions, and 12 Deno tests passed. Type checking and lint passed. Verification used a live dry run without sending an email.

## Explicit resends

Mailer version 34 supports a fresh resend request in a service-only delivery receipt’s `_resend_id` payload marker. An operator first locks/checks the show’s mail lease, preserves previous delivery IDs and timestamps in the check-in audit ledger, then queues only the requested wave’s sent receipts with a fresh request UUID and attempt time. Replaying that operation must use the same request UUID and check the audit event to avoid queueing it again.

The worker builds the latest PDF and email for that request and saves the full payload before contacting the provider. The provider key includes the resend UUID, so an intentional resend differs from the original delivery while network retries reuse identical content and a stable key. Ordinary delivery keys remain unchanged. The marker is removed from the provider payload. Thirteen Deno tests, type checking, and lint passed.
