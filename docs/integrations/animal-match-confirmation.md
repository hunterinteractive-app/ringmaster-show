# Animal import confirmation

RingMaster Breeder, HerdMaster and Pedigree HQ use a shared Show-side confirmation queue. New source records are checked against the connected owner's existing nondeleted Show animals. A matching species plus a normalized tattoo or name suggests a possible match; a supplied Show ID also requires owner confirmation. Suggestions never merge records automatically.

My Animals and Enter Show display pending reviews and ask **Is this the same animal?** The owner can select **Use this animal**, **Create a separate animal**, or **Decide later**. Each choice shows the incoming fields and existing Show record. Linking permits source fields to update the existing animal but preserves its ID and entry history. Decide later writes no animal or decision. The queue keeps the source payload until reviewed or withdrawn by an inactive update/snapshot.

Confirmed links are persisted by provider connection and permanent external animal ID. Separate creates one new Show animal and saves that same mapping. Later imports skip confirmation and reuse the ID, even when name or tattoo changes. Reauthorization and token rotation preserve mappings. Missing mappings, stale review versions, ownership loss, unavailable targets, and revoked connections cannot silently create replacements. Existing links are preserved; this release does not retrospectively merge existing duplicates.

A Show animal linked to a different source is displayed as unavailable; it cannot be selected. This prevents competing source feeds from overwriting one record. Switching a record between integrations requires a deliberate future unlink/relink operation, not an automatic merge.

## Partner API

HerdMaster base route: `/functions/v1/herdmaster-api`.
Pedigree HQ base route: `/functions/v1/pedigreehq-api`.
Pedigree HQ uses `pedigreehq_account_id` at authorization and `pedigreehq_animal_id` in results. Credentials are opaque; both routes enforce their provider namespace, including renewal and revocation. Account IDs can be equal across providers without collisions.

`GET /v1/animals/existing?after=<uuid>` returns minimal matching fields, `ringmaster_animal_id`, `can_link`, and pagination. It requires **new explicit consent** to read existing Show animals; legacy connections receive HTTP 403 `consent_required` until reauthorized. New authorization includes `animals:read` with the existing write/results/reports scopes. Token renewal alone cannot expand consent.

`POST /v1/animals` still accepts normal source batches. Records with possible matches are held for owner review in Show instead of created. The response adds `pending_reviews` alongside `applied` and `ignored`; partners must not interpret a held record as imported. Unrelated validated records can still apply in the same request. Replay of an unchanged pending source remains pending and cannot create a duplicate.

This implemented protocol uses Show's authenticated `animal_import_review` RPC for review and resolution. The earlier proposed external `/v1/animals/preview` route and `match_decision` import field are **not implemented** and must not be used. A partner must never forge a user's confirmation by attaching an ID. Supplied IDs are suggestions until the owner reviews them in Show.

## Verification

- `supabase/tests/partner_animal_confirmation.sql` runs inside a rollback transaction with synthetic fixtures. It covers all three providers, saved IDs, repeat imports, separate decisions, stale review submissions, already-linked targets, owner isolation, and existing-animal consent.
- `test/animal_import_review_test.dart` covers the confirmation choices for every provider on a 360-pixel screen.
- `supabase/functions/herdmaster-api/provider_test.ts` covers cross-provider access/refresh rejection; handler tests cover validation and pagination.

Real HerdMaster and Pedigree HQ sender systems still need partner configuration, authorized credentials, and a joint test. Simulated payload tests do not certify those external systems. No real user's animal mappings are changed by the verification fixtures.
