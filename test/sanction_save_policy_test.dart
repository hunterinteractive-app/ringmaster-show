import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/sanction_save_policy.dart';

void main() {
  test('saving blank numbers preserves pending requests and problems', () {
    for (final status in [
      'secretary_requested',
      'exhibitor_requested',
      'problem',
      ' SECRETARY_REQUESTED ',
    ]) {
      expect(preserveSanctionWithoutNumber(status), isTrue, reason: status);
    }
  });

  test('received numbers and unflagged rows can still be cleared', () {
    for (final status in [null, '', ' ', 'received', ' RECEIVED ']) {
      expect(preserveSanctionWithoutNumber(status), isFalse, reason: '$status');
    }
  });
}
