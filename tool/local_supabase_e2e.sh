#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="${1:-/tmp/ringmaster-show-local-e2e}"

if [[ -e "$workdir" ]]; then
  echo "Refusing to overwrite existing local workspace: $workdir" >&2
  echo "Choose a new path or remove the disposable workspace explicitly." >&2
  exit 2
fi

mkdir -p "$workdir"
supabase init --workdir "$workdir"
mkdir -p "$workdir/supabase/migrations"

cp "$repo_root/supabase/local/baseline.sql" \
  "$workdir/supabase/migrations/00000000000000_ringmaster_baseline.sql"
cp "$repo_root"/supabase/migrations/*.sql "$workdir/supabase/migrations/"
cp "$repo_root/supabase/local/seed.sql" "$workdir/supabase/seed.sql"
cp -R "$repo_root/supabase/functions" "$workdir/supabase/functions"
mkdir -p "$workdir/supabase/tests"
cp "$repo_root/supabase/tests/payment_hardening.sql" \
  "$workdir/supabase/tests/payment_hardening.sql"
cp "$repo_root/supabase/tests/closeout_scoped_financial_auth.sql" \
  "$workdir/supabase/tests/closeout_scoped_financial_auth.sql"
cp "$repo_root/supabase/tests/closeout_repair_diagnostic_classification.sql" \
  "$workdir/supabase/tests/closeout_repair_diagnostic_classification.sql"
cp "$repo_root/supabase/tests/closeout_dashboard_artifact_scope.sql" \
  "$workdir/supabase/tests/closeout_dashboard_artifact_scope.sql"

# This project ID guarantees different Docker resources from the linked
# production checkout while retaining the CLI-generated local ports/keys.
sed -i.bak 's/^project_id = .*/project_id = "ringmaster-show-local-e2e"/' \
  "$workdir/supabase/config.toml"
rm "$workdir/supabase/config.toml.bak"

echo "Prepared isolated Supabase project at $workdir"
echo "Start with: supabase start --workdir $workdir"
echo "Reset with: supabase db reset --workdir $workdir"
