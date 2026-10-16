# HerdMaster API rollout

## Current deployment

The migration and `herdmaster-api` function are deployed to RingMaster Show production (`yzjoycrvqkyfrksmaixf`), at the user's explicit request. Base URL: https://yzjoycrvqkyfrksmaixf.supabase.co/functions/v1/herdmaster-api.

Production rollback-only checks passed for empty animal batches, catalog export, linked-only result export, revocation, and RPC permissions. Live HTTP checks verify routing and authentication. No HerdMaster account tokens have been issued, and automatic pulling/OAuth remain pending HerdMaster documentation.

Security advisors report that the two service-only tables have RLS enabled without client policies, as intended; explicit table and RPC grants deny anonymous/authenticated access. Performance advisors returned no notices mentioning these objects.

## Implementation

The `herdmaster-api` Edge Function exposes the v1 contract in [herdmaster-api.md](herdmaster-api.md). It uses the server's existing Supabase URL, anon key, and service-role key; none of those keys are sent to HerdMaster. Connection tokens contain 256 bits of randomness and are hashed at rest. No additional shared secret is required.

Migration `20261013001815_herdmaster_partner_api.sql` adds service-only connection/link tables and RPCs. Follow-up migration `20261013011512_herdmaster_account_verification.sql` supplies a private, service-only boolean account-status helper because production denies direct service-role reads of auth.users. It does not modify the existing RingMaster Breeder bridge. The function has `verify_jwt=false` because partner tokens are opaque credentials; the handler validates user JWTs for connection creation/revocation and validates connection tokens inside the database RPC for every data request. The Supabase pattern is documented in [Authorization headers](https://supabase.com/docs/guides/functions/auth-headers).

## Verification

Run from the `ringmaster_show` checkout:

```sh
npx --yes deno test supabase/functions/herdmaster-api/handler_test.ts
npx --yes deno check supabase/functions/herdmaster-api/index.ts
git diff --check
```

Run `supabase/tests/herdmaster_partner_api.sql` inside a transaction after applying the migration to a disposable database, then roll back. Tests use only synthetic `example.invalid` accounts. The legacy local fixture may need the production animal columns `birth_date`, `is_dob_unknown`, and `updated_at`, plus the existing `breeder_animal_links` table. Do not apply fixture compatibility changes to production.

Verified locally: 12 handler tests; SQL assertions for string IDs, unknown DOB, same/stale/conflicting updates, atomic rollback, cross-owner link rejection, existing-animal preservation, managed inactivation, tombstone restoration, report publication gate, linked-only results, corrected results, account isolation, demo exclusion, expired/revoked tokens, and database grants. The local transaction rolls back the schema and fixtures. This verification is not a deployed HTTP or HerdMaster end-to-end pilot.

## Deployment checks

1. Provision a dedicated sandbox Supabase project and verify its target ID before applying any migration. A partner sandbox and credentials remain unissued; production is already deployed.
2. Verify prerequisite schema against the current production animal, breeds, entries, results, report artifact, and Breeder link tables. Apply the migration through the normal migration workflow, then deploy `herdmaster-api` with its checked-in configuration. Do not replay all historical migrations into an existing hosted project blindly.
3. Run Supabase security/performance advisors and inspect notices associated with the new objects. Both new tables intentionally have RLS enabled and no client policies; only the service role can access them. Check that authenticated and anonymous roles cannot invoke any of the three RPCs.
4. Create a verified sandbox user. In that signed-in user's context, issue a connection using `/v1/connections` with explicit consent. Send its token to the authorized HerdMaster sandbox account through the agreed secure channel. There is no finished consent UI or OAuth flow in this version; token issuance is a developer-assisted pilot operation.
5. Exercise the actual deployed HTTP endpoints, report storage, rotation, and revocation with HerdMaster. Confirm all identifiers map to the intended account. Keep sandbox credentials separate from production credentials.
6. Complete the pilot before activating HerdMaster account connections. Add a user-facing connection UI and automatic authorization flow before general availability. Agree on quotas, polling, withdrawal handling, and any incremental/webhook requirements before scaling beyond the pilot.

Connection creation/revocation and partner exchange routes are implemented; automatic pulling from HerdMaster, OAuth, webhooks, withdrawal events, per-token quotas, and a general-availability connection UI are not implemented.
