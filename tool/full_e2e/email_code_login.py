"""Actual app OTP request and verification, with six-digit codes from local SMTP.

Mailbox reads model receiving the email. No admin-generated tokens, passwords,
pre-authentication or direct database token reads are used for purchaser login.
"""
import json,re,threading,time,urllib.request,urllib.parse
from datetime import datetime
from urllib.parse import urlparse
from configure_capacity import _configure_service
from registration_retry import transient

class LocalEmailCodes:
    def __init__(self,lab,nonce,output,*,recipient_filter=None):
        self.lab=lab;self.nonce=nonce;self.output=output;self.recipient_filter=recipient_filter or ('burst-'+nonce);self.codes={};self.received_at={};self.lock=threading.Condition();self.stop=threading.Event();self.error=None
        self.url=lab.local.get('MAILPIT_URL') or lab.local['INBUCKET_URL']
        assert urlparse(self.url).hostname in ('127.0.0.1','localhost')
        self.thread=threading.Thread(target=self.collect,daemon=True)
    def start(self):
        settings={'GOTRUE_MAILER_TEMPLATES_MAGIC_LINK':'http://host.docker.internal:8769/auth-email-template','GOTRUE_MAILER_TEMPLATES_CONFIRMATION':'http://host.docker.internal:8769/auth-email-template'}
        evidence=_configure_service(self.lab,'auth',settings)
        (self.output/'email-code-config.json').write_text(json.dumps(evidence,indent=2))
        self.thread.start()
    def collect(self):
        while not self.stop.is_set():
            try:
                url=self.url+'/api/v1/search?'+urllib.parse.urlencode(dict(query='to:'+self.recipient_filter,limit=1000))
                with urllib.request.urlopen(url,timeout=10) as r:payload=json.load(r)
                self.accept_messages(payload['messages'])
            except Exception as e:self.error=str(e)
            self.stop.wait(.3)
    def accept_messages(self,messages):
        for message in messages:
            code=re.search(r'Synthetic login code:\s*(\d{6})',message['Snippet'])
            if code:
                stamp=datetime.fromisoformat(message['Created'].replace('Z','+00:00')).timestamp()
                with self.lock:
                    for person in message['To']:
                        email=person['Address']
                        if stamp>self.received_at.get(email,0):
                            self.codes[email]=code[1];self.received_at[email]=stamp
                    self.lock.notify_all()
    def login(self,test,email,session):
        from local import ApiError
        assert email.endswith('@example.invalid')
        def record(stage,error,round):
            with test.lock:
                with (self.output/'auth-http-failures.jsonl').open('a') as f:
                    f.write(json.dumps(dict(session=session,stage=stage,round=round,error=str(error)[:1000]))+'\n')
        for round in (1,2):
            # Use the mailbox's own timestamp watermark; host and Docker clocks
            # can differ slightly, especially on a fast resend.
            with self.lock:previous_message=self.received_at.get(email,0)
            sent=True
            try:self.lab.request('/auth/v1/otp',dict(email=email,create_user=True),self.lab.anon,timeout=90)
            except Exception as e:
                if not transient(e,function=True):raise
                sent=False;record('uncertain_code_request',e,round)
            # Match the app: allow code entry even after an uncertain request.
            # A user may explicitly resend only after the 60-second countdown.
            resend_at=time.monotonic()+60
            deadline=time.monotonic()+30
            with self.lock:
                while self.received_at.get(email,0)<=previous_message and time.monotonic()<deadline:self.lock.wait(timeout=.5)
                code=self.codes.get(email) if self.received_at.get(email,0)>previous_message else None
            if code:
                try:return self.lab.request('/auth/v1/verify',dict(email=email,token=code,type='email'),self.lab.anon,timeout=90)
                except ApiError as e:
                    if not (not sent and e.code==403):raise
                    record('code_from_uncertain_request_rejected',e,round)
            if round==2:raise RuntimeError('Synthetic login email could not be verified after one explicit resend')
            self.stop.wait(max(0,resend_at-time.monotonic()))
            test.log('simulated_user_code_resend',session=session,after_cooldown_seconds=60)
        raise AssertionError('Unreachable login state')
    def close(self):
        self.stop.set()
        if self.thread.is_alive():self.thread.join(timeout=15)
        (self.output/'email-code-capture-summary.json').write_text(json.dumps(dict(recipients=len(self.codes),collector_error=self.error,external_delivery=False)))
