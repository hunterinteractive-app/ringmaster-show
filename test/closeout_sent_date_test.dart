import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/closeout_sent_date.dart';

void main() {
  test('formats stored delivery timestamps for the closeout form', () {
    expect(formatCloseoutSentDate('2026-09-05T18:45:34.287Z'), '9/5/2026');
  });

  test('accepts a valid manually entered sent date', () {
    final parsed = parseCloseoutSentDate('9/5/2026');

    expect(parsed, isNotNull);
    expect(parsed!.year, 2026);
    expect(parsed.month, 9);
    expect(parsed.day, 5);
    expect(
      closeoutSentDateToIso8601('9/5/2026', fieldLabel: 'Club reports date'),
      parsed.toUtc().toIso8601String(),
    );
  });

  test('rejects impossible and incorrectly formatted dates', () {
    expect(parseCloseoutSentDate('2/30/2026'), isNull);
    expect(parseCloseoutSentDate('2026-09-05'), isNull);
    expect(
      () => closeoutSentDateToIso8601(
        'September 5',
        fieldLabel: 'Club reports date',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('allows a manually entered date to be cleared', () {
    expect(
      closeoutSentDateToIso8601('', fieldLabel: 'Club reports date'),
      isNull,
    );
  });
}
