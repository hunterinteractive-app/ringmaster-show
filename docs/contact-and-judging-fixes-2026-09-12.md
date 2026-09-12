# Contact report and manual judging fixes — September 12, 2026

The two follow-ups from the doubled closeout rehearsal are fixed and passed focused local retesting. A related full-section validation timeout discovered during these checks is also fixed. No deployment, commit, push, real payment, or external email occurred.

The retained fixture contains **51,422 entries and 5,056 exhibitors**, with one Open and one Youth section. Tests used the same database and gateway budgets as the preceding closeout rehearsal: PostgreSQL maximum 100 connections, REST pool 20, Auth pool 20, and gateway 2,048 connections. Both sections had finished judging before report regeneration.

| Check | Result with final changes |
|---|---|
| Actual contact report | 5,056 contacts, 392 pages, 827,404 bytes; all names appear exactly once and all populated contact fields are present |
| Targeted worker generation | First successful retry: 6.93 seconds total, including 5.57 seconds loading and 1.22 seconds rendering; second regeneration: 6.85 seconds wall time |
| Current report inventory | All 11,695 artifacts generated; the earlier failed rehearsal evidence remains unchanged |
| Mixed-breed manual navigation | 220 clerks plus 20 admins and 30 superintendents: 5.84 seconds, zero failed requests |
| QR navigation | Same 270 sessions: 2.83 seconds, zero failed requests |
| Concentrated largest-breed navigation | 110 clerks loading 4,020 Open Netherland Dwarfs and 110 loading 1,372 Youth Netherland Dwarfs, plus 50 support sessions: 22.62 seconds, zero failed requests |
| Complete-read reconciliation | All 51,422 entry identities, animal identities, species, awards, and scratch flags matched across every breed and both complete sections |
| Full-section readiness | Open 299 ms; Youth 104 ms; exact agreement with the canonical validator |
| Access and negative-case checks | Anonymous/unrelated users denied; wrong section rejected; a missing BIS was detected inside a transaction that was rolled back |
| Regression checks | 33 related unit tests, 3 contact PDF tests, and the Chrome screen regression passed; changed app files passed analysis |

The contact PDF now uses fixed column widths and tables of at most 100 rows, so pagination does not repeatedly lay out thousands of remaining contacts. Headers, total contact count, and page numbers repeat. Empty reports remain valid. The worker's two-minute render cancellation deadline is unchanged. The PDF regression also covers 5,056 contacts with three address lines and populated phone numbers; that fixture produces 562 pages and rendered in about three seconds during the final test. Representative actual PDF pages were inspected visually.

Manual judging now opens a compact breed index. Clerks select a breed before animal rows load, and each request reads at most 250 rows with complete cursor pagination and existing bounded retries. Entry links and validation fixes fetch the exact target, then its section and breed. Species remain separate within breeds with overlapping names. All-breed viewing and full-section validation are explicit actions; selected-breed checks do not imply that the entire section has passed validation. Failed reads remain visible.

The concentrated test exposed eight raw pool-acquisition failures with an intermediate 1,000-row implementation. Returning manual pages to 250 rows eliminated those failures in the retest. The final concentrated test's slowest manual request was 9.57 seconds, so it demonstrates a tested workload rather than unlimited capacity. Its raw failures and the successful smaller-page run are both retained. No HTTP retries were added to the Python load harness to obtain the passing results.

Full-section validation previously repeated entry permission checks and exceeded the local authenticated role's eight-second statement timeout. The new staff endpoint checks show access once in a private, guarded helper, then calls the existing canonical validator. Public wrappers remain security invoker functions. The canonical validator and table RLS policies are unchanged, and database advisors reported the same 47 pre-existing findings with zero new findings.

Deploy both new migrations before publishing the updated app. Deploy the rebuilt report worker to use the PDF fix. The default **local** rehearsal worker binary has already been updated and its predecessor preserved. New migrations:

- `20260912181733_add_judging_breed_index.sql`
- `20260912183506_bound_staff_readiness_permission_checks.sql`

These are focused local retests, not a new timed full-event rehearsal or proof of hosted capacity. The historical local fixture lacks permissive Storage read policies, so an authenticated direct-download probe returned “Object not found”; file integrity was audited using the worker service role, as in the previous rehearsal. Hosted staff-download permissions remain outside this local test's coverage. No production Storage policies were changed. Physical printing and external delivery were not exercised.

Evidence is under `output/full_e2e/contact-navigation-fix-20260912/`: `navigation-page250-final/summary.json`, `largest-breed-page250/summary.json`, `scopes-final/judging-scope-audit.json`, `readiness-permissions-and-negative-case.json`, `canonical-and-rls-unchanged.json`, `advisor-comparison-final.json`, and `contact-regeneration-r2/`. The earlier full rehearsal is documented in `doubled-closeout-rehearsal-2026-09-12.md`; its original failure result was preserved.
