import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/submitted_balance_payment.dart';

void main() {
  testWidgets('shows balance and requires confirmation before checkout', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmittedBalancePayment(
            showId: 'show',
            loadBalances: () async => [
              {
                'cart_id': 'cart',
                'exhibitors': 'Test Exhibitor',
                'currency': 'usd',
                'balance_due_cents': 2400,
                'online_available': true,
              },
            ],
            startCheckout: (id) async {
              attempts++;
              throw Exception('test provider unavailable');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Exhibitor — USD 24.00 outstanding'), findsOneWidget);
    await tester.tap(find.text('Pay outstanding balance'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(
      find.textContaining('Your entries will remain submitted.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    await tester.tap(find.text('Pay outstanding balance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to secure payment'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.textContaining('test provider unavailable'), findsOneWidget);
  });
  testWidgets('no unpaid submissions shows no payment action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SubmittedBalancePayment(
          showId: 'show',
          loadBalances: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pay outstanding balance'), findsNothing);
  });
  testWidgets('provider not ready disables payment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SubmittedBalancePayment(
          showId: 'show',
          loadBalances: () async => [
            {
              'exhibitors': 'Test',
              'balance_due_cents': 800,
              'online_available': false,
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
  });
}
