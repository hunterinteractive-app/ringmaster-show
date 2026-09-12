# National release and fresh-registration retest — September 12, 2026

Release `ce77cf3c137f9b55f5b4d87ace8dc11257b54534` was committed and pushed.
The Cloudflare app deployment passed CI (run 34713603836). Supabase migration
`20260912191416` installed the four reviewed coop, dashboard and judging fixes.
Sixteen affected Edge functions deployed with their existing JWT settings.
Cloud Run revision `ringmaster-closeout-renderer-00044-jj4` serves 100% of
traffic and its authenticated health response identifies that source revision.
Worker capacity remains four CPUs, 4 GiB, request concurrency one and at most
26 instances. The production security and performance advisor counts did not
change. Existing advisor warnings remain; this was not a full security audit.

A read-only production transaction using an existing staff identity checked
seven August-show sections. Every new readiness result matched the unchanged
canonical validator; the breed indexes loaded and the stored report object
was visible under staff RLS. This is database authorization evidence, not a
signed-in browser or authenticated Storage HTTP download test. The public app
shell also loaded. Production data, payments and email were not load-tested.

## Fresh 51,422-entry run R7

A new unlinked local project bootstrapped 233 frozen migration files. The show
was prepared with no entries or payments. A supplementary prestart count query
referenced a nonexistent `payments` table and failed without mutation; the
preparation guard and bootstrap establish freshness. All 1,494 frozen source
file hashes and the approved workload were independently checked.

Days 1–29 passed. The final-day burst had 139 failed purchasers: 72 checkout
HTTP 400 responses, 65 closed connections and two failed payment callbacks.
The original failed phase and its incomplete registrations remain preserved.
It was not continued or relabeled as a full-event pass.

The runner had silently reset the preflight REST pool from 20 connections to
10. The local gateway reached its 2,048-connection ceiling. The capacity helper
now defaults to the intended 20 and saves explicitly selected budgets so a
later startup cannot revert them. Two real configuration calls confirmed that
20 REST and 20 Auth connections persist; gateway and database limits stay the
same.

The SDK also serializes a thrown fetch exception into an error object with an
empty code, losing the `instanceof` identity. The transport exception now has
an explicit name; recognition of that exact serialized exception preserves
HTTP 503 through the payment and account-lookup handlers. Database permission
and validation errors remain non-retryable. The Auth SDK's equivalent
zero-status transport error is likewise classified as a service outage.
A real SDK regression confirms that an ambiguous database write is sent once.

## Focused 500-purchaser retest

The retained local fixture received a separate cohort of 500 new purchasers,
with 20 admins and 30 superintendents active. All 500 completed; all 5,061
entries were paid, with exactly 500 provider sessions/payments and no remaining
balance. The burst took 23.506 seconds, with zero pool timeouts and at most 57
database connections. A temporary checkout 503 and retried payment callbacks
recovered. This focused pass does not replace a fresh full-event rehearsal.

The extreme profile is verified offline: 102,844 entries, 10,112 exhibitors,
1,000 purchasers, 440 judging tables, 120 check-in sessions, 40 admins and
60 superintendents. It retains the original percentages and 7,200-second
checkout-generation deadline. It has not been run yet.

Raw release evidence: `output/full_e2e/national-release-20260912/`.
Failed full run: `output/full_e2e/fresh-51k-r7-20260912/`.
Focused retest: `output/full_e2e/r7-registration-repair-20260912/`.

## Sustained arrivals after the focused burst

Follow-up source `687671b1180096a3f1c592b92ad31d00bbc4591f` deployed all
16 affected Edge functions; app CI run 34714618676 passed. Eighteen focused
SDK/payment tests passed. No database or report-worker change was required.

The new R8 full event retained the correct 20-connection REST pool. Days 1–29
passed, but the final day's 1,518 purchasers at concurrency 500 produced
50 failures: 46 closed connections and four exhausted HTTP 503 requests.
The erroneous checkout HTTP 400 classification did not recur. Kong logged
that its 2,048 worker connections were insufficient. The failed phase is
preserved at `output/full_e2e/fresh-51k-r8-20260912/`.

The next full-event comparisons use one local gateway worker with 4,096
connection slots and an 8,192 open-file limit. Both the 51k and 102k runs
will use this same budget. Database connections and report-worker capacity
remain unchanged. This is an explicit local infrastructure adjustment;
the earlier 2,048-slot result must not be described as passing sustained load.

## Gateway verification and retained local storage

The CLI's embedded Nginx configuration hard-coded 2,048 connections, so an
environment variable alone did not apply the intended increase. Source
`9d2ec1641e3cd990a587f30ee86125706ae64654` updates the recognized events block,
preserves the rest of the generated configuration and rejects unknown or
ambiguous templates. Two focused tests passed; the running gateway reports
4,096 connections and an 8,192 open-file limit. CI run 34715252088 passed.

R9 then stopped during registration day four because the local Docker disk
was full (Postgres 53100), with 90 failed purchasers. This was a local storage
capacity failure, not an application throughput result. Its evidence and
database remain preserved; no dependent event stages ran.

Four inactive synthetic report-storage volumes were copied to host TAR
archives. All 49,957 regular files were independently SHA-256 checked against
the originals and each archive was sealed with its own checksum before the
inactive Docker copies were removed. This preserved 28,600,643,072 bytes of
report data; no database volume was removed. The archive directory includes
restoration instructions, and the affected old workspaces have a marker
requiring their report storage to be restored before reuse.

Archive evidence: `output/full_e2e/cold-report-storage-20260912-r2/`.
R9 evidence: `output/full_e2e/fresh-51k-r9-20260912/`.
Fresh preparations now have a free-space preflight before loading workload:
10 GiB Docker / 12 GiB host for 51k, and 18 GiB Docker / 20 GiB host for 102k.

## Fresh 51,422-entry run R10 — checkout passed; delivery recovered separately

R10 started with zero convention entries, exhibitors and payments, using
233 frozen migrations and source `9d2ec1641e3cd990a587f30ee86125706ae64654`.
The worker binary matches the deployed worker's source inputs. Its local
SHA-256 is `fbb431dd8d4a73b048418969ee9a201bab8c154c32079dc6d3fd8f77beeba147`.
At preparation, Docker had 26.9 GiB free and the host 44.7 GiB free.
The Mac has 10 logical CPUs and 24 GiB RAM; Docker reports 10 CPUs and
8,214,851,584 bytes of memory. The report processes run on the host. Both
scales use Auth/REST pools of 20, database maximum 100 connections, one
4,096-connection gateway worker, and four report processes with four render
slots each. The injected worker failure leaves three processes running.

Registration passed: 5,056 exhibitors, 51,422 entries, all paid. The final
day's 1,518 purchasers and 15,417 entries completed at concurrency 500 in
63.53 seconds, with no failed purchasers. Temporary upstream responses
recovered through the normal bounded retry path.

All preprint documents passed exact entry-coverage checks. The two-day
check-in simulation approved 22,112 changes with zero failed operations,
including later-day fees while preserving earlier payments. The four
judges' print jobs completed in about seven minutes and passed all coverage
checks: 47,308 active animals, updated ear numbers and no scratched animals.
First and last pages of all seven print packs were visually reviewed.

Both simultaneous judging days passed with 220 tables, 20 admins and
30 superintendents. All 47,308 active entries received results; repeated
saves passed, both sections passed canonical readiness, and QR/manual
navigation and the full judging scope audit passed. Finalization began
only after both sections were complete.

All 11,693 checkout reports generated in 1,723.449 seconds (28 minutes
43 seconds), including finalization and the injected worker failure. They
were ready 1,759.184 seconds after judging completed (29 minutes 19 seconds),
including the intervening navigation/scope checks. Both measurements meet
the 7,200-second deadline. The two ARBA artifacts await delivery prerequisites.

Four tasks owned by the killed worker were completed by surviving workers,
each with exactly one additional attempt and no artifact-generation change.
The harness advanced only the dead worker's lease expiry; the survivors
invoked recovery through their normal polling loop. No manual requeue or
test-invoked recovery RPC was used. Replaying a valid completion succeeded,
and a changed checksum was rejected.

All 165,628 measured staff reads/dashboard requests during closeout passed.
Their 95th-percentile latencies were 19.51 ms for judging reads, 20.65 ms for
admin dashboards and 39.65 ms for superintendent dashboards.

Reconciliation passed all checks: 51,422 entries, 5,056 exhibitors, 108 award
assignments, placements, individual and aggregate points, 22,112 approved
changes, completed check-ins and every coop assignment. There were exactly
5,056 synthetic online payments totaling $257,110 and 5,067 synthetic cash
payments totaling $89,990. The combined ledger totaled $347,100 with zero due.

The original delivery phase completed 5,054 of 5,056 exhibitor sends. Two
bundles, for exhibitors 4,775 and 4,791, hit the Edge runtime's CPU hard limit
(HTTP 546). Each included about 4.14 MB of leg certificates. All 53 club
deliveries and the ARBA email succeeded. Local image-cache cleanup overlapped
the failed delivery phase, so an isolated repeat was required to assess the
failure. The original failed evidence remains unchanged; R10 is not labeled
an uninterrupted full-event pass.

The attachment encoder now uses native Base64 encoding of the exact byte
view. On an actual failed 4.14 MB attachment, the old loop took about 58–74 ms
and native encoding about 0.6–0.8 ms, with identical output. Six regression
tests passed, including offset byte views, a large binary attachment and
unchanged empty-leg handling. A controlled replay of 100 previously sent
large bundles passed on both versions: 22.69 seconds before, 9.83 seconds
after (the latter also includes recovery of the two incomplete sends).
The initial failures were not reproduced by that isolated baseline.
Both incomplete sends then passed with exactly one new provider message each.

After combining the preserved original captures with the two recovery
captures, all 5,110 messages and 6,193 attachments matched the database and
file hashes, with no missing, duplicate or unlogged deliveries. All 439
empty-leg placeholders were excluded from email. Recovery evidence is
separate at `output/full_e2e/r10-email-cpu-repair-20260912/`.

All 11,695 generated PDFs passed size/hash checks. Every exhibitor report's
animal population matched, as did all 1,016 earned leg certificates. The
392-page contact PDF contains all 5,056 contacts exactly once, with every
populated field intact. The 109 official reports passed population and judge
coverage checks, including all required judges on the ARBA continuation pages.

An additional date check found that the harness had generated ARBA reports
after the partial exhibitor delivery, leaving the exhibitor-delivery date
blank. The original PDFs are preserved with that omission. The delivery
script now stops before ARBA generation when a send or delivery-state write
fails. The official-report audit now requires both printed delivery dates;
it rejects the incomplete R10 sequence and passes the preserved fixture with
both dates recorded. This is a rehearsal sequencing correction, not a claim
that the original ARBA date fields passed.

Backup restoration passed: a 40,557,332-byte database dump restored into an
isolated database, every table and both private-function schemas matched,
and all 11,695 archived report files restored with matching hashes. This
does not certify hosted failover, ownership/ACL restoration or physical printing.

Six unused public Supabase image caches were removed after recording their
tags and digests, recovering about 5 GB inside Docker without removing
containers, databases or test artifacts. Evidence is in
`output/full_e2e/local-image-cache-cleanup-20260912/`.

Supabase documents [CPU-limit behavior and HTTP 546](https://supabase.com/docs/guides/troubleshooting/edge-function-cpu-limits).
The upcoming 102,844-entry run will use the optimized email path and stricter
delivery sequencing under the same workload and capacity budgets.
Evidence: `output/full_e2e/fresh-51k-r10-20260912/`.
