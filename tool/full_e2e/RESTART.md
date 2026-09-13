# Fresh event rehearsal

Keep the original failed fixture and its evidence. Recovery and diagnostic bursts
use the isolated capacity clone; it is not a clean full-event starting point.

The tracked launcher archives a clean commit, builds the report worker from that
archive, retains the previous local volumes, starts a new unlinked local project,
and verifies disk space, migration hashes, queue scheduling and capacity. It
prepares the event but does not run its workload.

```sh
python3 tool/full_e2e/prepare_event.py RUN_NAME PROJECT_SUFFIX 4 PREVIOUS_WORKSPACE
```

Use unique lowercase names and the previous `/tmp/ringmaster-show-full-e2e-*`
workspace. Scale 4 means 102,844 entries, 10,112 exhibitors, 1,000 purchasers,
440 judging tables, 120 check-in sessions, 40 admins and 60 superintendents.
Registration uses email codes delivered to the local mailbox. Stripe, Club and
email delivery are emulated. CPU and RAM remain unchanged.

The capacity contract is Auth 20 connections, REST 30, gateway 8,192 connections
and a 30-second Auth request deadline. The launcher and supervisor verify the
effective settings; they must not silently revert to CLI defaults.

After reviewing `start-checks.json` and approving the full workload:

```sh
python3 tool/full_e2e/supervise_event.py output/full_e2e/RUN_NAME
python3 tool/full_e2e/finish_event.py output/full_e2e/RUN_NAME
```

Supervision stops at the first failed stage. The stages cover registration,
preprinting, two check-in days, judges' printing, two judging days, navigation,
scope completeness, closeout and reconciliation. Finishing covers delivery,
PDF content, contact coverage and backup restoration. Final reports are generated
after both Open and Youth judging finish, with the existing two-hour deadline.

For a fresh functional check, add `--smoke` to preparation and use the same two
commands. This creates 120 entries and 24 exhibitors with two judges and two
support staff. It exercises the same check-in percentages, workflows and report
audits; it does not certify capacity. Navigation concurrency remains a full-run
check. Failed outputs are preserved rather than overwritten.

Local verification does not deploy production. A later production release must
apply the durable queue and cart-item index migrations before the Stripe webhook
and payment confirmation UI. The payment scheduler must be active and its health
checked. Rebuild the report worker from the release source.
