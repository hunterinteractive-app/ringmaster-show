# Closeout dashboard queue-growth fix — September 12, 2026

**Fixed and verified locally.** The original failure was reproduced under
concurrent staff reads, and the patched dashboard passed the same queue-growth
transition. The earlier full-event run remains recorded as failed; final report
generation, delivery and recovery have not been rerun by this targeted test.

## Cause and change

The dashboard was polled repeatedly while the report queue was empty. Its cached
query plans continued estimating one row after first finalization inserted
11,695 artifacts and 11,693 tasks. A captured plan repeatedly scanned the queue
and a materialized artifact result: approximately 136.7 million rejected join
pairs plus 68.4 million rejected anti-join pairs. The base query alone took
24.31 seconds in an isolated diagnostic; the complete old call reached its
45-second diagnostic limit. Actual authenticated API calls retained their
original eight-second limit and reproduced SQLSTATE `57014`.

Migration `20260912145011_replan_closeout_dashboard_after_queue_growth.sql`
converts the existing SQL dashboard helper to PL/pgSQL with the same query and
uses `plan_cache_mode=force_custom_plan` within the helper and scoped dashboard
call chain. The planner can then account for the newly populated tables on each
call. A cache-setting-only candidate still failed because the original SQL
helper retained its own cached plan; both parts of the final change are needed.

PostgreSQL documents how PL/pgSQL reuses prepared statements and can select
custom or generic plans in its [plan-caching documentation](https://www.postgresql.org/docs/17/plpgsql-implementation.html#PLPGSQL-PLAN-CACHING).
The root-cause evidence and timings above come from this local reproduction.

The eight-second statement timeout, 20-connection REST pool, 20-connection Auth
pool, pagination, report scopes, return values and access controls are preserved.
The planning setting returns to its previous value when the function exits;
it is not a global database setting. No extra indexes or restarts are required
by the fix.

## Verification

The regression builds private copies of the report tables and dashboard
functions, then warms **all 20 REST backends** through authenticated API calls.
It populates the queue while **20 admins and 30 superintendents** read concurrently.
There is no service restart, manual ANALYZE or schema change between warmup and
the populated-queue measurements. Autoanalyze is disabled only on the diagnostic
tables to keep the stale-statistics case reproducible. Temporary schemas and
probe RPCs are removed afterward.

| Check | Result |
| --- | --- |
| Original code under queue growth | Failure reproduced: 25 statement timeouts |
| Patched code under queue growth | 416 requests, zero errors or timeouts |
| Patched dashboard after growth | p95 1.043 s; maximum 1.101 s |
| Isolated patched transition | Complete call 153 ms |
| Full dashboard JSON comparison | All 10 cases identical |
| Access restrictions | Anonymous, reporting clerk and unrelated-show access denied |
| Migration replay | Idempotent |
| Original event data | Entry, payment, artifact, queue and finalization hashes unchanged |
| Function contracts and access | Arguments, return types, ownership, ACLs and security behavior preserved |
| Database advisors | 47 existing findings before/after; zero new findings |
| Source checks | Python compilation, CLI help and `git diff --check` passed |

The ten content cases include combined/Open/Youth scopes, unfiltered/rabbit/cavy
requests, exhibitor-report pages including the final partial page, deferred ARBA
artifacts, and page-limit/offset boundaries. The trial logs retain every failed
baseline request; the fixed trial is separately recorded.

## Files and next step

Implementation: `supabase/migrations/20260912145011_replan_closeout_dashboard_after_queue_growth.sql`.
Repeatable test: `tool/full_e2e/verify_dashboard_queue_growth.py`; its README
explains how to reuse the saved original definitions on an already patched
fixture. Evidence is in `output/full_e2e/dashboard-fix-20260912/`.

Only the guarded local synthetic database was patched. No production deployment,
commit or push was performed. The prior source snapshots and failed full-event
logs remain preserved.

The next validation is the full closeout rehearsal: report generation within two
hours, final PDF/leg correctness, worker interruption and recovery, report
delivery, navigation and backup restoration. This targeted repair does not
claim those unfinished stages passed.
