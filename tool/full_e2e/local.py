"""Full workflow rehearsal: synthetic identities and loopback services only."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import re
import hashlib
import base64
import threading
import time
import tomllib
from uuid import UUID
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(ROOT / 'tool/closeout_rehearsal'))
from lab import Lab, ApiError, SHOW, uid, sql_quote

PROJECT = 'ringmaster-show-full-e2e'


def selected_finalize_run(arguments):
    """Optional exact run scope for probes on a fixture with older reports."""
    values=[a.split('=',1)[1] for a in arguments if a.startswith('--finalize-run-id=')]
    if len(values)>1:raise ValueError('Specify only one finalize run')
    return str(UUID(values[0])) if values else None


class Local(Lab):
    def __init__(self, workspace):
        self.workspace = Path(workspace).resolve()
        if not str(self.workspace).startswith(('/tmp/', '/private/tmp/')):
            raise ValueError('A disposable /tmp workspace is required')
        config = tomllib.loads((self.workspace / 'supabase/config.toml').read_text())
        self.project = config.get('project_id','')
        if not re.fullmatch(PROJECT+r'(?:-[a-z0-9_-]+)?',self.project):
            raise ValueError('Unexpected project: refusing to operate')
        self.container = 'supabase_db_' + self.project
        if (self.workspace / 'supabase/.temp/project-ref').exists():
            raise ValueError('Linked projects are forbidden')
        frozen = self.workspace / 'rehearsal-migration-manifest.json'
        if frozen.exists():
            # Explicitly pin a running rehearsal when another task edits the
            # shared checkout. Never silently apply new migrations mid-event.
            manifest = json.loads(frozen.read_text())
            if manifest['project_id'] != self.project:
                raise ValueError('Frozen manifest has a different project')
            actual = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (self.workspace / 'supabase/migrations').glob('*.sql')}
            if actual != manifest['files']:
                raise ValueError('Frozen rehearsal migration set changed')
        else:
            for source in (ROOT / 'supabase/migrations').glob('*.sql'):
                if (self.workspace / 'supabase/migrations' / source.name).read_bytes() != source.read_bytes():
                    raise ValueError('Local migration differs: ' + source.name)
        result = subprocess.run(['supabase', 'status', '--workdir', str(self.workspace), '-o', 'json'],
                                capture_output=True, text=True, check=True)
        self.local = json.loads(result.stdout)
        self.url = self.local['API_URL']
        parsed = urlparse(self.url)
        if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost'):
            raise ValueError('Non-loopback API is forbidden')
        self.key, self.anon = self.local['SERVICE_ROLE_KEY'], self.local['ANON_KEY']
        self._session_refresh_lock = threading.Lock()

    def session_token(self, person):
        """Refresh long-lived synthetic sessions using the real Auth endpoint."""
        def expiring():
            payload = person['token'].split('.')[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
            return claims['exp'] <= time.time() + 60
        if expiring():
            with self._session_refresh_lock:
                if expiring():
                    auth = self.request('/auth/v1/token?grant_type=refresh_token',
                                        {'refresh_token': person['refresh_token']})
                    person.update(token=auth['access_token'], refresh_token=auth['refresh_token'])
        return person['token']

    def sql(self, statement):
        result = subprocess.run(['docker', 'exec', '-i', self.container,
            'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-At'],
            input=statement, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr[-5000:])
        return result.stdout

    def person(self, label):
        email = f'{label}-{secrets.token_hex(6)}@example.invalid'
        password = secrets.token_urlsafe(32)
        user = self.request('/auth/v1/admin/users',
            {'email': email, 'password': password, 'email_confirm': True})
        auth = self.request('/auth/v1/token?grant_type=password', {'email': email, 'password': password})
        return {'user_id': user['id'], 'token': auth['access_token'],
                'refresh_token': auth['refresh_token'], 'email': email}

    def worker_env(self, worker_id):
        env = super().worker_env(worker_id)
        return {k: v for k, v in env.items()
                if not any(word in k.upper() for word in ('STRIPE', 'SQUARE', 'PAYPAL', 'SMTP'))}

    def edge(self, name, data, token):
        return self.request('/functions/v1/' + name, data, token, timeout=300)

    def rows(self, query):
        return json.loads(self.sql('select coalesce(json_agg(q),\'[]\') from (' + query + ') q'))
