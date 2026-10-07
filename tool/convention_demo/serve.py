"""Isolated convention sandbox. Never use a linked or hosted database."""
import argparse
import functools
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import signal
import uuid
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tool/full_e2e'))
from local import Local, SHOW, uid, sql_quote
from run import Rehearsal
from providers import Providers, prepare_functions

PASSWORD = 'Convention-Demo-Only-2026!'
PORT = 8787
GUARD = '''// Convention runtime only: reject outbound requests to non-local services.
const originalFetch = globalThis.fetch;
globalThis.fetch = ((input, init) => {
 const u = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
 if (u.protocol !== 'http:' || !['kong','supabase_kong_ringmaster-show-full-e2e-convention','host.docker.internal','127.0.0.1','localhost'].includes(u.hostname)) {
  throw new Error('Convention demo blocked external request: ' + u.origin);
 }
 return originalFetch(input, init);
}) as typeof fetch;
'''


def patch_runtime(lab):
    for path in (lab.workspace/'supabase/functions').rglob('*.ts'):
        source=path.read_text().replace(GUARD, "")
        source=source.replace('https://api.resend.com/emails', 'http://host.docker.internal:8769/resend/emails')
        source=source.replace('https://api.stripe.com/v1/checkout/sessions','http://host.docker.internal:8769/stripe/v1/checkout/sessions')
        if path.name=='index.ts': source=GUARD+source
        path.write_text(source)


def page(title, body):
    return ('<!doctype html><html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>body{font:18px system-ui;background:#321768;color:#fff;max-width:900px;margin:50px auto;padding:24px}a,button{display:inline-block;background:#ffd137;color:#25133f;padding:16px;margin:8px;border:0;border-radius:12px;font:inherit;text-decoration:none}li{margin:16px 0}pre{white-space:pre-wrap}small{color:#ddd}</style>'
      f'<title>{title}</title><h1>{title}</h1>{body}</html>').encode()


def seed(test):
    lab=test.lab
    # Historical field used by the current checkout RPC, absent from the baseline.
    lab.sql("alter table public.entry_cart_items add column if not exists is_show_addon_carrier boolean not null default false;")
    if not lab.rows(f"select id from entries where show_id='{SHOW}' limit 1"):
        lab.sql("delete from entry_cart_items; delete from entry_carts; delete from animals; delete from show_exhibitor_balances; delete from exhibitors; delete from auth.users;")
    if not lab.rows("select schema_name from information_schema.schemata where schema_name='show_addons_private'"):
        lab.sql((ROOT/'tool/convention_demo/local_addon_contract.sql').read_text())
    test.registration(24)
    names=['Avery Meadow','Jordan Brook','Taylor Willow','Casey Maple','Riley Grove','Morgan Field',
           'Quinn Clover','Jamie Reed','Rowan Hill','Cameron Birch','Alex Fern','Skyler Oak',
           'Emery Meadow','Parker Brook','Finley Willow','Reese Maple','Blair Grove','Robin Field',
           'Drew Clover','Sage Reed','River Hill','Charlie Birch','Sam Fern','Ellis Oak']
    people={}
    for n,name in enumerate(names,1):
        row=lab.rows(f"select owner_user_id from exhibitors where id='{uid('952',n)}'")[0]
        email=f'exhibitor{n}@example.invalid'
        lab.request('/auth/v1/admin/users/'+row['owner_user_id'],dict(email=email,password=PASSWORD,email_confirm=True),method='PUT')
        lab.sql(f"update exhibitors set display_name={sql_quote(name)},first_name={sql_quote(name.split()[0])},last_name={sql_quote(name.split()[1])},email='{email}',type={'\'adult\'' if n<=12 else '\'youth\''} where id='{uid('952',n)}';")
        if n==1: people['exhibitor']=dict(email=email,name=name)
    existing=lab.rows("select id from auth.users where email='secretary@example.invalid'")
    user=existing[0] if existing else lab.request('/auth/v1/admin/users',dict(email='secretary@example.invalid',password=PASSWORD,email_confirm=True))
    sid=user['id']
    lab.sql(f"""insert into exhibitors(owner_user_id,display_name,type,email) select '{sid}','Demo Secretary','adult','secretary@example.invalid' where not exists(select 1 from exhibitors where owner_user_id='{sid}');
      insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{sid}','admin') on conflict do nothing;
      insert into show_managers(show_id,user_id,can_manage_entries,can_manage_settings,can_finalize) values ('{SHOW}','{sid}',true,true,true) on conflict do nothing;
      update shows set name='RingMaster Convention Showcase',owner_user_id='{sid}',is_test=false,is_published=true,
      start_date=current_date+7,end_date=current_date+7,entry_close_at=now()+interval '6 days',
      auto_email_checkin_sheets=true where id='{SHOW}';""")
    lab.sql("insert into profiles(user_id,accepted_terms_version,accepted_privacy_version,accepted_terms_at,accepted_privacy_at) select id,'2026-09','2026-09',now(),now() from auth.users on conflict(user_id) do update set accepted_terms_version='2026-09',accepted_privacy_version='2026-09';")
    people['secretary']=dict(email='secretary@example.invalid',name='Demo Secretary')
    finish_fixture(lab)
    # Snapshot contains fictional data and local Auth credentials only.
    (test.output/'personas.json').write_text(json.dumps(people))
    with (test.output/'baseline.dump').open('wb') as f:
        subprocess.run(['docker','exec','-e','PGPASSWORD=postgres',lab.container,'pg_dump','-U','supabase_admin','-d','postgres','-Fc','--data-only','--schema=public','--schema=auth','--exclude-table=auth.schema_migrations'],stdout=f,check=True)
    (test.output/'ready').write_text('Synthetic demo initialized\n')


def finish_fixture(lab):
    lab.sql((ROOT/'tool/convention_demo/local_report_access.sql').read_text())
    sid=lab.rows("select id from auth.users where email='secretary@example.invalid'")[0]['id']
    club='95000000-0000-0000-0000-000000000099'
    lab.sql(f"""insert into clubs(id,name,club_name,email,is_active) values ('{club}','Meadowbrook Rabbit Club','Meadowbrook Rabbit Club','club@example.invalid',true) on conflict(id) do nothing;
      insert into club_members(club_id,user_id,role,is_active) values ('{club}','{sid}','owner',true) on conflict do nothing;
      update shows set club_id='{club}',club_name='Meadowbrook Rabbit Club',secretary_email='secretary@example.invalid',is_national_show=false where id='{SHOW}';
      insert into role_assignments(show_id,user_id,role) values ('{SHOW}','{sid}','superintendent') on conflict do nothing;
      update exhibitors set exhibitor_number=9000 where owner_user_id='{sid}';""")


def main():
    parser=argparse.ArgumentParser();parser.add_argument('workspace');parser.add_argument('output',type=Path)
    args=parser.parse_args();lab=Local(args.workspace)
    if lab.project!='ringmaster-show-full-e2e-convention':raise ValueError('Wrong local project')
    test=Rehearsal(lab,args.output)
    # Apply guards AFTER the harness has staged its exact provider patches.
    import run
    original_prepare=run.prepare_functions
    def prepare(lab,output):
        result=original_prepare(lab,output);patch_runtime(lab);return result
    run.prepare_functions=prepare
    def stop_demo(*_):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,stop_demo)
    try:
        test.start()
        if not (args.output/'ready').exists(): seed(test)
        lab.sql(f"update shows set start_date=current_date+7,end_date=current_date+7,entry_close_at=now()+interval '6 days' where id='{SHOW}';")
        worker=ROOT/'output/convention-demo/closeout-renderer'
        if worker.exists():
            log=(args.output/'renderer.log').open('a');test.logs.append(log)
            test.children.append(subprocess.Popen([str(worker),'--continuous'],cwd=ROOT,env=lab.worker_env('local-convention-renderer'),stdout=log,stderr=subprocess.STDOUT))
        provider=test.providers
        capture=args.output/'captured-deliveries.jsonl'
        if capture.exists():
            provider.emails.extend(json.loads(line) for line in capture.read_text().splitlines() if line)
        base=provider.server.RequestHandlerClass
        class Checkout(base):
            def do_GET(self):
                if not self.path.startswith('/checkout/'):
                    return super().do_GET()
                sid=self.path.split('/')[-1]
                try: item=provider.checkout(sid)
                except StopIteration:self.send_error(404);return
                body=page('Simulated payment',f'<p>Demo total: ${item["amount_total"]/100:.2f}</p><p>No card is needed. No money will be charged.</p><form method="post" action="/complete/{html.escape(sid)}"><button>Complete demo payment</button></form>')
                self.send_response(200);self.send_header('Content-Length',str(len(body)));self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(body)
            def do_POST(self):
                if self.path=='/resend/emails':
                    if self.headers.get('Authorization')!='Bearer re_local_synthetic_only':self.send_error(401);return
                    size=int(self.headers.get('Content-Length','0'))
                    if size>35_000_000:self.send_error(413);return
                    payload=json.loads(self.rfile.read(size))
                    record={k:v for k,v in payload.items() if k not in ('html','attachments')}
                    record['id']='demo_'+uuid.uuid4().hex
                    record['attachments']=[{'filename':a.get('filename')} for a in payload.get('attachments',[])]
                    with provider.lock:
                        provider.emails.append(record)
                        with (args.output/'captured-deliveries.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
                    body=json.dumps({'id':record['id']}).encode()
                    self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
                if not self.path.startswith('/complete/'):return super().do_POST()
                sid=self.path.split('/')[-1]
                try:
                    test.webhook(provider.checkout(sid),'evt_convention_'+sid)
                    body=page('Demo payment completed','<p>The local show has received the simulated payment.</p><a href="http://127.0.0.1:8787/">Return to RingMaster</a>')
                    self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
                except Exception as e:self.send_error(500,str(e))
        provider.server.RequestHandlerClass=Checkout
        class Web(SimpleHTTPRequestHandler):
            def __init__(self,*a,**kw):super().__init__(*a,directory=str(ROOT/'build/web'),**kw)
            def end_headers(self):
                self.send_header('Cache-Control','no-store')
                self.send_header('Content-Security-Policy',"connect-src 'self' http://127.0.0.1:* http://localhost:* ws://127.0.0.1:*; font-src 'self' data:; img-src 'self' data: blob: http://127.0.0.1:*;")
                super().end_headers()
            def do_GET(self):
                path=urlparse(self.path).path
                if path=='/booth':
                    body=page('RingMaster Convention Demo','<p>The real RingMaster Show app, using fictional local records. Emails and payments are simulated.</p><a href="/?demo_role=secretary">Secretary & superintendent</a><a href="/?demo_role=exhibitor">Exhibitor</a><a href="/mail">Captured emails</a><p>24 exhibitors · 120 entries · Open and Youth · 2 judges</p><a href="/reset-confirm">Reset sample show</a><small>Use one persona at a time. Switching personas changes the account for all demo tabs.</small>')
                elif path=='/reset-confirm':
                    body=page('Reset the demo?', '<p>This restores the original fictional records and clears captured emails. Close other demo tabs first.</p><form action="/reset" method="post"><button>Restore sample show</button></form><a href="/booth">Cancel</a>')
                elif path=='/mail':
                    body=page('Captured demo emails','<a href="/booth">Demo controls</a><p>These messages were captured locally and never delivered.</p><pre>'+html.escape(json.dumps(provider.emails,indent=2))+'</pre>')
                else:return super().do_GET()
                self.send_response(200);self.send_header('Content-Type','text/html');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
            def do_POST(self):
                if self.path!='/reset' or self.headers.get('Origin')!=f'http://127.0.0.1:{PORT}':self.send_error(403);return
                # One transaction, local project is checked above; never touch hosted data.
                tables=lab.rows("select schemaname,tablename from pg_tables where schemaname in ('public','auth') and tablename <> 'schema_migrations'")
                trunc='truncate '+','.join('"'+r['schemaname']+'"."'+r['tablename']+'"' for r in tables)+' cascade;'
                dump=subprocess.run(['pg_restore','--data-only','--disable-triggers','--file=-',str(args.output/'baseline.dump')],capture_output=True,check=True).stdout.decode()
                subprocess.run(['docker','exec','-i','-e','PGPASSWORD=postgres',lab.container,'psql','-X','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d','postgres'],input='begin; set session_replication_role=replica;'+trunc+dump+f"update public.shows set start_date=current_date+7,end_date=current_date+7,entry_close_at=now()+interval '6 days' where id='{SHOW}';"+'commit;',text=True,capture_output=True,check=True)
                provider.emails.clear();provider.sessions.clear();provider.email_keys.clear()
                (args.output/'captured-deliveries.jsonl').write_text('')
                self.send_response(303);self.send_header('Location','/booth');self.end_headers()
        server=ThreadingHTTPServer(('127.0.0.1',PORT),Web)
        print(f'Convention demo ready: http://127.0.0.1:{PORT}/booth',flush=True)
        server.serve_forever()
    finally:test.finish()

if __name__=='__main__':main()
