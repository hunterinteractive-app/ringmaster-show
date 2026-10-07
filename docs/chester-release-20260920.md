# Chester production release — 2026-09-20

Version 1.00.02 deployed to https://show.ringmasterone.com via Cloudflare Pages.
Deployment: https://a1c4a4af.ringmaster-show.pages.dev
Previous production deployment: e33ee3b7-23e3-42cd-9e5e-a22bd259d135.

Built from production baseline aef18ea with only Chester UI, navigation, rabbit assets, admin review screens, services, and version update. Unfinished contest, add-on and checkout changes were excluded. Working-tree changes remain uncommitted. Exact release source is retained at output/releases/chester-1.00.02/source.tar.gz.

Validation: 38 distinct assistant and accessibility tests passed (guide catalog check rerun after adding its reference fixture to the isolated source). Release web build passed. Static analysis reports 28 informational lint notices, no errors or warnings. Production browser confirmed version 1.00.02 and Chester chat. Backend migrations and Edge Function were deployed previously; AI enabled and live provider response verified before this release.
