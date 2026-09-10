"""Run opt-in Flutter checks against the marked local loader lab only."""
import argparse
import json
import os
import pathlib
import subprocess
import sys
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("workspace", help="Workspace created by prepare.py")
parser.add_argument("test_name", nargs="?", help="Optional test name substring")
args = parser.parse_args()
target = pathlib.Path(args.workspace).resolve()
if not (target / "LOADER_LAB_ONLY").is_file():
    sys.exit("Refusing an unmarked workspace; use prepare.py first.")
config = (target / "supabase/config.toml").read_text()
is_convention = 'project_id = "ringmaster-convention-loader-lab"' in config
if not is_convention and 'project_id = "ringmaster-national-loader-lab"' not in config:
    sys.exit("Refusing an unexpected project ID.")
status = subprocess.run(
    ["supabase", "status", "--workdir", str(target), "-o", "json"],
    check=True, capture_output=True, text=True)
local = json.loads(status.stdout)
url = local["API_URL"]
parsed = urlparse(url)
if parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost"):
    sys.exit("Refusing a non-loopback API URL.")
env = dict(os.environ,
           NATIONAL_TEST_URL=url,
           NATIONAL_TEST_KEY=local["SERVICE_ROLE_KEY"])
test_file = "test/national_scale_local_integration_test.dart"
env.pop("CONVENTION_MANIFEST", None)
if is_convention:
    manifest = target / "convention_manifest.json"
    if not manifest.is_file():
        sys.exit("Convention manifest is missing; prepare a fresh fixture.")
    env["CONVENTION_MANIFEST"] = str(manifest)
    test_file = "test/convention_scale_local_integration_test.dart"
# Do not inherit unrelated database credentials or enable the old parity test.
for name in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "PDF_PARITY_OUTPUT"):
    env.pop(name, None)
command = [
    "flutter", "test", test_file, "--no-pub",
    "--reporter", "expanded", "--concurrency", "1", "--timeout", "5m"]
if args.test_name:
    command += ["--plain-name", args.test_name]
result = subprocess.run(command, cwd=ROOT, env=env)
sys.exit(result.returncode)
