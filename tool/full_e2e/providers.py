"""Local provider protocol emulation. Captures mail; never relays to the internet."""
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import time
from urllib.parse import parse_qs
import uuid

WEBHOOK_SECRET = 'whsec_local_full_e2e_synthetic_only'


class Providers:
    def __init__(self, output):
        self.output, self.sessions, self.emails = output, {}, []
        self.lock = threading.Lock()
        parent = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_POST(self):
                size = int(self.headers.get('Content-Length','0'))
                if size > 35_000_000:
                    self.send_error(413); return
                raw = self.rfile.read(size)
                if self.path == '/stripe/v1/checkout/sessions':
                    if self.headers.get('Authorization') != 'Bearer sk_test_local_synthetic_only':
                        self.send_error(401); return
                    form = {k:v[0] for k,v in parse_qs(raw.decode()).items()}
                    key = self.headers.get('Idempotency-Key')
                    with parent.lock:
                        if key not in parent.sessions:
                            metadata = {k[9:-1]:v for k,v in form.items() if k.startswith('metadata[')}
                            sid = 'cs_test_local_' + uuid.uuid4().hex
                            amount = sum(int(v) for k,v in form.items() if k.endswith('[price_data][unit_amount]'))
                            parent.sessions[key] = dict(id=sid,object='checkout.session',
                                url='http://127.0.0.1:8769/checkout/'+sid,
                                expires_at=int(time.time())+86400,metadata=metadata,
                                amount_total=amount,currency='usd',payment_status='paid',
                                payment_intent='pi_local_'+uuid.uuid4().hex)
                        response = parent.sessions[key]
                elif self.path == '/resend/emails':
                    if self.headers.get('Authorization') != 'Bearer re_local_synthetic_only':
                        self.send_error(401); return
                    payload = json.loads(raw)
                    # Fail closed if fixture addresses ever become real addresses.
                    for field in ('to','bcc','reply_to'):
                        addresses = payload.get(field,[])
                        if isinstance(addresses,str): addresses=[addresses]
                        if any(not a.endswith('@example.invalid') for a in addresses):
                            self.send_error(400,'Only synthetic recipients are accepted'); return
                    record = {k:v for k,v in payload.items() if k not in ('html','attachments')}
                    record['id'] = str(uuid.uuid4())
                    record['attachments'] = []
                    for a in payload.get('attachments',[]):
                        content = base64.b64decode(a['content'],validate=True)
                        record['attachments'].append(dict(filename=a['filename'],size=len(content),sha256=hashlib.sha256(content).hexdigest()))
                    with parent.lock:
                        parent.emails.append(record)
                        with (parent.output/'captured-deliveries.jsonl').open('a') as f:
                            f.write(json.dumps(record)+'\n')
                    response = {'id':record['id']}
                else:
                    self.send_error(404); return
                body=json.dumps(response).encode()
                self.send_response(200); self.send_header('Content-Type','application/json')
                self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
        self.server = ThreadingHTTPServer(('127.0.0.1',8769),Handler)
        self.thread = threading.Thread(target=self.server.serve_forever,daemon=True)

    def start(self): self.thread.start()
    def stop(self):
        if self.thread.is_alive():
            self.server.shutdown()
            self.thread.join()
        self.server.server_close()

    def checkout(self, sid):
        with self.lock:
            return next(v.copy() for v in self.sessions.values() if v['id']==sid)


def prepare_functions(lab, output):
    from local import ROOT
    patches = {
        'stripe-create-checkout-session':('https://api.stripe.com/v1/checkout/sessions','http://host.docker.internal:8769/stripe/v1/checkout/sessions'),
        'send-report-email':('https://api.resend.com/emails','http://host.docker.internal:8769/resend/emails'),
    }
    evidence = []
    for name,(source,destination) in patches.items():
        original=(ROOT/'supabase/functions'/name/'index.ts').read_text()
        assert original.count(source)==1
        modified=original.replace(source,destination)
        (lab.workspace/'supabase/functions'/name/'index.ts').write_text(modified)
        evidence.append(dict(function=name,only_change=dict(source=source,destination=destination),source_sha256=hashlib.sha256(original.encode()).hexdigest(),local_sha256=hashlib.sha256(modified.encode()).hexdigest()))
    (output/'provider-boundary.json').write_text(json.dumps(evidence,indent=2))
    env_file=lab.workspace/'local-provider.env'
    env_file.write_text('\n'.join([
        'STRIPE_SECRET_KEY=sk_test_local_synthetic_only',
        'STRIPE_WEBHOOK_SECRET='+WEBHOOK_SECRET,
        'RESEND_API_KEY=re_local_synthetic_only',
        'RESEND_FROM_EMAIL=Local Rehearsal <sender@example.invalid>',
        'APP_BASE_URL=http://127.0.0.1:8769',
    ])+'\n')
    env_file.chmod(0o600)
    config=lab.workspace/'supabase/config.toml'
    text=config.read_text()
    if '[functions.stripe-webhook]' not in text:
        config.write_text(text+'\n[functions.stripe-webhook]\nverify_jwt = false\n')
    return env_file
