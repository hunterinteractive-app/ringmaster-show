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
cp "$repo_root/supabase/local/legacy_foundation.sql" \
  "$workdir/supabase/migrations/00000000000001_ringmaster_legacy_foundation.sql"
cp "$repo_root"/supabase/migrations/*.sql "$workdir/supabase/migrations/"
cp "$repo_root/supabase/local/readiness_format_compat.sql" \
  "$workdir/supabase/migrations/20260903002624_local_readiness_format_compat.sql"
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
cp "$repo_root/supabase/tests/closeout_artifact_scope_identity_repair.sql" \
  "$workdir/supabase/tests/closeout_artifact_scope_identity_repair.sql"
cp "$repo_root/supabase/tests/closeout_scope_species_inference.sql" \
  "$workdir/supabase/tests/closeout_scope_species_inference.sql"
cp "$repo_root/supabase/tests/closeout_regeneration_rebuilds_club_manifest.sql" \
  "$workdir/supabase/tests/closeout_regeneration_rebuilds_club_manifest.sql"
cp "$repo_root/supabase/tests/closeout_readiness_ignores_zero_duplicate_placements.sql" \
  "$workdir/supabase/tests/closeout_readiness_ignores_zero_duplicate_placements.sql"

cp "$repo_root/supabase/tests/closeout_result_pages_and_revisions.sql" \
  "$workdir/supabase/tests/closeout_result_pages_and_revisions.sql"

cp "$repo_root/supabase/tests/national_section_revisions_and_judging.sql" \
  "$workdir/supabase/tests/national_section_revisions_and_judging.sql"

cp "$repo_root/supabase/tests/event_rehearsal_shown_counts.sql" \
  "$workdir/supabase/tests/event_rehearsal_shown_counts.sql"

# This project ID guarantees different Docker resources from the linked
# production checkout while retaining the CLI-generated local ports/keys.
sed -i.bak 's/^project_id = .*/project_id = "ringmaster-show-local-e2e"/' \
  "$workdir/supabase/config.toml"
rm "$workdir/supabase/config.toml.bak"

echo "Prepared isolated Supabase project at $workdir"
echo "Start with: supabase start --workdir $workdir"
echo "Reset with: supabase db reset --workdir $workdir"
