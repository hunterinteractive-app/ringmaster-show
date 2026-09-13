import contextlib,io,unittest
from unittest.mock import patch
import configure_capacity
from event_capacity import CAPACITY,verify_capacity

class CapacityCliTests(unittest.TestCase):
    def test_old_capacity_reset_is_rejected(self):
        actual=dict(auth_pool=20,rest_pool=30,auth_request_timeout_seconds=30,
                    verified_gateway_settings=dict(worker_connections=8192,worker_rlimit_nofile=16384),
                    verified_rest_settings={'db-pool':'30'})
        verify_capacity(actual,CAPACITY)
        for key,old in [('rest_pool',20),('auth_request_timeout_seconds',10)]:
            with self.subTest(key=key),self.assertRaises(AssertionError):
                verify_capacity({**actual,key:old},CAPACITY)
        with self.assertRaises(AssertionError):
            verify_capacity({**actual,'verified_gateway_settings':dict(worker_connections=4096,worker_rlimit_nofile=8192)},CAPACITY)
    def test_all_requested_budgets_reach_the_configuration_function(self):
        with patch('sys.argv',['configure_capacity','/tmp/synthetic','--auth-pool','20','--rest-pool','30','--gateway-connections','8192','--auth-request-timeout','30']),patch.object(configure_capacity,'Local',return_value='synthetic-lab'),patch.object(configure_capacity,'configure',return_value={}) as configure,contextlib.redirect_stdout(io.StringIO()):
            configure_capacity.main()
            configure.assert_called_once_with('synthetic-lab',20,30,8192,30)
if __name__=='__main__':unittest.main()
