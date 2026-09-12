"""Keep the load client's error classification aligned with Dart exception types."""
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from local import ApiError
from registration_retry import retry,transient

class RegistrationRetryTest(unittest.TestCase):
    def test_edge_runtime_500_retries_even_with_a_non_database_code(self):
        error=ApiError(500,{'code':'Internal Server Error','message':'WorkerAlreadyRetired'})
        with tempfile.TemporaryDirectory() as directory:
            test=SimpleNamespace(output=Path(directory),lock=threading.Lock());calls=[]
            def operation():
                calls.append(1)
                if len(calls)==1:raise error
                return 'recovered'
            with patch('registration_retry.time.sleep'):
                self.assertEqual(retry(test,'account_lookup',1,operation,function=True),'recovered')
            self.assertEqual(len(calls),2)
            self.assertIn('"retry": true',(test.output/'registration-http-failures.jsonl').read_text())

    def test_database_errors_use_database_code(self):
        self.assertTrue(transient(ApiError(504,{'code':'PGRST003'})))
        self.assertFalse(transient(ApiError(500,{'code':'42501'})))
        self.assertFalse(transient(ApiError(500,{})))
        self.assertFalse(transient(ApiError(409,{'code':'23505'})))

    def test_function_auth_validation_and_rate_limits_do_not_retry(self):
        for status in (400,401,403,429):
            self.assertFalse(transient(ApiError(status,{'code':'Internal Server Error'}),function=True))

    def test_function_retries_are_bounded_to_three(self):
        with tempfile.TemporaryDirectory() as directory:
            test=SimpleNamespace(output=Path(directory),lock=threading.Lock());calls=[]
            def operation():
                calls.append(1);raise ApiError(503,{'code':'BOOT_ERROR'})
            with patch('registration_retry.time.sleep'):
                with self.assertRaises(ApiError):retry(test,'account_lookup',1,operation,function=True)
            self.assertEqual(len(calls),3)

if __name__=='__main__':unittest.main()
