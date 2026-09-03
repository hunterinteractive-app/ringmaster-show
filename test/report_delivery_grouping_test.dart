import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/report_delivery_grouping.dart';

void main() {
  test('groups every file from one provider message into one display row', () {
    final groups = groupReportDeliveriesForDisplay([
      {
        'id': 'delivery-1',
        'provider_message_id': 'message-1',
        'artifact_id': 'report-file',
      },
      {
        'id': 'delivery-2',
        'provider_message_id': 'message-1',
        'artifact_id': 'legs-file',
      },
      {
        'id': 'delivery-3',
        'provider_message_id': 'message-2',
        'artifact_id': 'other-user-file',
      },
    ]);

    expect(groups, hasLength(2));
    expect(groups.first, hasLength(2));
    expect(
      groups.first.map((row) => row['artifact_id']),
      containsAll(['report-file', 'legs-file']),
    );
  });

  test('groups provider failures from the same database insert attempt', () {
    final groups = groupReportDeliveriesForDisplay([
      {
        'id': 'delivery-1',
        'provider_message_id': null,
        'recipient_email': 'person@example.com',
        'subject': 'Show reports',
        'created_at': '2026-09-03T12:00:00Z',
      },
      {
        'id': 'delivery-2',
        'provider_message_id': null,
        'recipient_email': 'PERSON@example.com',
        'subject': 'Show reports',
        'created_at': '2026-09-03T12:00:00Z',
      },
    ]);

    expect(groups, hasLength(1));
    expect(groups.single, hasLength(2));
  });
}
