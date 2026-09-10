"""Restore synthetic public/Auth/Storage data into a separate, unexposed database.

Also restores every archived report into a temporary directory and verifies its
hash. This is a data recovery rehearsal, not a complete hosted-platform restore.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
import secrets
from local import Local, PROJECT, SHOW


def main():
    lab=Local(sys.argv[1]);out=Path(sys.argv[2]);container=lab.container
    reuse='--existing-backup' in sys.argv[3:]
    database='full_e2e_restore_'+secrets.token_hex(6)
    if (out/'backup-restore-summary.json').exists():raise RuntimeError('Completed recovery evidence already exists')
    if int(lab.sql(f"select count(*) from pg_database where datname='{database}'")):
        raise RuntimeError('Restore database already exists; preserve prior evidence')
    if int(lab.sql(f"select count(*) from show_task_queue where show_id='{SHOW}' and task_status in ('queued','running')")):
        raise RuntimeError('Stop rendering before the recovery snapshot')
    dump=out/'database-with-private-schema.dump'
    if dump.exists() and not reuse:raise RuntimeError('Database backup already exists')
    if reuse:
        assert dump.exists() and dump.stat().st_size>0
    else:
        with dump.open('xb') as target:
            subprocess.run(['docker','exec',container,'pg_dump','-U','postgres','-d','postgres','-Fc',
                '--schema=public','--schema=auth','--schema=storage','--schema=report_generation_private','--no-owner'],stdout=target,check=True)
    dump.chmod(0o600)
    lab.sql(f'create database {database};')
    def sql(statement):
        r=subprocess.run(['docker','exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d',database,'-At'],input=statement,text=True,capture_output=True)
        if r.returncode:raise RuntimeError(r.stderr[-4000:])
        return r.stdout
    sql('drop schema public; create schema extensions; create extension pgcrypto with schema extensions; create extension "uuid-ossp" with schema extensions; create extension pg_trgm with schema extensions;')
    with dump.open('rb') as source,(out/'database-restore.log').open('w') as log:
        restored=subprocess.run(['docker','exec','-i',container,'pg_restore','-U','postgres','-d',database,'--no-owner','--no-acl','--exit-on-error'],stdin=source,stdout=log,stderr=subprocess.STDOUT)
    if restored.returncode:raise RuntimeError('Database restore failed; inspect database-restore.log')
    tables=lab.rows("select schemaname,tablename from pg_tables where schemaname in ('public','auth','storage','report_generation_private') order by 1,2")
    results=[]
    for row in tables:
        table='"'+row['schemaname']+'"."'+row['tablename']+'"'
        query=f"select count(*)::text||':'||coalesce(md5(string_agg(row_to_json(t)::text,'|' order by row_to_json(t)::text)),md5('')) from {table} t;"
        original=lab.sql(query).strip();recovered=sql(query).strip()
        results.append(dict(table=table,original=original,restored=recovered,passed=original==recovered))
    hashes={a['id']+'.pdf':a['file_hash_sha256'] for a in json.loads((out/'generated-artifacts.json').read_text())}
    destination=out/'temporary-restored-report-files'
    destination.mkdir(exist_ok=False);files=[]
    try:
        with zipfile.ZipFile(out/'report-files.zip') as archive:
            for item in archive.infolist():
                if item.filename not in hashes or Path(item.filename).name!=item.filename:raise RuntimeError('Unexpected archive member')
                target=destination/item.filename
                with archive.open(item) as source,target.open('xb') as recovered:shutil.copyfileobj(source,recovered)
                digest=hashlib.sha256(target.read_bytes()).hexdigest()
                files.append(dict(file=item.filename,passed=digest==hashes[item.filename]))
                # Each file is independently restored, read back, and then removed.
                # Bound disk usage without leaving another multi-GB duplicate.
                if digest!=hashes[item.filename]:raise RuntimeError('Restored report checksum mismatch')
                target.unlink()
    finally:
        if not any(destination.iterdir()):destination.rmdir()
    result=dict(status='passed' if all(r['passed'] for r in results) and len(files)==len(hashes) else 'failed',
        restored_database=database,database_bytes=dump.stat().st_size,tables=results,acl_restore_excluded=True,
        restored_files=len(files),expected_files=len(hashes),file_failures=[r for r in files if not r['passed']],
        limitations=['Separate database is not connected to Auth, REST, or Storage services.',
            'Roles, ownership, extensions, provider secrets and a hosted disaster-recovery switchover are not certified.',
            'Storage bytes restored individually to disk and verified; not republished through a new Storage API.'])
    (out/'backup-restore-summary.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k!='tables'}))
    if result['status']=='failed':raise SystemExit(1)

if __name__=='__main__':main()
