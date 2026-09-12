**Doubled full-event rehearsal — prepared, not started**

The next local synthetic rehearsal is prepared. The user requested that it wait
for an explicit start instruction. No registration, payment, check-in, judging,
printing, closeout or delivery workload has run. The isolated local services are
stopped with their volumes retained.

| Input | Prepared workload |
| --- | ---: |
| Open entries / exhibitors | 37,734 / 3,710 |
| Youth entries / exhibitors | 13,688 / 1,346 |
| Total entries / exhibitors | 51,422 / 5,056 |
| Simultaneous purchaser peak | 500 |
| Check-in clerks | 60 |
| Judging tables | 220: 110 QR and 110 manual |
| Admins / superintendents | 20 / 30 |
| Total staff during judging and closeout | 270 |
| Ear changes / other permitted sex changes / scratches | 15,427 / 2,571 / 4,114 |
| Checkout file-generation deadline | 2 hours |

All breed and class counts are twice the historical fixture. There is one Open
show and one Youth show with no exhibitor overlap. Ownership and outcomes remain
synthetic; one animal record per entry, including each meat pen, is not a physical
rabbit census.

The compressed month retains the original 25% / 45% / 30% arrival distribution:
75% in the final two weeks and 40% of that group on the final day. Whole purchaser
cohorts cause small rounding differences: the final day has 15,417 entries from
1,518 exhibitors, with up to 500 purchasing at once. That peak is a scaled test
assumption, not measured historical concurrency.

The ordered workflow remains registration, coop cards/check-in sheets, two days
of check-in, overnight judging packs, two days of simultaneous Open/Youth judging,
combined finalization, checkout rendering with continued staff reads, report
and ledger reconciliation, navigation checks, simulated delivery, complete PDF
and attachment audits, and backup restoration. Finalization starts only after
both sections finish judging. One of four report workers will be interrupted to
verify automatic recovery within the same two-hour generation clock.

Thirty percent of entries have ear corrections, 5% have permitted sex corrections,
and 8% are scratched. The selections are disjoint. Sixty first-day exhibitors
return for one of their already-planned charged changes on day two, after paying
their first fees. This checks the later-fee fix while preserving the percentages
and total fees. The plan expects $257,110 in simulated online entry payments and
$89,990 in simulated cash change fees, using the prior $5-per-entry/$5-per-charged-
change assumptions. Scratches are free. These are workload inputs, not event policy.

Server capacity is unchanged: Auth pool 20, four report workers with 16 concurrent
renders before the intentional worker interruption, and the same local database
image and runtime mitigation. Client concurrency doubles. Physical printing,
real provider settlement, actual emails, rendered-browser concurrency, and hosted
production capacity are outside this local rehearsal.

Preparation checks passed: four offline fixture/profile tests, Python compilation,
Flutter analysis of the print harness, and diff checks. The database has 220
configured judges but zero event exhibitors, entries, payments or queued reports.
The new fee-table RLS restrictions and all three private-helper callers are present.
No app logic, production configuration or production data was changed for setup.

The release source is `7ab2da3a4ddcc33c17d941203560ace864e01a65`, with the local
harness changes that make fixture counts, staffing, payment reconciliation and
judge-list audits scale from the manifest. The complete source is copied into
`output/full_e2e/double-event-20260912/source/`; source/migration/input hashes and
the compiled worker checksum prevent silent changes before execution.
The harness edits are local and have not been committed or pushed.

The isolated workspace is `/tmp/ringmaster-show-full-e2e-double-20260912`, project
`ringmaster-show-full-e2e-double-0912`. Evidence and the prepared launch script live
under `output/full_e2e/double-event-20260912/`. Running `start_when_requested.py`
without arguments only previews the plan and starts no services. After explicit
user instruction, run it with `--start` using a Python environment containing
`pypdf` (the bundled runtime was verified). It verifies the frozen files and empty
show, starts only this stack, runs each phase in order, stops on a failed phase,
and retains evidence. It stops the local services afterward without deleting data.

The subsequent extreme-capacity test is not configured or scheduled. Choose its
size using the doubled run's measured pressure points and the user's direction.
