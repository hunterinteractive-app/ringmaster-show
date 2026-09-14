import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/entry_refund_dialog.dart';
import 'package:ringmaster_show/services/entry_refund_service.dart';
import 'package:ringmaster_show/services/support_impersonation_session.dart';

class FakeRefundService extends EntryRefundService {
  FakeRefundService({this.manual = false, this.failFirst = false})
    : super(
        client: SupabaseClient(
          'https://example.invalid',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final bool manual, failFirst;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> options(
    String showId,
    String exhibitorId,
  ) async => {
    'enabled': true,
    'locked': false,
    'history': [],
    'entries': [
      {
        'id': 'entry-1',
        'section': 'Open A',
        'tattoo': 'RF1',
        'breed': 'Dutch',
        'is_fur': false,
      },
      {
        'id': 'entry-2',
        'section': 'Open B',
        'tattoo': 'RF2',
        'breed': 'Dutch',
        'is_fur': false,
      },
    ],
    'payments': [
      {
        'id': 'payment-1',
        'provider': manual ? 'cash' : 'stripe',
        'manual': manual,
        'method': manual ? 'cash' : 'card',
        'paid_at': '2026-09-14T10:00:00Z',
        'currency': 'USD',
        'remaining_entry_cents': 2000,
        'remaining_online_fee_cents': manual ? 0 : 100,
        'entries': [
          {'id': 'entry-1', 'suggested_cents': 1000},
          {'id': 'entry-2', 'suggested_cents': 1000},
        ],
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async {
    requests.add(Map.from(body));
    if (failFirst && requests.length == 1) throw Exception('Connection lost');
    return {'status': manual ? 'succeeded' : 'pending'};
  }
}

Future<void> openDialog(WidgetTester tester, FakeRefundService service) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EntryRefundDialog(
          showId: 'show',
          exhibitorId: 'exhibitor',
          exhibitorName: 'Test Exhibitor',
          initialEntryId: 'entry-1',
          service: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'support viewing cannot submit a refund or obtain refund access',
    () async {
      final service = EntryRefundService(
        client: SupabaseClient(
          'https://example.invalid',
          'key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      SupportImpersonationSession.start(
        const SupportImpersonatedUser(
          userId: 'owner',
          email: '',
          displayName: '',
          exhibitorName: '',
        ),
      );
      addTearDown(SupportImpersonationSession.stop);
      expect(await service.canRefund('show'), isFalse);
      await expectLater(service.submit({'action': 'refund'}), throwsStateError);
    },
  );
  test('money parsing uses exact cents and rejects invalid amounts', () {
    expect(refundAmountCents('10.01'), 1001);
    expect(refundAmountCents('5.5'), 550);
    for (final value in ['-1', '1.001', 'NaN', '1e3', '']) {
      expect(refundAmountCents(value), isNull);
    }
  });
  testWidgets('selected entry and optional fee are reviewed before sending', (
    tester,
  ) async {
    final service = FakeRefundService();
    await openDialog(tester, service);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for refund'),
      'Entry canceled',
    );
    await tester.tap(find.text('Include online fees'));
    await tester.pumpAndSettle();
    expect(find.text('0.50'), findsOneWidget);
    await tester.tap(find.text('Review Refund'));
    await tester.pumpAndSettle();
    expect(service.requests, isEmpty);
    expect(find.textContaining('Total: USD 10.50'), findsOneWidget);
    await tester.tap(find.text('Issue Refund & Remove'));
    await tester.pumpAndSettle();
    expect(service.requests.single['entry_ids'], ['entry-1']);
    expect(service.requests.single['entry_amount_cents'], 1000);
    expect(service.requests.single['online_fee_cents'], 50);
    expect(find.textContaining('Refund is pending.'), findsOneWidget);
  });
  testWidgets(
    'ambiguous response reuses exact request instead of a new refund',
    (tester) async {
      final service = FakeRefundService(failFirst: true);
      await openDialog(tester, service);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason for refund'),
        'Entry canceled',
      );
      await tester.tap(find.text('Review Refund'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Issue Refund & Remove'));
      await tester.pumpAndSettle();
      expect(service.requests.length, 1);
      await tester.tap(find.text('Check / Retry Existing Refund'));
      await tester.pumpAndSettle();
      expect(service.requests.length, 2);
      expect(service.requests[1], service.requests[0]);
    },
  );
  testWidgets('manual refunds require confirmation of money returned', (
    tester,
  ) async {
    final service = FakeRefundService(manual: true);
    await openDialog(tester, service);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for refund'),
      'Cash returned',
    );
    await tester.tap(find.text('Review Refund'));
    await tester.pumpAndSettle();
    expect(service.requests, isEmpty);
    expect(
      find.textContaining('Confirm the money has been returned.'),
      findsOneWidget,
    );
    await tester.tap(
      find.text(
        'I have returned this money to the exhibitor outside RingMaster.',
      ),
    );
    await tester.tap(find.text('Review Refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record Refund & Remove'));
    await tester.pumpAndSettle();
    expect(service.requests.single['manual_returned'], true);
    expect(service.requests.single['online_fee_cents'], 0);
    expect(find.textContaining('Refund completed.'), findsOneWidget);
  });
}
