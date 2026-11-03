"""Prepare synthetic recognition examples in the existing local Show database.
No production configuration, real recipients, or service keys are written.
"""
import base64
import json
import re
import subprocess
import urllib.request
from pathlib import Path

PROJECT = 'ringmaster-show-full-e2e-convention'
URL = 'http://127.0.0.1:55321'
EMAIL = 'recognition-preview@example.invalid'
PASSWORD = 'Local-recognition-preview-2026!'
config = subprocess.check_output(['docker', 'exec', f'supabase_kong_{PROJECT}', 'cat', '/home/kong/kong.yml'], text=True)
# The local gateway maps public API keys to JWTs. Keep the admin token in memory.
def key_for(username):
    for token in re.findall(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', config):
        payload = token.split('.')[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        if claims.get('role') == username:
            return token
    raise RuntimeError('Local gateway token not found')
service = key_for('service_role')
anon = key_for('anon')
def api(path, payload=None, method=None):
    request = urllib.request.Request(URL + path, data=None if payload is None else json.dumps(payload).encode(),
        headers={'apikey': service, 'Authorization':'Bearer '+service,'Content-Type':'application/json'}, method=method)
    with urllib.request.urlopen(request) as response:
        return json.load(response)
users = api('/auth/v1/admin/users?per_page=1000')['users']
user = next((u for u in users if u.get('email') == EMAIL), None)
if user is None:
    user = api('/auth/v1/admin/users', {'email':EMAIL,'password':PASSWORD,'email_confirm':True})
else:
    api('/auth/v1/admin/users/'+user['id'], {'password':PASSWORD,'email_confirm':True}, 'PUT')
uid = user['id']
from uuid import UUID
UUID(uid)
sql = f"insert into public.super_admins(user_id) values ('{uid}') on conflict do nothing;\n"
subjects = [
    ('Velveteen Lop (COD)', '', 'cod'),
    ('Velveteen Lop (COD)', 'Solid', 'cod'),
    ('Velveteen Lop (COD)', 'Broken', 'cod'),
    ('French Lop', 'Otter (COD)', 'cod'),
    ('Mini Rex', 'Brindle (COD)', 'cod'),
    ('Satin', 'Silver Marten (COD)', 'cod'),
    ('Netherland Dwarf', 'Frosty (COD)', 'cod'),
]
def q(s): return "'"+s.replace("'","''")+"'"
for breed, variety, status in subjects:
    sql += f"""
insert into public.breeds(name,species,class_system,is_active)
select {q(breed)},'rabbit','four',true where not exists(select 1 from public.breeds where species='rabbit' and public.catalog_recognition_key(name)=public.catalog_recognition_key({q(breed)}));
"""
    if variety:
        sql += f"""
insert into public.varieties(breed_id,name,is_active)
select b.id,{q(variety)},true from public.breeds b where b.species='rabbit' and public.catalog_recognition_key(b.name)=public.catalog_recognition_key({q(breed)})
and not exists(select 1 from public.varieties v where v.breed_id=b.id and public.catalog_recognition_key(v.name)=public.catalog_recognition_key({q(variety)}));
"""
    sql += f"""
insert into public.catalog_recognition_history(species,breed_name,variety_name,status,effective_date,source_note,created_by)
values ('rabbit',{q(breed)},{q(variety)},'cod','2026-01-01','LOCAL TEST: sample COD start date, not an official historical date','{uid}') on conflict do nothing;
"""
    if variety != 'Broken':
        sql += f"""
insert into public.catalog_recognition_history(species,breed_name,variety_name,status,effective_date,source_note,created_by)
values ('rabbit',{q(breed)},{q(variety)},'recognized','2026-12-01','LOCAL TEST: December 1 recognition example','{uid}') on conflict do nothing;
"""
subprocess.run(['docker','exec','-i',f'supabase_db_{PROJECT}','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'], input=sql,text=True,check=True,capture_output=True)
output=Path('/tmp/ringmaster-recognition-preview-defines.json')
output.write_text(json.dumps({'SUPABASE_URL':URL,'SUPABASE_ANON_KEY':anon,'PREVIEW_EMAIL':EMAIL,'PREVIEW_PASSWORD':PASSWORD}))
output.chmod(0o600)
print('Prepared local recognition preview and synthetic admin. No production changes.')
