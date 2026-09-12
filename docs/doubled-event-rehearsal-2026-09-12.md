**51,422-entry rehearsal — stopped during registration**

The doubled local event reached its 500-purchaser final-day burst and failed the
registration gate. Seven of 5,056 purchasers did not finish, leaving 71 planned
entries unregistered. The runner stopped before printing, check-in, judging,
closeout, delivery and recovery. This is a failed registration rehearsal, not a
completed full-event pass or a measured maximum show size.

The workload was the prepared 51,422 entries and 5,056 exhibitors: Open
37,734/3,710 and Youth 13,688/1,346. All 270 staff accounts authenticated, with
20 admins and 30 superintendents reading dashboards throughout registration.
The first 29 compressed days completed without failed purchasers. The final day
contained 15,417 planned entries from 1,518 purchasers, up to 500 at once; seven
failed and 1,511 completed. Registration ran for about 3 minutes 27 seconds,
including setup; the final-day batch took 64.7 seconds.

| Failed operation | Purchasers | Observed response |
| --- | ---: | --- |
| Account lookup | 3 | HTTP 503 at the new 12-second upstream budget |
| Animal creation | 1 | HTTP 504, PGRST003: connection-pool acquisition timed out |
| Cart creation | 1 | HTTP 504, PGRST003 |
| Adding cart items | 1 | HTTP 504, PGRST003 |
| Checkout session | 1 | Connection-pool timeout returned as HTTP 400 |

The bounded lookup behaved as designed by returning within about 12 seconds,
but these three purchasers still stopped. The app's account lookup currently
invokes the function directly. The checkout catch block maps ordinary database
errors to HTTP 400; the shared payment helper discards the database error type
when it throws a plain Error. The existing checkout retry policy accepts
500/502/503/504, so the misclassified pool timeout was not retried. These are
specific recovery/error-handling gaps exposed by the larger burst.

Other transient payment calls recovered: nine checkout HTTP 502 attempts and
14 webhook attempts (12 HTTP 502, two HTTP 500). Every attempt remains in the
evidence. These recovered attempts are distinct from the seven failed purchasers.

**Entry and payment integrity**

A read-only reconciliation after the runner stopped checked every saved entry
against the expected identity, exhibitor, section, breed, variety, class, sex,
tattoo and paid status. It also compared payments and balances per completed
purchaser and checked unique cart, payment-session and provider-session identities.

| Reconciliation | Result |
| --- | ---: |
| Completed purchasers | 5,049 |
| Saved paid entries | 51,351 |
| Simulated paid amount | $256,755 |
| Duplicate paid cart/session records | 0 |
| Entry-field or completed-payment mismatches | 0 |
| Failed purchasers with a paid record | 0 |
| Planned entries absent because registration failed | 71 |
| Pending payment quote retained | 1, for $55 |
| Active carts retained | 2: one with 11 items, one empty |
| Downstream report tasks | 0 |

The incomplete registrations are preserved for recovery testing. Their earlier
steps vary: three created only an Auth account; one also created its exhibitor;
one created its exhibitor and animals; two reached a cart. No record was repaired,
replayed or deleted to improve the result. Real money and external providers
were not involved.

**Latency and capacity observations**

These are measurements for final-day purchasers only, including failed operations.

| Operation | p95 | Maximum |
| --- | ---: | ---: |
| Public signup | 5.34s | 8.49s |
| Account lookup | 6.49s | 12.03s |
| Checkout session | 8.58s | 16.97s |
| Signed payment callback | 12.31s | 20.96s |

All 3,939 admin/superintendent dashboard reads succeeded, though their whole-run
p95 was about 1.8 seconds and the slowest approached 9.2 seconds. There are no
220-table judging measurements from this attempt because judging never started.

The local REST pool is 10 connections with a 10-second acquisition timeout;
PostgreSQL allows 100 connections and sampled total usage peaked at 47. Auth
remained at or below its configured 20 connections during the measured event.
This shows pressure in the REST request path; it does not demonstrate exhaustion
of the database-wide connection maximum or identify a single slow SQL query.
The attempted live diagnostic arrived after automatic shutdown, so the pool
settings were confirmed after restarting the same local configuration for
read-only reconciliation. No query-contention snapshot from the peak is claimed.

The retained runtime log contains 52 Edge CPU-soft-limit messages. Sampled Edge
memory reached about 4.57 GiB, and Auth CPU was also high. These observations
justify separating Auth, Edge and database pressure in the next focused test;
they do not establish the cause of every failed request. Hosted capacity cannot
be inferred directly from this Mac's local Docker services.

**Before the next full attempt**

1. Preserve transient database failure types through checkout and return a
   retryable service error while retaining the same cart/payment attempt.
2. Add bounded, safe recovery for account lookup and interrupted registration
   steps. Verify resumption of the seven saved incomplete registrations without
   duplicate animals, cart items, quotes or payments.
3. Measure REST-pool wait and query latency during repeated 500-purchaser bursts,
   then test justified pool/query changes within a documented connection budget.
   Confirm zero failed final purchases before another full-event run.

The two-hour checkout target, later-day fee scenario, 220 judging tables, report
completeness and restoration all remain untested at this size. The extreme test
should follow a successful doubled run and a separate decision about its size.
No production deployment or capacity setting was changed during this attempt.
The local stack is stopped and its volumes are retained.

The tested source remains release `7ab2da3a4ddcc33c17d941203560ace864e01a65`
plus the previously prepared harness overlay. Frozen source, fixture inputs,
migrations and worker hashes were checked by the launcher. The frozen files
were not patched while the workload ran.

Evidence is retained under `output/full_e2e/double-event-20260912/`, particularly
`event/registration-day-30.json`, `event/registration-summary.json`,
`event/events.jsonl`, `event/checkout-http-failures.jsonl`,
`event/resource-samples.jsonl`, `registration-reconciliation.json`,
`final-day-metrics.json`, `retry-analysis.json`, `rest-pool-diagnostic.json`,
`phase-results.json` and `run-outcome.json`.
