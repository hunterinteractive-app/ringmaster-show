**Four readiness fixes and focused tests — September 12, 2026**

The four findings from the full-event rehearsal have fixes or a local runtime mitigation, and the focused tests pass. Code is committed at `e2e54fa4fa4a8f921fd378af9b45f2ea9bd533a1`. A larger **local synthetic** run can use these files. Production deployment is pending the explicit approval required by automatic approval review.

| Finding | Change | Focused evidence |
| --- | --- | --- |
| Fee bookkeeping accessible directly | Enable RLS, revoke client table access, move the charging helper into the private schema, and update the three authorized entrypoints | Nine real API access attempts denied; two unrelated-user staff operations denied; staff approvals and financial reports still work |
| New fees after cash payment missing from balance | Use a new cart after a full/partial payment, serialize fees and manual payments per exhibitor, preserve earlier payment records, and reject changed replays | $7.50, $2.50, and $3.00 later fees paid through $7.50/$1.00/$4.50 payments; final due $0; earlier balances/payments unchanged; no duplicate fees or animal entries; Youth/Open totals correct |
| Permission-denial test crashes local PostgreSQL | Disable only optional `supautils` error hints on the affected pinned local image; preserve ACL/RLS and all access denials | Exact denied-function pattern succeeds for anon/authenticated by returning permission errors; 150 repeated denied operations pass; database start timestamp unchanged |
| Long registration waits | Give account lookup one 12-second upstream budget across Auth, Show and Club; return retryable 503 on timeout; instrument all stages; use persistent HTTP connections in the local provider emulator | Three bursts of 250 new purchasers, 750 total, all complete with exact payment/session counts; intentional 16-second upstream stall returns 503 after 12.175s and retry succeeds |

The payment test also exposed and fixed a related bug: the existing payment-protection trigger blocked an authorized later partial payment. The manual-payment RPC now enables its existing protected-write mechanism only after authorization and balance locking, then restores the prior setting. Payment protection remains active outside that operation.

Twelve simultaneous staff approvals produced twelve $5 fees on exactly one fee cart. Their $60 cash payment and scoped report reconciled, retaining exactly one actual animal entry in that separate probe show. Direct access remains denied even for a show admin; authorized staff use the existing RPCs.

**Registration measurements**

| Metric | Before: 250 purchasers | After: 750 purchasers, 250 at a time |
| --- | --- | --- |
| Account lookup p95 | 3.414s | 2.353s |
| Account lookup maximum | 4.429s | 3.493s |
| Checkout p95 | 2.776s | 2.788s |
| Checkout maximum | 3.543s | 3.904s |
| Failed final operations | 0 | 0 |

All 750 new Auth accounts, exhibitors, carts, provider sessions, paid entries, and duplicate-payment replays reconciled. Auth connections remained bounded at 20. The three bursts completed in about 32 seconds after service startup; the deliberate timeout test was separate from those latency metrics.

The earlier 31–70 second outliers did not reproduce in the small baseline either, so these numbers do not prove that every source of sustained-load latency has been eliminated. The production lookup now has an explicit timeout in the proposed release, and the local emulator avoids repeated connection setup. The larger run should confirm sustained behavior using the updated harness. Physical printing, real providers, and hosted national-scale capacity remain outside these local tests.

The local database image is `public.ecr.aws/supabase/postgres:17.6.1.106`. Its denied-function crash matches [Supabase's reported extension issue](https://github.com/supabase/supautils/issues/214). Only the extension's optional error-hint feature is disabled locally; no permissions are broadened. `configure_capacity.py` automatically applies this mitigation for that exact affected image when the rehearsal starts. The verified production project uses `17.6.1.063`; no production database-runtime setting or version was changed.

Additional validation passed: nine Deno timeout/payment-quote tests, Edge Function type checking, existing payment-hardening and scoped-financial authorization suites, Python compilation, and diff checks. The complete migration applied atomically to the separate restored snapshot, and the full fee regression passed there. The restored snapshot needed its expected public-schema usage grants because the prior backup intentionally excluded ACLs; that fixture correction was isolated to the restored database.

Earlier failed diagnostics are retained: the first fee test expected a repeated approval to succeed, whereas the existing API correctly rejects an already-reviewed request; the next iteration exposed the partial-payment bug. The final tests require rejection of repeated approval and verify the internal helper's idempotency separately. The first local migration attempt had a missing SQL terminator and rolled back completely; the final complete migration passed.

**Ready-to-deploy scope**

The destination is the existing `ringmaster-show` Supabase project, `yzjoycrvqkyfrksmaixf`, at `https://yzjoycrvqkyfrksmaixf.supabase.co`. Project inventory and the application's `lib/config/supabase_config.dart` both identify this destination.

- Apply `20260912104332_fix_checkin_fee_access_and_followup_charges.sql`: fee-table permissions/RLS, private helper, three internal call references, and authorized manual-payment handling. It does not rewrite historical payments or entries.
- Deploy `claim-or-import-exhibitor` and its shared timeout dependency, retaining JWT verification.
- The report worker and Flutter application logic have no changes in this fix; no worker redeployment is required.

Automatic approval review rejected the attempted migration because persistent privilege/payment-function changes require explicit approval for the production destination and scope. No production migration or Edge Function deployment from this fix was applied. The existing production build remains the release from the preceding full rehearsal until approval is provided.

Focused evidence is retained in `output/full_e2e/focused-fixes-20260912/`, especially `fee-regression-v3/summary.json`, `fee-api/summary.json`, `registration-after/summary.json`, `database-stability.json`, and the clean-migration regression logs. The original full-event fixture and PDF evidence remain retained; small committed API probes use separate synthetic shows. No real payments or external emails were sent.
