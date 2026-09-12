# Focused national-show checks — September 12, 2026

Steps 1–5 were checked with an isolated local fixture. The 102,844-entry full
event remains paused: no extreme fixture or workload was started. This work
used 120 rabbit entries, 24 exhibitors, two sections and two judges, plus a
separate three-entry cavy show for browser checks. Payments and email used
local synthetic receivers. Production inspection was read-only.

The starting source was `a07b9aa04771d9e4ef40a4f96dae1a9130909f70`.
Its app CI/deployment succeeded in run 34721415163. The deployed email function
was version 55, active with JWT verification. Cloud Run revision
`ringmaster-closeout-renderer-00044-jj4` served all traffic; all 82 reachable
worker source files still matched the preserved worker binary. The changes
from these checks affect the web UI, tests and local rehearsal tooling;
they require no production database, Edge function or worker deployment.

Actual signed-in browser saves passed through both QR and manual results
entry. Persisted placements, judges and writer information were inspected.
A legacy cavy stored as Buck appeared in the Senior Boar class but still
showed Buck in the QR result dialog. The QR loader now normalizes presentation
after loading authoritative species, without changing stored labels. A Chrome
regression reproduced that defect before the fix and passed afterward. The
compiled corrected build visibly showed Boar for that same entry.

Browser testing also exposed missing historical contracts in the local loader
baseline: judge/catalog read policies, assignment metadata, result locks and
the judging-session callback. The local bootstrap now restores selected
inspected production definitions. It passed both an idempotent repeat and a
missing-contract creation check inside a rolled-back local transaction.
This is signed-in coverage, not anonymous QR or complete production ACL parity.

All 120 results were entered through the API. Both sections passed readiness
before combined finalization. Four worker processes with four slots each
completed all 77 checkout tasks, with zero failed tasks, in about 13 seconds.
The two ARBA reports remained deferred until delivery prerequisites completed.

An injected provider failure left one exhibitor delivery incomplete. The
delivery harness stopped before ARBA generation and left the exhibitor-delivery
date unset. The successful club batch correctly recorded its own date. The
first test wrapper incorrectly expected both dates to remain unset; its failure
is preserved separately from the corrected assertion review. Recovery then
passed, including a provider acceptance followed by a response timeout and
retry. Both final ARBA PDFs contain both delivery dates.

The final file audit passed all 79 artifacts, including all 24 exhibitor
reports, 24 check-in sheets and eight earned leg certificates. The merged
delivery audit matched 28 messages and 48 attachments against recipients and
file hashes, with no missing or duplicate deliveries. A separate transport
test sent 20 new 4,593,340-byte bundles through the actual email function;
all 20 completed, their 40 attachments matched the original bytes, and all
20 completed-send replays produced no additional messages. One send also
recovered an accepted request whose response timed out. These large PDFs
were preserved synthetic transport fixtures, not reports derived from the
three-entry cavy show.

All nine focused official reports passed population, payment, judge and date
checks. The audit previously assumed 110 judges and 104 breed reports even
for the small fixture. It now derives expectations from the independently
planned section judges and manifest breed population. A negative check adding
an expected but absent judge failed both the judges and ARBA reports.

ARBA pagination passed at 0, 12, 13, 110 and 440 judges. All 440 names and
license numbers appear exactly once across eight pages. Pages 1, 2, 4, 7 and 8
were visually reviewed, along with focused ARBA, judges and contact samples.
The remaining R10 ARBA and judges-report samples were also reviewed for
layout. R10's original missing exhibitor-delivery date remains documented;
its two failed sends and separate recovery are not an uninterrupted full pass.

Other validation included 26 passing focused Flutter tests, the Chrome-only
manual navigation test, the new Chrome QR regression, six email encoding and
attachment tests, five permanent worker pagination cases, Python compilation,
and Flutter analysis with no issues. The original VM invocation could not
load the browser-only manual test; that file passed under Chrome.

Capacity inspection confirmed database maximum 100 connections, Auth and REST
pools of 20, gateway connection limit 4,096 and open-file limit 8,192. Docker
has 10 logical CPUs and 8,214,851,584 bytes of memory; the host has 24 GiB RAM.
The small closeout exercised the configured four processes and four slots.
The final disk snapshot passed the current 20 GiB host / 18 GiB Docker minimums.
Those are point-in-time minimums, not a disk-growth guarantee for the extreme
event. Recheck the combined host and Docker storage budget before step 6.
A preserved 6.38 GB cold TAR was compressed to 144 MB and its entire
decompressed stream matched the original checksum before replacing the TAR.
Filesystem free space did not immediately increase by that logical reduction.

Raw evidence is under `output/full_e2e/focused-preflight-20260912/`, including
the frozen source manifests, browser results, failure/recovery captures, PDF
audits, capacity snapshot and release follow-up. Older failure evidence and
database volumes remain preserved. These focused checks do not measure
102,844-entry throughput, hosted failover, real provider delivery or physical
printer time.
