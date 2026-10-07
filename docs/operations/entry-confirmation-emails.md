# Entry submission confirmations

A successful cart submission queues one confirmation for the checkout account, covering all exhibitors in that cart. Online submissions wait for paid finalization; pay-at-show submissions show the outstanding cart balance. The snapshot uses the cart's actual payment amount and cart-sourced balance rows. It includes the check-in promise only when automatic check-in emails are enabled at submission.

Existing submissions are not backfilled. Later balance payments on an already submitted cart do not generate another entry confirmation. Test shows and shows with email disabled are skipped. This does not email secretary-created entries that do not use a cart.

## Deployment

1. Deploy `send-entry-confirmations` with the project's existing `RESEND_API_KEY` secret and verified `noreply@ringmasterone.com` sender.
2. Apply `20261001042546_entry_submission_confirmation_emails.sql`.
3. Verify the `send-entry-confirmations` cron job exists and is active, without printing its command (it contains a credential). The migration reuses the existing `auto-email-checkin-sheets` scheduler command. If that job is absent, configure a secure scheduled POST before enabling this feature operationally.
4. Review worker logs and queue status after the next legitimate submission. Do not backfill old carts or send test mail to real exhibitors.

## Delivery protection

The primary key allows one queue record per cart. Deferred insertion sees committed entries and amounts; rollback removes the queued email. Only the service role can read or claim the queue. Workers lease jobs and freeze the exact provider payload before sending. Retries retain the same cart-specific Resend idempotency key. Jobs stop after 12 attempts or 23 hours, before the provider's 24-hour idempotency window ends.

Blocked jobs need delivery review before manual intervention. Never blindly reset sent or expired jobs; that can duplicate mail. Queue status counts can be inspected without exposing recipient details:

```sql
select status, count(*) from public.entry_confirmation_emails group by status;
select jobname, active, schedule from cron.job where jobname='send-entry-confirmations';
```

## Local verification

- `supabase/tests/entry_confirmation_emails.sql`: 24 transactional database checks, rolled back.
- `supabase/functions/send-entry-confirmations/email_test.ts`: six template and mocked delivery tests.
- Deno type-check of the worker.

No live email is required by these tests.

The confirmation itemizes nonzero entry, fur, per-show, custom exhibitor, add-on, discount, and exhibitor-paid online fees. Paid submissions use the completed payment session line items; pay-at-show uses saved cart balance components and selected add-ons. Club platform and processor deductions are excluded. Custom fee labels are preserved.
