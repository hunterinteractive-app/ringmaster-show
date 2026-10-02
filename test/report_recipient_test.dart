import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/report_recipient.dart';

void main() {
  final contacts = <String, Map<String, dynamic>>{
    'one': {'email': ' current@example.com '},
    'two': {'email': 'other@example.com'},
  };
  test('missing generated email resolves from current exhibitor ID', () {
    expect(
      exhibitorReportRecipient({'exhibitor_id': 'one'}, contacts),
      'current@example.com',
    );
  });
  test('current address replaces stale metadata', () {
    expect(
      exhibitorReportRecipient({
        'exhibitor_id': 'one',
        'exhibitor_email': 'old@example.com',
      }, contacts),
      'current@example.com',
    );
  });
  test('blank primary metadata does not hide fallback email', () {
    expect(
      exhibitorReportRecipient({
        'exhibitor_email': ' ',
        'email': 'saved@example.com',
      }, {}),
      'saved@example.com',
    );
  });
  test('no matching identity does not borrow another exhibitor address', () {
    expect(
      exhibitorReportRecipient({
        'exhibitor_id': 'missing',
        'exhibitor_name': 'one',
      }, contacts),
      isNull,
    );
  });
}
