"""Loopback-only helpers for the synthetic full-schema rehearsal."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
SHOW = '95000000-0000-0000-0000-000000000001'
PROJECT = 'ringmaster-show-local-e2e'
CONTAINER = 'supabase_db_' + PROJECT


def uid(prefix, n):
    return f'{prefix}00000-0000-0000-0000-{n:012d}'


def sql_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


class ApiError(RuntimeError):
    def __init__(self, code, body):
        self.code, self.body = code, body
        super().__init__(f'HTTP {code}: {str(body)[:1500]}')


class Lab:
    def __init__(self, workspace):
        self.workspace = Path(workspace).resolve()
        config = (self.workspace / 'supabase/config.toml').read_text()
        if f'project_id = "{PROJECT}"' not in config:
            raise ValueError('Unexpected local project ID')
        if (self.workspace / 'supabase/.temp/project-ref').exists():
            raise ValueError('Refusing a linked project')
        # A full migration workspace is required, not the baseline loader lab.
        if len(list((self.workspace / 'supabase/migrations').glob('*.sql'))) < 218:
            raise ValueError('The full local migration bootstrap is required')
        for source in (ROOT / 'supabase/migrations').glob('*.sql'):
            copied = self.workspace / 'supabase/migrations' / source.name
            if not copied.is_file() or copied.read_bytes() != source.read_bytes():
                raise ValueError(f'Stale or missing local migration: {source.name}')
        result = subprocess.run(['supabase', 'status', '--workdir', str(self.workspace), '-o', 'json'],
                                capture_output=True, text=True, check=True)
        self.local = json.loads(result.stdout)
        self.url = self.local['API_URL']
        parsed = urlparse(self.url)
        if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost'):
            raise ValueError('Refusing a non-loopback API')
        self.key, self.anon = self.local['SERVICE_ROLE_KEY'], self.local['ANON_KEY']
        count = self.sql(f"select count(*) from public.entries where show_id='{SHOW}'")
        if count.strip() != '25711':
            raise ValueError('The exact synthetic convention fixture is required')

    def sql(self, sql):
        result = subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql',
                                 '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-At'],
                                input=sql, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr[-3500:])
        return result.stdout

    def request(self, path, data=None, token=None, method=None, timeout=65):
        key = self.anon if token else self.key
        headers = {'apikey': key, 'Authorization': 'Bearer ' + (token or self.key),
                   'Content-Type': 'application/json'}
        body = None if data is None else json.dumps(data).encode()
        request = urllib.request.Request(self.url + path, body, headers,
                                         method=method or ('GET' if body is None else 'POST'))
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read().decode(errors='replace')
            try:
                raw = json.loads(raw)
            except ValueError:
                pass
            raise ApiError(error.code, raw) from None

    def rpc(self, name, params, token=None):
        return self.request('/rest/v1/rpc/' + name, params, token)

    def staff(self, count=40):
        # Fresh local Auth users, no real names, addresses, or shared passwords.
        nonce = secrets.token_hex(5)
        staff = []
        for index in range(count):
            email = f'rehearsal-{nonce}-{index + 1}@example.invalid'
            password = secrets.token_urlsafe(32)
            user = self.request('/auth/v1/admin/users',
                                {'email': email, 'password': password, 'email_confirm': True})
            auth = self.request('/auth/v1/token?grant_type=password', {'email': email, 'password': password})
            role = 'admin' if index >= 36 or count == 1 else 'reporting_clerk'
            self.sql(f"insert into public.role_assignments(show_id,user_id,role) values ('{SHOW}',{sql_quote(user['id'])},{sql_quote(role)});"
                     f"insert into public.show_managers(show_id,user_id,can_manage_entries,can_manage_settings,can_finalize) values ('{SHOW}',{sql_quote(user['id'])},true,{str(role == 'admin').lower()},{str(role == 'admin').lower()});")
            staff.append({'user_id': user['id'], 'token': auth['access_token'], 'role': role, 'index': index})
        return staff

    def readiness(self, section, token=None):
        return self.rpc('show_results_readiness_scoped',
                        {'p_show_id': SHOW, 'p_section_ids': [uid('951', section)]}, token)

    def finalize(self, section):
        # Same trusted RPC as run-closeout. Initiator permission is checked by
        # callers; this local harness does not claim Edge Function coverage.
        sections = [uid('951', section)]
        return self.rpc('finalize_show_scoped', {'p_show_id': SHOW,
            'p_section_ids': sections, 'p_scope_label': 'Open A' if section == 1 else 'Youth A',
            'p_scope_key': SHOW + ':' + ','.join(sections)})

    def worker_env(self, worker_id):
        env = {k: v for k, v in os.environ.items()
               if not any(word in k for word in ('SUPABASE', 'RESEND', 'WORKER_', 'STORAGE_', 'WORK_TRIGGER'))}
        env.update(SUPABASE_URL=self.url, SUPABASE_SERVICE_ROLE_KEY=self.key,
                   ASSET_ROOT=str(ROOT / 'assets'), WORKER_ID=worker_id,
                   TASK_BATCH_SIZE='8', MAX_CONCURRENT_RENDERS='4', POLL_INTERVAL_SECONDS='1')
        return env


def elapsed(call):
    start = time.monotonic()
    value = call()
    return value, round((time.monotonic() - start) * 1000, 2)
