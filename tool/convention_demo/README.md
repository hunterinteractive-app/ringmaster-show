# RingMaster convention demo

Open **Launch.command** to start, then use http://127.0.0.1:8787/booth.
Open **Stop.command** when finished. Docker Desktop must be installed and running;
the launcher will start it if needed. Keep this checkout in its current location.

## At the booth

- **Secretary & superintendent:** normal show-management and superintendent screens.
- **Exhibitor:** Avery Meadow's fictional account, with five paid sample entries.
- **Captured emails:** messages the app considers sent. Nothing is delivered externally.
- **Reset sample show:** confirm on the next page to restore the saved fictional data.
  Close other demo tabs first. Reset clears changes and captured emails; it does not
  delete or rebuild the database schema. Generated local files may remain on disk.

The sample show has 24 exhibitors, 120 entries, Open and Youth sections, two breeds,
and two judges. Its date and entry deadline roll forward whenever the demo starts
or resets, so entries remain open at convention. Switch personas one at a time;
they share the browser's local session. Use only fictional data.

Checkout uses a clearly labeled local payment page. **Complete demo payment** runs
the application's actual signed webhook and registration logic without a card or
charge. The simulated checkout service intentionally does not reproduce Stripe's
hosted page appearance. Square and other external payment connections are not
configured. External AI services are unavailable offline.

## Isolation and offline preparation

This is the same Flutter application source as the web version, compiled with
`CONVENTION_DEMO=true`, a separate local database, and a small demo banner.
Production builds do not automatically log in or show the banner.

The demo validates loopback frontend/API URLs, restricts browser connections, and
rejects non-local Edge Function requests. Local Stripe and Resend credentials are
fictional; outgoing email requests are captured and return simulated success.
Report PDFs use the real builders and local Storage. No production data was copied.

The initial setup/build needs internet to obtain dependencies and Docker images.
After preparation, application assets, fonts, rendering engine, report worker, and
database live on this Mac. Launch and try your planned walkthrough before traveling;
keep Docker's convention volumes and this checkout. Docker's local Supabase services
use default development credentials and should contain fictional data only.

## Developer details

- Branch: `convention/local-demo`; this work has not been deployed to the live site.
- Application: port 8787; simulated providers: 8769; Supabase API: 55321.
- Runtime config: `/tmp/ringmaster-convention-demo`, recreated from the saved copy
  if macOS clears temporary files. Database data persists in Docker volumes.
- Persistent fixture, snapshot, logs, dependencies: `output/convention-demo/`.
- Rebuild after changing app code: `python3 tool/convention_demo/build.py` with
  Flutter, Dart, Supabase, Docker, and Python 3.11+ on PATH.
- Local historical SQL prerequisites are isolated from production migrations.
- `flutter test test/convention_demo_test.dart --dart-define=CONVENTION_DEMO=true`
  checks rejection of hosted endpoints. Those checks skip in ordinary app tests.

Verified: 120 registrations through simulated Stripe checkout, secretary and
exhibitor login, actual check-in PDF generation/upload, simulated report email with
attachment and delivery record, an additional interactive paid entry, and snapshot
reset restoring 120 entries. A full audit of every administration feature and a
physical disconnected-network rehearsal remain outside these checks.
