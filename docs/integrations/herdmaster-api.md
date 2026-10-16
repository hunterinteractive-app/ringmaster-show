> Current matching behavior: see [animal-match-confirmation.md](animal-match-confirmation.md). Possible matches are held for owner confirmation in Show and returned as `pending_reviews`; no duplicate is created. Existing-animal listing requires new explicit `animals:read` consent.

# RingMaster and HerdMaster API integration

Version 1.0 • Partner pilot specification • October 12, 2026

HerdMaster supplies animal records; RingMaster handles show entry, checkout, judging, and show results. Exhibitors authorize each connection and complete their entries in RingMaster. The RingMaster implementation is deployed to RingMaster Show production. Live routing and authentication checks and rollback-only production database checks have passed. HerdMaster-specific credentials and a partner sandbox have not been issued.

For the initial pilot, HerdMaster **sends animal updates to RingMaster and retrieves results from RingMaster**. This works without RingMaster knowing HerdMaster's API endpoints. Automatic animal pulls and OAuth require HerdMaster's documentation and are outside this version. The machine-readable contract is [herdmaster-openapi.json](herdmaster-openapi.json).

## API address and endpoints

The base URL is `https://yzjoycrvqkyfrksmaixf.supabase.co/functions/v1/herdmaster-api`. Sandbox and production must use separate projects and credentials. All paths below are relative to that base URL.

| Method | Path | Authorization | Purpose |
| --- | --- | --- | --- |
| POST | `/v1/connections` | RingMaster user session JWT | Authorize an account connection and issue a token |
| DELETE | `/v1/connections/{connection_id}` | RingMaster user session JWT | Revoke a connection |
| POST | `/v1/animals` | Connection token | Send animal updates |
| GET | `/v1/catalog?after={uuid}` | Connection token | Retrieve accepted breed names and grouping modes |
| GET | `/v1/results?after={uuid}` | Connection token | Retrieve current eligible results for linked animals |
| GET | `/v1/reports?after={uuid}` | Connection token | Retrieve account-owned exhibitor and leg reports |

## Account authorization

Connection management requires a signed-in RingMaster user with a verified email. RingMaster validates the user's session; email matching alone grants no access. The pilot uses explicit user consent and manual token handoff through a secure channel. No redirect, token exchange, or automatic OAuth flow is supplied in this version. HerdMaster must not collect the user's RingMaster password or session JWT.

The user authorizes animal synchronization, result retrieval, and **their owned exhibitor and leg reports**, which may contain animals beyond those linked to HerdMaster. All three permissions are bundled for the pilot; individual scope selection is not implemented.

Create a connection in the authenticated RingMaster context:

```http
POST /v1/connections
Authorization: Bearer <ringmaster-user-session-jwt>
Content-Type: application/json

{
  "herdmaster_account_id": "HM-account-789",
  "consent": true
}
```

Example response (`201 Created`; token shown as a placeholder):

```json
{
  "connection_id": "11111111-1111-4111-8111-111111111111",
  "token": "<issued-rmhm-token>",
  "token_type": "Bearer",
  "expires_at": "2027-01-10T14:00:00.000Z",
  "scopes": ["animals:write", "results:read", "reports:read"]
}
```

New access tokens expire one hour after issuance. Initial authorization and POST /v1/connections/refresh return rotating refresh credentials with a rolling 180-day expiry. Persist both replacement tokens and expiry timestamps atomically; serialize renewal across workers. Never blindly retry a used or uncertain refresh credential. Legacy access tokens retain their original expiration; legacy connections need reauthorization to obtain refresh credentials. RingMaster stores a hash; HerdMaster stores the token securely on its server. A token belongs to one RingMaster user and one declared HerdMaster account. RingMaster cannot independently verify the HerdMaster account ID before HerdMaster's authentication contract is available; HerdMaster must ensure the recipient is signed into that account.

Repeating creation for the same user and HerdMaster account rotates the token, immediately invalidating the old token while preserving animal links. Do not blindly retry an uncertain creation response: a retry rotates again. Reauthorize and distribute the newly returned token deliberately.

Revoke using the owning user's session:

```http
DELETE /v1/connections/11111111-1111-4111-8111-111111111111
Authorization: Bearer <ringmaster-user-session-jwt>
```

Response: `200 {"revoked":true}`. Subsequent partner requests fail with `401`. Revocation stops data exchange; previously saved animals, show entries, and downloaded reports remain. Already issued report URLs expire within five minutes. An in-flight request authorized before revocation may finish.

## Animal fields and mapping

Send `POST /v1/animals` with `{"animals":[...]}`. Each batch is atomic and contains at most 500 records. The maximum request body is 1 MiB. Omitted animals are unchanged; this is an update feed, not a replacement snapshot.

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | Required permanent HerdMaster animal ID; 1–200 characters; unique within the account |
| `active` | boolean | Required; `false` marks an animal inactive |
| `updated_at` | string | Required ISO 8601 timestamp including `Z` or a numeric time zone; increase whenever the source record changes |
| `species` | string | Required for active animals: `rabbit` or `cavy` |
| `tattoo` | string | Required for active animals; tattoo or ear identification |
| `breed` | string | Required for active animals; accepted catalog breed name; matched without case sensitivity and stored with catalog spelling |
| `sex` | string | Rabbit: `Buck` or `Doe`; cavy: `Boar` or `Sow`; case sensitive |
| `variety` | string or null | Optional variety/color; missing values require entry review where the show requires them |
| `pattern` | string or null | Optional pattern used when grouping lop varieties |
| `dob` | string or null | `YYYY-MM-DD`; omitted or `null` means unknown |
| `name` | string or null | Optional animal display name |
| `ringmaster_animal_id` | UUID or null | Optional confirmed existing Show animal to link on first active import |

All text fields are limited to 200 characters. Strings are trimmed; optional strings may be omitted or `null` but cannot be blank. Extra fields are ignored. Ownership comes from the token, so no owner ID is accepted in animal records. An inactive update needs only `id`, `active`, and `updated_at`.

Retrieve `/v1/catalog` to map HerdMaster breed names to RingMaster names. `variety_mode` may be `null` when unavailable. For a breed with `variety_mode=lop_grouped`, a variety containing Broken, Tri-color, or Tricolor, or a pattern containing Broken, maps to `Broken`; other supplied varieties map to `Solid`. Other variety values are preserved. This endpoint does not supply a complete variety dictionary or validate show-specific eligibility; the exhibitor reviews that during entry. Weight, pedigree, registration numbers, medical records, and breeding history are outside this API.

Example update:

```http
POST /v1/animals
Authorization: Bearer <issued-rmhm-token>
Content-Type: application/json

{
  "animals": [{
    "id": "HM-12345",
    "active": true,
    "updated_at": "2026-10-12T14:00:00Z",
    "species": "rabbit",
    "tattoo": "ZH24",
    "breed": "Mini Rex",
    "variety": "Black",
    "pattern": null,
    "sex": "Buck",
    "dob": "2026-03-15",
    "name": "Midnight"
  }]
}
```

Response: `200 {"applied":1,"ignored":0}`.

Older timestamps are ignored. Repeating the same normalized data and timestamp is ignored. Different data with the same timestamp produces `409`; resend with a newer source timestamp. Duplicate IDs in a batch produce `422`. A failed batch applies none of its animals.

Stable IDs maintain animal identity even when a name or tattoo changes. RingMaster does not automatically merge animals by tattoo. Linking an existing animal requires its confirmed RingMaster UUID and matching ownership; an animal already linked to another connection or the existing Breeder bridge cannot be relinked. The optional ID is used only for the first active link.

Inactivation hides animals created by this integration and preserves show history. Existing Show animals explicitly linked by the user remain in their Show animal list. Send an inactive update for sales, transfers, deletions, or archives. Send a newer active update to restore availability. Updating animals does not rewrite historical entries. Changes become visible through the existing Show animal list; this version does not make a HerdMaster network call when the entry screen opens.

## Result fields and sample response

Request `GET /v1/results` with the connection token. Only entries linked to this connection and owned or claimed by its RingMaster user are returned. Test and demo shows are excluded. An entry is eligible when its exhibitor has a generated, current exhibitor report with a stored file. This matches the existing breeder export gate; it does not independently certify that a show is finalized.

Example response (values are illustrative):

```json
{
  "data": [{
    "entry_id": "22222222-2222-4222-8222-222222222222",
    "herdmaster_animal_id": "HM-12345",
    "ringmaster_animal_id": "33333333-3333-4333-8333-333333333333",
    "show_id": "44444444-4444-4444-8444-444444444444",
    "show_name": "Example Rabbit Show",
    "show_date": "2026-10-12",
    "location": "Example Show Hall",
    "exhibitor_id": "55555555-5555-4555-8555-555555555555",
    "species": "rabbit",
    "tattoo": "ZH24",
    "animal_name": "Midnight",
    "breed": "Mini Rex",
    "variety": "Black",
    "sex": "Buck",
    "class_name": "Senior Buck",
    "placement": "1",
    "special_awards": null,
    "result_status": null,
    "is_shown": true,
    "is_disqualified": false,
    "disqualified_reason": null,
    "scratched_at": null,
    "is_fur": false,
    "fur_placement": null,
    "fur_award": null,
    "result_details": [],
    "entry_awards": []
  }],
  "next_after": null,
  "sync_mode": "full_scan"
}
```

`entry_id` is the upsert key in HerdMaster; `herdmaster_animal_id` selects the animal. A single animal can have multiple entries and results. Nullable result fields mean not recorded; do not interpret null as zero, a loss, or an awarded leg. `placement` is text, preserving placing labels. `legs_awarded` is a boolean indicating whether a leg was recorded, not a numeric count. `result_details` contains recorded `placing_label`, `award`, and `legs_awarded` values. `entry_awards` contains recorded `award_code` values. Preserve unfamiliar codes; do not calculate awards or legs from placement alone. `special_awards` preserves the stored JSON value.

## Pagination and corrections

Results, reports, and catalog endpoints return up to 500 records in UUID order. When `next_after` is non-null, request the same endpoint with `?after=<next_after>`. A full page can require a final empty page.

Start each synchronization run **without** `after` and scan to the end. A UUID cursor is a page position, not a change watermark. Rescanning returns corrected results under the same entry IDs; upsert those records. For the pilot, polling every 15 minutes is a reasonable starting point to agree with HerdMaster. Webhooks and an incremental revision feed are not implemented.

Pages are live reads, not a frozen snapshot. Missing results can indicate temporary report regeneration or loss of eligibility; this version does not emit withdrawal events. Preserve historical results and flag missing records for review rather than deleting them automatically. Repeat the scan to recover changes that occur during pagination. Do not reconcile a failed or partially completed scan.

## Report downloads

`GET /v1/reports` returns authorized current exhibitor and leg report metadata:

```json
{
  "data": [{
    "report_id": "66666666-6666-4666-8666-666666666666",
    "show_id": "44444444-4444-4444-8444-444444444444",
    "show_name": "Example Rabbit Show",
    "show_date": "2026-10-12",
    "report_name": "exhibitor_report",
    "exhibitor_id": "55555555-5555-4555-8555-555555555555",
    "file_name": "exhibitor-report.pdf",
    "generated_at": "2026-10-12T18:00:00Z",
    "download_url": "https://<ringmaster-project>.supabase.co/storage/v1/object/sign/<signed-path>",
    "download_expires_in": 300
  }],
  "next_after": null,
  "sync_mode": "full_scan"
}
```

Download URLs are bearer capabilities valid for five minutes. Download promptly over HTTPS; request the report feed again for a fresh URL. Do not log or share tokens or signed URLs. A regenerated report may have a new report ID; use the current feed to identify current documents.

## Errors and retries

Errors have the shape `{"error":{"code":"unauthorized","message":"Connection token is invalid, expired, or revoked."}}`.

| HTTP status | Meaning | Action |
| --- | --- | --- |
| 400 | Malformed JSON | Fix the request |
| 401 | Missing/invalid user session or invalid, expired, revoked connection | Reauthorize; do not keep retrying the credential |
| 404 | Unknown endpoint or connection not owned by the user | Check the path or connection ID |
| 405 | Wrong HTTP method | Use the documented method |
| 409 | Same animal timestamp with different data | Correct the source version and resend |
| 413 | Body exceeds 1 MiB | Split into smaller batches |
| 415 | Incorrect content type | Send `application/json` |
| 422 | Invalid fields, breed, ID, or linking request | Correct the mapping or split a failed batch to isolate the record |
| 503 | Database, storage, or server temporarily unavailable | Retry with exponential backoff |

The application enforces batch/body limits but does not yet enforce a per-token requests-per-minute quota. Handle platform `429` and gateway failures with backoff and honor `Retry-After` when supplied. GETs and identical animal updates are safe to retry. Connection creation rotates credentials, so it requires deliberate recovery as described above.

## What we need from HerdMaster

To complete the pilot, please provide:

1. A technical contact and confirmation that HerdMaster can send animal updates and retrieve RingMaster results using this contract.
2. A sandbox account, sample animal records, and the permanent account and animal ID definitions.
3. The breed, variety, pattern, species, sex, and inactive-status values HerdMaster uses, so we can finalize mappings.
4. Confirmation that updates carry increasing source timestamps and that sales, transfers, archives, and deletions can send inactive records.
5. How account owners, households, youth exhibitors, and ownership transfers are represented.
6. How HerdMaster will store multiple entries per animal, corrected placements, award codes, legs, and PDFs.
7. A secure process for the authorized user to hand the pilot connection token to their signed-in HerdMaster account.

If HerdMaster prefers RingMaster to pull animals, also provide API base URLs, animal endpoint documentation, pagination, change/deletion behavior, rate limits, authentication documentation, and sandbox credentials through a secure channel. OAuth documentation is needed for a later automatic account-linking flow. None of these details are assumed in the pilot API.

## Test access and rollout

The production API is live at the address above. Partner credentials and sandbox access have not been issued. Once HerdMaster supplies its account and authorization details, a verified RingMaster user can authorize a connection and securely provide its token to the intended HerdMaster account. Credentials are never included in this document. Use the sample requests above or the examples in [herdmaster-openapi.json](herdmaster-openapi.json).

The pilot should verify authorization, catalog mapping, first import, repeat/stale updates, explicit animal linking, inactivation, a test entry, published results, a correction, report download, token rotation, and revocation. Test/demo shows are intentionally excluded from the export; use a synthetic sandbox show with its test/demo flags off to exercise the export gate.

HerdMaster-specific activation follows account authorization and joint testing. See [herdmaster-rollout.md](herdmaster-rollout.md) for implementation and deployment checks.


## Current contract and manual refresh

The current machine-readable contract is herdmaster-openapi.json version 1.2.0. Token rotation is deployed in production; manual-refresh completion metadata and the animal-sync gateway are staged changes pending rollout. See manual-animal-refresh.md and the OpenAPI webhooks section for Joe’s callback requirements. The My Animals and Enter Show controls share successful per-provider timestamps and never trigger herd pulls on screen load.
