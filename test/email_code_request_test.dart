import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/services/email_code_request.dart';

void main() {
  test(
    'a lost OTP response permits code entry without sending another code',
    () async {
      var sends = 0;
      final sent = await sendEmailCodeOnce(() async {
        sends++;
        throw const AuthException('Request timed out', statusCode: '504');
      });
      expect(sent, isFalse);
      expect(sends, 1);
    },
  );
  test('a successful send is confirmed', () async {
    expect(await sendEmailCodeOnce(() async {}), isTrue);
  });
  test('rate limits stay visible and are never replayed', () async {
    var sends = 0;
    await expectLater(
      sendEmailCodeOnce(() async {
        sends++;
        throw const AuthException('Wait before resending', statusCode: '429');
      }),
      throwsA(isA<AuthException>()),
    );
    expect(sends, 1);
  });
}
