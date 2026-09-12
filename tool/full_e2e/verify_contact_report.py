"""Regenerate only the failed synthetic contact report with a supplied worker."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from uuid import UUID
from local import Local, SHOW

lab = Local(sys.argv[1])
out = Path(sys.argv[2]).resolve()
binary = Path(sys.argv[3]).resolve()
artifact_id = str(UUID(sys.argv[4]))
out.mkdir(parents=True, exist_ok=True)
assert not (out / 'contact-before.json').exists(), 'Preserve earlier evidence'

def artifact():
    rows = lab.rows(f"select * from show_report_artifacts where id='{artifact_id}' and show_id='{SHOW}'")
    assert len(rows) == 1 and rows[0]['report_name'] == 'entered_exhibitors_contact_report'
    return rows[0]

def fingerprint():
    return {table: lab.rows(f"select count(*) n,md5(string_agg(to_jsonb(t)::text,'' order by id)) digest from public.{table} t")[0]
            for table in ('entries', 'exhibitors', 'entry_awards', 'show_animal_coop_numbers')}

before = artifact()
assert before['artifact_status'] == 'failed' or ('--allow-generated' in sys.argv and before['artifact_status'] == 'generated')
assert not lab.rows("select id from show_task_queue where task_status::text in ('queued','running')"), 'Other work is pending'
(out / 'contact-before.json').write_text(json.dumps(before, indent=2))
inputs = fingerprint()
(out / 'inputs-before.json').write_text(json.dumps(inputs, indent=2))
admin = lab.person('contact-fix-admin')
lab.sql(f"insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{admin['user_id']}','admin'); insert into show_managers(show_id,user_id,can_manage_entries,can_manage_settings,can_finalize) values ('{SHOW}','{admin['user_id']}',true,true,true)")
queued = lab.rpc('requeue_single_closeout_artifact', dict(p_show_id=SHOW,
    p_finalize_run_id=before['finalize_run_id'], p_scope_key=before['scope_key'], p_artifact_id=artifact_id), admin['token'])
(out / 'contact-requeue.json').write_text(json.dumps(queued, indent=2))
start = time.monotonic()
with (out / 'contact-worker.log').open('w') as log:
    subprocess.run([str(binary)], env=lab.worker_env('local-contact-fix'), stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
elapsed = time.monotonic() - start
after = artifact()
(out / 'contact-after.json').write_text(json.dumps(after, indent=2))
assert after['artifact_status'] == 'generated', after.get('metadata')
assert after['generation'] == before['generation'] + 1
url = lab.url + '/storage/v1/object/authenticated/' + after['storage_bucket'] + '/' + urllib.parse.quote(after['storage_path'], safe='/')
request = urllib.request.Request(url, headers={'apikey': lab.key, 'Authorization': 'Bearer ' + lab.key})
with urllib.request.urlopen(request, timeout=60) as response:
    data = response.read()
assert hashlib.sha256(data).hexdigest() == after['file_hash_sha256']
assert len(data) == after['file_size_bytes']
(out / 'contact-actual-5056.pdf').write_bytes(data)
sections = ','.join("'" + s + "'" for s in before['section_ids'])
contacts = lab.rows(f"select ex.* from exhibitors ex where exists(select 1 from entries e where e.exhibitor_id=ex.id and e.show_id='{SHOW}' and e.section_id in ({sections})) order by lower(ex.display_name),ex.id")
(out / 'expected-contacts.json').write_text(json.dumps(contacts, indent=2))
assert inputs == fingerprint(), 'Judging/check-in inputs changed during targeted regeneration'
counts = lab.rows(f"select artifact_status::text status,count(*) n from show_report_artifacts where show_id='{SHOW}' and finalize_run_id='{before['finalize_run_id']}' and is_current group by artifact_status")
dashboard = lab.rpc('get_closeout_dashboard_scoped_for_species', dict(p_show_id=SHOW,
    p_scope_key=before['scope_key'], p_section_ids=before['section_ids'], p_species_filter='rabbit', p_artifact_limit=1, p_artifact_offset=0), admin['token'])
(out / 'dashboard-after.json').write_text(json.dumps(dashboard, indent=2))
summary = dict(status='passed', elapsed_s=elapsed, contacts=len(contacts), bytes=len(data),
    worker_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), generation=after['generation'],
    artifact_counts=counts, unchanged_input_fingerprints=inputs, content_audit='pending', storage_audit_role='service_role; local fixture lacks permissive Storage read policies')
(out / 'contact-regeneration-summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps({k:v for k,v in summary.items() if k!='unchanged_input_fingerprints'}))
