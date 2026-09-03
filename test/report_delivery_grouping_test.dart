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

  test('sorts error groups ahead of successful deliveries', () {
    final groups = groupReportDeliveriesForDisplay([
      {
        'id': 'new-success',
        'provider_message_id': 'message-success',
        'delivery_status': 'delivered',
        'sent_at': '2026-09-03T13:00:00Z',
      },
      {
        'id': 'old-error',
        'provider_message_id': 'message-error',
        'delivery_status': 'bounced',
        'sent_at': '2026-09-03T12:00:00Z',
      },
    ])..sort(compareReportDeliveryGroupsForDisplay);

    expect(groups.first.single['id'], 'old-error');
  });

  test('keeps newest-first order within each status group', () {
    final groups = groupReportDeliveriesForDisplay([
      {
        'id': 'old-error',
        'provider_message_id': 'message-old-error',
        'delivery_status': 'failed',
        'sent_at': '2026-09-03T12:00:00Z',
      },
      {
        'id': 'new-error',
        'provider_message_id': 'message-new-error',
        'delivery_status': 'suppressed',
        'sent_at': '2026-09-03T13:00:00Z',
      },
      {
        'id': 'old-success',
        'provider_message_id': 'message-old-success',
        'delivery_status': 'sent',
        'sent_at': '2026-09-03T10:00:00Z',
      },
      {
        'id': 'new-success',
        'provider_message_id': 'message-new-success',
        'delivery_status': 'delivered',
        'sent_at': '2026-09-03T11:00:00Z',
      },
    ])..sort(compareReportDeliveryGroupsForDisplay);

    expect(groups.map((group) => group.single['id']), [
      'new-error',
      'old-error',
      'new-success',
      'old-success',
    ]);
  });

  test('marks an older failed package fixed after a successful resend', () {
    final groups = groupReportDeliveriesForDisplay([
      {
        'id': 'failed-attempt',
        'provider_message_id': 'failed-message',
        'artifact_id': 'report-file',
        'delivery_status': 'bounced',
        'created_at': '2026-09-03T12:00:00Z',
      },
      {
        'id': 'failed-legs',
        'provider_message_id': 'failed-message',
        'artifact_id': 'legs-file',
        'delivery_status': 'bounced',
        'created_at': '2026-09-03T12:00:00Z',
      },
      {
        'id': 'resent-attempt',
        'provider_message_id': 'resent-message',
        'artifact_id': 'report-file',
        'delivery_status': 'delivered',
        'sent_at': '2026-09-03T13:00:00Z',
      },
      {
        'id': 'resent-legs',
        'provider_message_id': 'resent-message',
        'artifact_id': 'legs-file',
        'delivery_status': 'delivered',
        'sent_at': '2026-09-03T13:00:00Z',
      },
    ]);

    expect(resolvedReportDeliveryFailureKeys(groups), {
      'provider:failed-message',
    });
  });

  test('does not resolve a failed package after another failed retry', () {
    final groups = groupReportDeliveriesForDisplay([
      {
        'id': 'first-failure',
        'provider_message_id': 'first-failed-message',
        'artifact_id': 'report-file',
        'delivery_status': 'bounced',
        'created_at': '2026-09-03T12:00:00Z',
      },
      {
        'id': 'retry-failure',
        'provider_message_id': 'retry-failed-message',
        'artifact_id': 'report-file',
        'delivery_status': 'failed',
        'created_at': '2026-09-03T13:00:00Z',
      },
    ]);

    expect(resolvedReportDeliveryFailureKeys(groups), isEmpty);
  });

  test('moves fixed failures out of the active error section', () {
    final groups = groupReportDeliveriesForDisplay([
      {
        'id': 'fixed-failure',
        'provider_message_id': 'fixed-message',
        'artifact_id': 'fixed-file',
        'delivery_status': 'bounced',
        'created_at': '2026-09-03T12:00:00Z',
      },
      {
        'id': 'fixed-success',
        'provider_message_id': 'success-message',
        'artifact_id': 'fixed-file',
        'delivery_status': 'sent',
        'sent_at': '2026-09-03T13:00:00Z',
      },
      {
        'id': 'active-failure',
        'provider_message_id': 'active-message',
        'artifact_id': 'active-file',
        'delivery_status': 'failed',
        'created_at': '2026-09-03T11:00:00Z',
      },
    ]);
    final resolved = resolvedReportDeliveryFailureKeys(groups);
    groups.sort(
      (a, b) => compareReportDeliveryGroupsForDisplay(
        a,
        b,
        resolvedFailureKeys: resolved,
      ),
    );

    expect(groups.first.single['id'], 'active-failure');
  });
}
