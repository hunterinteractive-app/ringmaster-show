"""Configure the refund status job without printing or persisting its token.

Requires authenticated Supabase and gcloud CLIs. This only installs a job that
reconciles previously authorized requests; it never creates a refund request.
"""
import argparse
import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase-project", required=True)
    parser.add_argument("--google-project", required=True)
    parser.add_argument("--location", default="us-east1")
    parser.add_argument("--supabase-bin", default="supabase")
    parser.add_argument("--gcloud-bin", default="gcloud")
    args = parser.parse_args()
    job = "ringmaster-entry-refunds"
    common = [f"--project={args.google_project}", f"--location={args.location}"]
    current = run([args.gcloud_bin, "scheduler", "jobs", "describe", job, *common, "--format=json"])
    if current.returncode and "NOT_FOUND" not in current.stderr:
        raise SystemExit("Unable to inspect the refund scheduler job; no changes made.")
    existing = json.loads(current.stdout) if current.returncode == 0 else None
    headers = existing.get("httpTarget", {}).get("headers", {}) if existing else {}
    authorization = next((v for k, v in headers.items() if k.lower() == "authorization"), "")
    token = authorization.removeprefix("Bearer ") if authorization.startswith("Bearer ") else secrets.token_urlsafe(48)
    with tempfile.TemporaryDirectory(prefix="ringmaster-refund-job-") as folder:
        env = Path(folder) / "secret.env"
        env.write_text(f"ENTRY_REFUND_RECONCILE_SECRET={token}\n")
        os.chmod(env, 0o600)
        saved = run([args.supabase_bin, "secrets", "set", "--env-file", str(env), "--project-ref", args.supabase_project])
        if saved.returncode:
            raise SystemExit("Could not configure the refund-only backend secret.")
        flags = {
            "schedule": "*/5 * * * *",
            "uri": f"https://{args.supabase_project}.supabase.co/functions/v1/refund-show-entries",
            "http-method": "POST",
            "message-body": '{"action":"reconcile"}',
            "attempt-deadline": "180s",
            "description": "Reconcile already-authorized entry refunds and remove entries after confirmed success.",
            "update-headers" if existing else "headers": {
                "Authorization": f"Bearer {token}", "Content-Type": "application/json"
            },
        }
        config = Path(folder) / "job.json"
        config.write_text(json.dumps({f"--{key}": value for key, value in flags.items()}))
        os.chmod(config, 0o600)
        configured = run([args.gcloud_bin, "scheduler", "jobs", "update" if existing else "create", "http", job,
                          *common, "--flags-file", str(config), "--quiet", "--format=value(name)"])
        if configured.returncode:
            print(configured.stderr.replace(token, "[redacted]")[-2000:])
            raise SystemExit("Refund backend secret is configured, but scheduler creation failed. Rerun this script to finish.")
        print(f"Configured {job}: every 5 minutes in {args.location}.")


if __name__ == "__main__":
    main()
