**RingMaster Show — completed large-rehearsal breakdown and live-event planning**\
Prepared September 13, 2026. All storage quantities below use decimal MB/GB; RAM uses binary GiB where the source reports it.

The most recent large baseline is **51,422 entries and 5,056 exhibitors**, twice the supplied historical convention counts. The September 12 R10 run passed registration, all printing, check-in, simultaneous Open/Youth judging, navigation, finalization, checkout report generation, and reconciliation. Two exhibitor emails required a later recovery, and ARBA delivery-date sequencing was corrected and tested separately. Its original finishing status remains failed; the accurate description is **core event passed, delivery completed after recovery**, not an uninterrupted full-event pass.

The latest uninterrupted event on the newest source was the September 13 **120-entry / 24-exhibitor functional rehearsal**. It passed delivery, report audits, and restoration, but is not a capacity measurement. The 102,844-entry run is retained as a failed capacity experiment: its local Edge Functions container ran out of RAM during the 1,000-purchaser final-day rush. No additional large run was started for this report.

**Workload in the 51,422-entry baseline**

| Item | Tested workload |
| --- | --- |
| Show sections | One Open A and one Youth A |
| Open | 37,734 entries / 3,710 exhibitors |
| Youth | 13,688 entries / 1,346 exhibitors; no Open/Youth exhibitor overlap |
| Registration | Compressed 30-day sequence: approximately 25% early, 45% before the final day, 30% on the final day |
| Final-day registration | 1,518 purchasers / 15,417 entries; peak 500 simultaneous purchasers |
| Check-in | Two day batches; 60 clerks, 20 admins, 30 superintendents |
| Changes | 15,427 ear-number changes, 2,571 sex changes, 4,114 scratches; 22,112 approved changes |
| Fees | $5 per ear/sex change; scratches free; 60 exhibitors returned for another charged change on day two |
| Judging | 220 tables: 110 QR / 110 manual; 20 admins and 30 superintendents alongside them |
| Animals judged | All 47,308 active animals after scratches; Open and Youth together over two batches |
| Final reports | Generated only after both sections completed judging |
| Deadline | Two hours for checkout file generation; physical printing excluded |

These are synthetic API workloads. R10 used public signup/password sign-in; the newer payment preflight and the latest small event also exercised email-code login. Actual human judging, typing, travel between tables, a month of uptime, and a venue network were not compressed into these timing measurements.

**Stage timings, RAM, CPU, and storage**

There is a measurement gap: **R10 did not retain per-stage RAM peaks or CPU utilization samples.** It recorded the machine allocations, timing, generated file sizes, and operation latencies. Earlier runs have partial container samples, but those are different runs and omit host-side PDF workers. They cannot fill in R10's missing measurements.

`N/R` means not recorded, not zero. The storage column reports generated output, not peak temporary disk usage, disk I/O rate, or database growth. Database growth by stage was also not recorded. Stage times below come from the supervisor, except the explicitly timed closeout deadline and the separately recorded recovery exercise.

| Stage | Measured elapsed time | Peak RAM | CPU utilization | Verified output / storage |
| --- | ---: | --- | --- | --- |
| Entire compressed registration month | 3m 07s | N/R | N/R | 51,422 paid entries / 5,056 exhibitors; stage database growth N/R |
| Final-day rush, included above | 1m 04s | N/R | N/R | 15,417 entries / 1,518 purchasers at peak 500 |
| Coop cards + Open/Youth check-in sheets | 2m 57s | N/R | N/R | 17,912 pages; 60.99 MB of PDFs |
| Preprint coverage audit | 28s | N/R | N/R | Every planned animal present in its expected pack |
| Both check-in days | 4m 54s | N/R | N/R | 22,112 approved changes; all exhibitors checked in |
| Check-in day 1, included above | 2m 09s | N/R | N/R | 110 concurrent staff sessions |
| Check-in day 2, included above | 2m 42s | N/R | N/R | 110 sessions; later fees preserved previous payments |
| Judges' sheets + comment cards | 6m 43s | N/R | N/R | 27,318 pages; 136.73 MB of PDFs |
| Judging-pack coverage audit | 2m 11s | N/R | N/R | Updated ear numbers; scratched animals excluded |
| Both judging days, including setup/readiness | 1m 35s | N/R | N/R | 47,308 result saves plus 202 deliberate save replays |
| Judging day 1 workload, included above | 46s | N/R | N/R | Open and Youth together, 270 staff sessions |
| Judging day 2 workload, included above | 41s | N/R | N/R | Open and Youth together, 270 staff sessions |
| Navigation + judging-scope audit | 31s | N/R | N/R | Complete scoped reads and exhibitor roster |
| Finalization + checkout generation + worker recovery | **28m 43s** | N/R | N/R | **11,693 checkout PDFs** generated; two ARBA PDFs deferred until delivery prerequisites |
| Entry/payment/award reconciliation | 2s | N/R | N/R | All checks passed |
| Initial simulated report delivery | 7m 36s | N/R | N/R | 5,054/5,056 exhibitor sends; two required recovery |
| Separate corrected email exercise | 9.83s | N/R | N/R | 100 duplicate-safe replays and recovery of both missing sends |
| Final PDF/content/delivery audits | Combined duration N/R | N/R | N/R | 11,695 PDFs / **6.30 GB** / 14,922 pages; 5,110 messages and 6,193 attachments reconciled after recovery |
| Database and report-file restoration | Duration N/R | N/R | N/R | 40.56 MB compressed database dump; 6.24 GB report ZIP; all 130 tables and 11,695 restored files matched |

Registration through reconciliation took **51m 15s**, including the coverage audits. The first delivery stage added 7m 36s. Later diagnosis, corrections, recovery, and audits were separate, so there is no single recorded elapsed time for a completely clean end-to-end pass at this size.

The closeout supervisor stage took 28m 48s including process overhead. Its deadline measurement was 28m 43s from finalization start, or **29m 19s from completion of judging**, including the intervening scope checks. This left approximately 90m 41s of the two-hour file-generation window. Physical printing and live provider delivery were outside that measurement.

**Resources allocated to the successful core event**

| Component | Recorded allocation / configuration |
| --- | --- |
| Mac | ARM64, 10 logical CPUs, 24 GiB RAM |
| Docker VM | 10 CPUs available, 7.65 GiB RAM shared by local Supabase services |
| Report processes | Ran directly on the Mac, outside Docker; shared the Mac's CPU/RAM |
| Initial report parallelism | Four processes, four render slots each: up to 16 simultaneous renders |
| After injected worker failure | Three surviving processes: up to 12 renders; four interrupted tasks recovered |
| Database | Maximum 100 connections; Auth pool 20, REST pool 20 |
| Local gateway | One worker, 4,096 connections |
| Starting free disk | Docker 28.91 GB; host 48.02 GB |

The Docker allocation is part of the Mac's memory, not an additional 7.65 GiB on top of its 24 GiB. These are available resources, not proven minimum requirements or measured consumption. The 28-minute closeout result does not show that every report worker needs 4 GiB, nor that 7.65 GiB is enough for the complete hosted system.

**File-generation detail**

| Print job | Time including its test harness | Pages | PDF size |
| --- | ---: | ---: | ---: |
| All coop cards | 1m 49s | 12,856 | 44.15 MB |
| Open check-in sheets | 49s | 3,710 | 12.35 MB |
| Youth check-in sheets | 17s | 1,346 | 4.49 MB |
| Open judges' sheets | 3m 07s | 2,406 | 8.61 MB |
| Youth judges' sheets | 38s | 1,257 | 5.42 MB |
| Open comment/runner cards | 2m 17s | 17,371 | 90.75 MB |
| Youth comment/runner cards | 38s | 6,284 | 31.95 MB |

One copy of all seven print packs plus all final reports occupies approximately **6.50 GB**. The final PDFs include 5,056 exhibitor reports, 5,056 check-in sheets, leg files, club reports, and show-wide reports. Much of the size comes from leg PDFs (3.82 GB) and exhibitor reports (2.29 GB). All 1,016 expected earned leg certificates matched; 439 empty-leg placeholders were excluded from email.

The 40.56 MB database dump is compressed backup output; it is not the live database's footprint. The 6.24 GB report archive is a second copy of files, not a substitute for counting their 6.30 GB in object storage. Retaining originals, an archive, and an extracted restore would consume about 18.8 GB for report copies alone.

For planning, **20–30 GB per retained 50k-scale event** is a reasonable initial allowance for these report copies and a regeneration margin. This is an estimate from the observed files, not a measured database requirement or a purchased quota. Multiply by concurrent shows, retained versions, and backup policy. Repeated downloads and emailed attachments also consume transfer bandwidth separately from stored bytes.

**Responsiveness and correctness**

| Operation | 95th-percentile response | Result |
| --- | ---: | --- |
| Account lookup during registration | 4.61s | No failed logical actions |
| Checkout creation | 5.86s | No failed logical actions; bounded transient retries remain in the logs |
| Check-in completion | 0.50s | All completed |
| Change approval | 1.04s | All 22,112 approved |
| Cash change payment | 0.50s | All 5,067 recorded |
| Manual judging save | 0.95s | All 23,199 saved |
| QR judging save | 0.94s | All 24,109 saved |
| Staff reads during closeout | 0.020–0.040s by operation | 165,628 reads, zero failed actions |

The financial reconciliation matched 5,056 simulated online payments totaling $257,110 and 5,067 cash payments totaling $89,990: **$347,100 collected, zero due**. Entries, placements, 108 awards, synthetic points, scratches, changes, and coop numbering matched independently generated expectations. The original ARBA PDFs' missing exhibitor-delivery date remains a recorded finding; the corrected sequencing and date-required audit subsequently passed.

**What the live setup needs**

Production divides this workload among hosted services. Staff devices do not each need the Mac's test-server RAM. Supabase provides the database and API services, Cloud Run renders reports, object storage holds PDFs, and Stripe and Resend handle payment and email boundaries. Hosted Edge workers have their own limits—currently 256 MB memory and two seconds of CPU per request—so the local aggregate Edge-container footprint cannot be used as a per-function RAM requirement. [Supabase Edge limits](https://supabase.com/docs/guides/functions/limits).

A read-only check on September 13 found:

| Live component | Current verified setting | Planning implication |
| --- | --- | --- |
| Supabase organization | Pro plan; Show project healthy in `us-west-2` | The database compute tier and RAM were not exposed by the connector; Pro alone does not identify them |
| Production PostgreSQL | 60 maximum connections; database about 392 MB | The rehearsal used 100 maximum connections; validate the live pool budget and compute before carrying over capacity claims |
| Payment reliability release | New durable enqueue and registration-confirmation functions absent | Deploy the tested payment migrations, webhook, and UI together in the documented order; verify the scheduler and queue health afterward |
| Cloud Run renderer | 4 vCPU and 4 GiB per instance; request concurrency 1; `us-east1` | This is separate memory from Supabase; cross-region latency was absent from the loopback test |
| Live render settings | Three dispatched worker requests, two renders per worker | About six renders per dispatch wave, versus 16 initially and 12 after worker failure locally; the 28m 43s local result is not a live ETA |
| Cloud Run scaling caps | Service cap 20; revision annotation 26 | Neither means 26 workers are always active; effective throughput also depends on dispatcher settings and quota |
| Worker release | Revision `00044-jj4`, source `ce77cf3...` | The September 13 local test source is newer; include the worker in release alignment review |

The live overview is read-only. No production changes, deployments, emails, payments, or new tests were performed for this report.

1. **Release alignment.** Ship and verify the latest tested reliability changes before relying on their behavior in production. The local restart guide lists the payment migration order. Confirm application, functions, database changes, and worker version together.

2. **Database and worker capacity.** Keep a separate budget for PostgreSQL connections/CPU/RAM and report-worker CPU/RAM. Check the actual Supabase compute tier and measure a bounded hosted workload at the intended show size; select the tier from connection waits, query latency, CPU, memory, and I/O. Do not turn 500 purchasers into 500 database connections or simply raise a limit without memory headroom. For the worker, use its current 4 vCPU / 4 GiB allocation as a configuration to validate, not a proven minimum. Increase render parallelism only with measured per-instance memory and downstream database headroom. Review region placement to reduce repeated cross-region reads. [Supabase compute guidance](https://supabase.com/docs/guides/platform/compute-and-disk), [connection budgeting](https://supabase.com/docs/guides/database/connecting-to-postgres/pooling-and-limits), [Cloud Run memory planning](https://docs.cloud.google.com/run/docs/configuring/services/memory-limits).

3. **Authentication, payments, and email throughput.** Validate custom SMTP/Send Email configuration and Auth limits for many people sharing venue Wi-Fi. The built-in Auth mail provider's documented limit is only two emails per hour. Preserve signed, durable, duplicate-safe payment handling and monitor uncompleted registrations; Stripe retries failed live webhook deliveries for up to three days, so delayed delivery must not be mistaken for immediate failure or success. Check the team's actual Resend rate and monthly allowance for at least 5,110 report messages at doubled scale, plus registration messages and receipts. The documented default is currently ten API requests/second; at that rate 5,110 individual send requests alone require at least 8m 31s before upload time and retries. The local emulator's 7m 36s is not an inbox-delivery guarantee. [Auth limits](https://supabase.com/docs/guides/auth/rate-limits), [Stripe webhook delivery](https://docs.stripe.com/webhooks), [Resend limits](https://resend.com/docs/api-reference/rate-limit).

4. **Storage and recoverability.** Budget object storage for approximately 6.50 GB of generated documents per doubled fixture, with retained generations and independent backups. Enable a recovery policy that matches how much recent registration/judging work can be lost; point-in-time recovery is appropriate to evaluate for the event period. Back up report objects separately: Supabase database backups preserve their metadata, not the stored files themselves. Confirm restore procedures and queue recovery before the event. [Supabase backups](https://supabase.com/docs/guides/platform/backups).

5. **Venue and physical printing.** Engineer staff Wi-Fi and internet for the intended simultaneous sessions, with a backup connection and power protection for network and print equipment. At the historical workload that means up to 110 judging tables plus 25 admins/superintendents; the doubled test exercised 220 plus 50. Use the venue's real tablets/laptops and QR cameras in a focused check. Pre-download finished print packs, provide a documented paper fallback, and measure printer throughput on the actual stock. The 27,318-page overnight pack takes 7h 35m at a sustained 60 pages/minute on one printer, or an ideal 1h 54m across four equally fast printers. Those are arithmetic lower bounds; jams, duplex/card handling, warm-up, collating, and distribution add time. The 14,922 final PDF pages include several report types and duplicate-use check-in sheets; the print plan should specify which are actually needed.

6. **Event monitoring and ownership.** Assign someone to watch registration completion, payment queue age, database connection waits, report queue progress, failed deliveries, and storage growth. Alert on failed or blocked jobs, increasing queue age, and sustained memory/CPU pressure. Use the two-hour report deadline as an operational target with time reserved for physical printing and checkout preparation. Confirm that dashboard totals agree with independent entry/payment counts before final delivery.

The most useful remaining verification is a bounded hosted check of the actual live configuration and providers at the intended show workload. Another four-times maximum local run is not needed to document the limit already found. Exact live RAM/CPU requirements and a hosted closeout ETA remain unmeasured.

**Evidence**

R10 source: `9d2ec1641e3cd990a587f30ee86125706ae64654`. The newer 120-entry run used `2b9a1df0d4f94a26161e4bd0ed2327d34c6ff27b`.

- [Original R10 supervisor timings](../output/full_e2e/fresh-51k-r10-20260912/supervisor-state.json), [original delivery failure](../output/full_e2e/fresh-51k-r10-20260912/finish-state.json), and [recorded machine allocation](../output/full_e2e/fresh-51k-r10-20260912/local-host-resources.json).
- [Checkout deadline evidence](../output/full_e2e/fresh-51k-r10-20260912/event/checkout-timing-evidence.json), [PDF audit](../output/full_e2e/fresh-51k-r10-20260912/event/pdf-audit-summary.json), and [reconciliation](../output/full_e2e/fresh-51k-r10-20260912/event/reconciliation.json).
- [Recovered delivery audit](../output/full_e2e/fresh-51k-r10-20260912/delivery-after-recovery-audit/delivery-audit.json), [corrected ARBA-date audit](../output/full_e2e/r10-email-cpu-repair-20260912/date-positive/official-report-content-audit.json), and [restore results](../output/full_e2e/fresh-51k-r10-20260912/event/backup-restore-summary.json).
- [Latest small full-event completion](../output/full_e2e/restart-smoke-r2-20260913/finish-state.json) and [102,844-entry failure report](../output/full_e2e/extreme-102k-r2-20260913/RESULTS.md).
- [Read-only live worker settings](../output/capacity-overview-20260913/live-worker-config.json), [live database settings](../output/capacity-overview-20260913/live-database-config.json), and [derived timing data](../output/capacity-overview-20260913/r10-stage-timings.json).
