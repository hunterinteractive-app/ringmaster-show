"""Explicit capacity contract shared by preparation and supervision."""

CAPACITY = dict(auth_pool=20, rest_pool=30, gateway_connections=8192,
                auth_request_timeout_seconds=30)


def verify_capacity(actual, expected):
    for key in ('auth_pool', 'rest_pool', 'auth_request_timeout_seconds'):
        if actual.get(key) != expected[key]:
            raise AssertionError(f'{key} changed: {actual.get(key)} != {expected[key]}')
    gateway = actual['verified_gateway_settings']
    wanted = dict(worker_connections=expected['gateway_connections'],
                  worker_rlimit_nofile=expected['gateway_connections'] * 2)
    if gateway != wanted:
        raise AssertionError(f'Gateway capacity changed: {gateway} != {wanted}')
    if actual['verified_rest_settings']['db-pool'] != str(expected['rest_pool']):
        raise AssertionError('Effective REST pool does not match the plan')
