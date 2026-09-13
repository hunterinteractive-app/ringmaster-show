"""A webhook receipt cannot count as a completed purchaser."""
import threading,unittest
from types import SimpleNamespace
from run import Rehearsal

class CompletionTests(unittest.TestCase):
    def test_waits_for_saved_entries_and_payment(self):
        pending={'completed':False,'saved_paid_entries':0}
        done={'completed':True,'expected_entries':10,'saved_paid_entries':10,'payment_records':1,'paid_records':1}
        states=iter([pending,done]);calls=[]
        def rpc(*args):calls.append(args);return next(states)
        fixture=SimpleNamespace(lab=SimpleNamespace(rpc=rpc),stop=SimpleNamespace(wait=lambda _:None))
        self.assertEqual(Rehearsal.wait_for_registration(fixture,'cart','owner',1,10),done)
        self.assertEqual(len(calls),2)
    def test_incomplete_counts_cannot_pass_even_with_completed_flag(self):
        for mismatch in ({'saved_paid_entries':9},{'paid_records':0},{'payment_records':2}):
            state={'completed':True,'expected_entries':10,'saved_paid_entries':10,'payment_records':1,'paid_records':1,**mismatch}
            fixture=SimpleNamespace(lab=SimpleNamespace(rpc=lambda *args:state),stop=threading.Event())
            with self.assertRaises(AssertionError):Rehearsal.wait_for_registration(fixture,'cart','owner',1,10)
    def test_receipt_without_completion_times_out(self):
        fixture=SimpleNamespace(lab=SimpleNamespace(rpc=lambda *args:{'queued':True}),stop=SimpleNamespace(wait=lambda _:None))
        with self.assertRaisesRegex(RuntimeError,'not durably finalized'):
            Rehearsal.wait_for_registration(fixture,'cart','owner',1,10,timeout=.001)
if __name__=='__main__':unittest.main()
