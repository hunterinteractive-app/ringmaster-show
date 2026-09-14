Entry Management supports **Refund & Remove Entries** in each entry menu and
beside each exhibitor. The page toolbar also offers **Refund History**, including
refunds for exhibitors whose last entry has been removed.

Only the show's owner/creator, assigned show secretaries (`admin` / legacy show
admin), and global super administrators can use it. Entry managers and
superintendents do not gain refund permission. Support viewing is read-only.
The database checks the actual authenticated actor independently of the UI.
This feature is available to all qualified secretaries, without the Houston
feature allowlist.

The secretary selects an original payment, selects entries across the full show,
reviews the suggested entry fee, chooses whether to include online fees, and
provides a reason. Refund amounts can be adjusted within the remaining payment.
The confirmation lists the selected entries and the entry/online fee split.
Stripe and Square return funds to the original payment source. A manually
recorded cash/check/external payment instead requires confirmation that the
money has already been returned outside RingMaster; this records the refund.

Entry deletion happens only after provider success (or confirmation of a manual
return). Saved animals are retained. Pending entries are reserved against edits,
deletion and another refund. A failed refund releases the reservations. Shows
with unresolved refunds cannot be locked or finalized. The existing Allow
refunds setting is respected when starting a refund.

Refunds use a durable request UUID, provider idempotency, payment limits and
database reservations. A timeout preserves the same request. Automatic checks
and **Check Status** look up the existing provider refund. No new refund is
created once the Stripe idempotency safety window has elapsed; unresolved
requests remain in **needs review** for investigation against the provider.
Provider failures keep entries intact. Provider success followed by a database
outage retries only the accounting/removal work.

Accounting retains gross payments and records the actual refunded principal.
The same principal is credited against the assessed fees so a refund does not
create a new balance due. Online fee refunds are tracked separately because
they were never part of the exhibitor's entry balance. Deleted entry snapshots,
selected IDs, amounts, reason, actor, timestamps and provider references are
stored in a private audit schema. Refreshes preserve the refund credit. Prior
refund credits do not change the suggested price of remaining entries.

Stripe refunds use the original account snapshot or its signed webhook record.
Both checkout endpoints now save that account before charging. Historical
destination charges are accepted only when Stripe confirms the original
destination. When online fees are included, Stripe may return the proportional
application fee; entry-only refunds retain it. Square uses the same fee choice.

Deployment consists of migrations `20260914102453_add_entry_refunds.sql` and
`20260914105802_harden_entry_refund_read_access.sql`, and Edge
Functions `refund-show-entries`, `stripe-create-checkout-session`, and
`checkin-stripe-create-checkout`. Preserve each function's JWT configuration.
The refund endpoint validates user JWTs with `getUser`. Background reconciliation
accepts a dedicated `ENTRY_REFUND_RECONCILE_SECRET` (or the existing backend
service credential); this secret can only reconcile already-authorized refunds.
Configure a five-minute POST job with `{"action":"reconcile"}` and its bearer
token. Do not log or commit that token.

`scripts/configure_entry_refund_reconciler.py` configures the dedicated secret
and Cloud Scheduler job, reusing the existing job when present. On September
14, 2026, the backend was deployed to `yzjoycrvqkyfrksmaixf`: refund endpoint v1,
normal Stripe checkout v64, check-in Stripe checkout v7. The
`ringmaster-entry-refunds` job is enabled in `ringmaster-show-production`,
`us-east1`, every five minutes; its first scheduled run succeeded. Anonymous
requests return HTTP 401. The security advisor found no new findings after
hardening the read RPCs. No live refund was issued for deployment validation.

Validation uses rollback-only SQL fixtures (`supabase/tests/entry_refunds.sql`),
the existing exhibitor-fee payment suite, provider/state-machine tests with
mocked responses, and Flutter interaction tests. Never issue a live refund as
part of a deployment smoke test.
