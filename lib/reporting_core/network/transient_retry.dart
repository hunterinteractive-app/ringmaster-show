import 'dart:math';

import 'package:supabase/supabase.dart';

/// Only use for reads or operations with an existing idempotency guarantee.
/// Permission/validation failures and rate limits must not cause retry storms.
Future<T> retryTransient<T>(
  Future<T> Function() operation, {
  int maxAttempts = 3,
  Future<void> Function(Duration)? wait,
}) async {
  if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
  final random = Random();
  for (var attempt = 1; ; attempt++) {
    try {
      return await operation();
    } catch (error) {
      if (attempt >= maxAttempts || !isTransientServiceError(error)) rethrow;
      await (wait ?? Future<void>.delayed)(
        Duration(milliseconds: (250 << (attempt - 1)) + random.nextInt(250)),
      );
    }
  }
}

bool isTransientServiceError(Object error) {
  if (error is PostgrestException) {
    return const {
      'PGRST003',
      '53300',
      '57P01',
      '08000',
      '08006',
      '502',
      '503',
      '504',
    }.contains(error.code);
  }
  if (error is AuthException) {
    return const {'500', '502', '503', '504'}.contains(error.statusCode);
  }
  if (error is FunctionException) {
    return const {500, 502, 503, 504}.contains(error.status);
  }
  return false;
}
