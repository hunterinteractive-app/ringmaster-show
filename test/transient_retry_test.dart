import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/reporting_core/network/transient_retry.dart';
import 'package:supabase/supabase.dart';

void main() {
  test(
    'a retried page keeps the cursor and recovers from pool exhaustion',
    () async {
      var attempts = 0;
      final delays = <Duration>[];
      final value = await retryTransient(
        () async {
          if (++attempts < 3) {
            throw const PostgrestException(
              message: 'pool busy',
              code: 'PGRST003',
            );
          }
          return 'complete page';
        },
        wait: (delay) async {
          delays.add(delay);
        },
      );
      expect(value, 'complete page');
      expect(attempts, 3);
      expect(delays, hasLength(2));
      expect(delays.last.inMilliseconds, greaterThanOrEqualTo(500));
    },
  );
  test('exhausted retries fail instead of returning partial data', () async {
    var attempts = 0;
    await expectLater(
      retryTransient(() async {
        attempts++;
        throw const PostgrestException(message: 'pool busy', code: 'PGRST003');
      }, wait: (_) async {}),
      throwsA(isA<PostgrestException>()),
    );
    expect(attempts, 3);
  });
  for (final error in <Object>[
    const PostgrestException(message: 'permission', code: '42501'),
    const AuthException('Invalid code', statusCode: '401'),
    const AuthException('Rate limited', statusCode: '429'),
    const FunctionException(status: 400),
  ]) {
    test('does not retry $error', () async {
      var attempts = 0;
      await expectLater(
        retryTransient(() async {
          attempts++;
          throw error;
        }, wait: (_) async {}),
        throwsA(same(error)),
      );
      expect(attempts, 1);
    });
  }
}
