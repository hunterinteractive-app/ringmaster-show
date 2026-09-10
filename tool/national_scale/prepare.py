"""Prepare a fresh local loader lab; never links to a hosted project."""
import argparse
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("workspace", help="New disposable local workspace directory")
parser.add_argument("--scenario", choices=["national", "convention-2024"], default="national")
args = parser.parse_args()
target = pathlib.Path(args.workspace).resolve()
project_id = "ringmaster-national-loader-lab"
seed = (ROOT / "tool/national_scale/seed.sql").read_text()
manifest = None
if args.scenario == "convention-2024":
    import json
    from convention_2024 import build
    seed, manifest = build()
    project_id = "ringmaster-convention-loader-lab"
try:
    target.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    parser.error(f"Refusing to overwrite existing workspace: {target}")
subprocess.run(["supabase", "init", "--workdir", str(target)], check=True)
config = target / "supabase/config.toml"
config.write_text(config.read_text().replace(
    next(line for line in config.read_text().splitlines()
         if line.startswith("project_id =")),
    f'project_id = "{project_id}"'))
migrations = target / "supabase/migrations"
migrations.mkdir(exist_ok=True)
shutil.copyfile(ROOT / "supabase/local/baseline.sql",
                migrations / "00000000000000_ringmaster_baseline.sql")
(target / "supabase/seed.sql").write_text(
    (ROOT / "supabase/local/seed.sql").read_text() + "\n" +
    seed)
if manifest is not None:
    (target / "convention_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
(target / "LOADER_LAB_ONLY").write_text(
    "Repository baseline only. Not a full migration, auth, or capacity rehearsal.\n")
print(f"Prepared local loader lab: {target}")
