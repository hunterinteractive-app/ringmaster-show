import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/closeout_status_error_message.dart';

void main() {
  test('replaces the production Postgres timeout with secretary-safe copy', () {
    const raw =
        'PostgrestException(message: canceling statement due to statement '
        'timeout, code: 57014, details: , hint: null)';

    expect(isCloseoutStatusStatementTimeout(raw), isTrue);
    expect(
      closeoutReportStatusErrorMessage(raw),
      closeoutReportStatusTimeoutMessage,
    );
    expect(closeoutReportStatusErrorMessage(raw), isNot(contains('57014')));
    expect(
      closeoutReportStatusErrorMessage(raw),
      isNot(contains('PostgrestException')),
    );
  });

  test('detects timeout code even when the message wording changes', () {
    expect(
      closeoutReportStatusErrorMessage('database request failed, code=57014'),
      closeoutReportStatusTimeoutMessage,
    );
  });

  test('leaves unrelated status errors available for diagnosis', () {
    const raw = 'Permission denied';
    expect(closeoutReportStatusErrorMessage(raw), raw);
  });
}
