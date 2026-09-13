import threading,unittest,tempfile
from pathlib import Path
from datetime import datetime,timezone
from types import SimpleNamespace
from local import ApiError
from email_code_login import LocalEmailCodes

class LatestCodeTests(unittest.TestCase):
    def test_newest_email_wins_even_when_mailbox_returns_it_first(self):
        inbox=object.__new__(LocalEmailCodes);inbox.codes={};inbox.received_at={};inbox.lock=threading.Condition()
        def message(stamp,code):return dict(Created=stamp,Snippet='Synthetic login code: '+code,To=[{'Address':'synthetic@example.invalid'}])
        old=message('2026-09-13T01:33:14.909Z','123456');new=message('2026-09-13T01:33:15.467Z','654321')
        inbox.accept_messages([new,old]);self.assertEqual(inbox.codes['synthetic@example.invalid'],'654321')
        inbox.accept_messages([old]);self.assertEqual(inbox.codes['synthetic@example.invalid'],'654321')
    def test_uncertain_response_uses_delivered_code_without_automatic_resend(self):
        with tempfile.TemporaryDirectory() as directory:
            inbox=object.__new__(LocalEmailCodes);inbox.codes={};inbox.received_at={};inbox.lock=threading.Condition();inbox.stop=threading.Event();inbox.output=Path(directory);calls=[]
            def request(path,data,*args,**kwargs):
                calls.append(path)
                if path.endswith('/otp'):
                    inbox.accept_messages([dict(Created=datetime.now(timezone.utc).isoformat(),Snippet='Synthetic login code: 123456',To=[{'Address':data['email']}])])
                    raise ApiError(504,{'error_code':'request_timeout'})
                self.assertEqual(data['token'],'123456');return {'user':{'id':'verified'}}
            inbox.lab=SimpleNamespace(request=request,anon='local')
            test=SimpleNamespace(lock=threading.Lock(),log=lambda *args,**kwargs:None)
            self.assertEqual(inbox.login(test,'synthetic@example.invalid',1),{'user':{'id':'verified'}})
            self.assertEqual(calls,['/auth/v1/otp','/auth/v1/verify'])
if __name__=='__main__':unittest.main()
