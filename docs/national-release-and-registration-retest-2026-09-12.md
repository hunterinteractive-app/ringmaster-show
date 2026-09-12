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
