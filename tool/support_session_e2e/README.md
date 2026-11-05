# Local support-session rehearsal

Use only the disposable Supabase project `rm-delegation-e2e` on loopback port 58721. Never point the script at a linked or hosted project. The small schema uses the Show application's actual licensed-create routine with synthetic users and tables. The downstream payment function is an identity echo; no money moves and no messages are sent.

From the repository root on a machine with Docker, Python 3, and the Supabase CLI:

```sh
lab=/private/tmp/rm-delegation-e2e
mkdir -p "$lab/supabase/migrations" "$lab/supabase/functions/payment-quote-preview"
cp tool/support_session_e2e/config.toml "$lab/supabase/config.toml"
cp tool/support_session_e2e/fixture.sql "$lab/supabase/migrations/20260101000000_fixture.sql"
cp tool/support_session_e2e/show_creation_fixture.sql "$lab/supabase/migrations/20260101000001_show.sql"
cp supabase/migrations/*_audited_support_sessions.sql "$lab/supabase/migrations/"
cp -R supabase/functions/_shared supabase/functions/support-session "$lab/supabase/functions/"
cp tool/support_session_e2e/edge_identity.ts "$lab/supabase/functions/payment-quote-preview/index.ts"
supabase start --workdir "$lab" --exclude studio,postgres-meta,logflare,vector,realtime,imgproxy,mailpit,supavisor
supabase functions serve --workdir "$lab"
```

In a second terminal, run `python3 tool/support_session_e2e/smoke.py`. It tests ordinary-user denial, operator grants, target identification, cross-account denial, licensed show creation, ownership, staff membership, an edit under RLS, private binary report upload/download, a downstream authenticated function, audit records, expiration, revocation and preservation of the two original logins. The script creates fresh random test accounts each time. Stop this **test** project after use.
