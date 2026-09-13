import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/stripe_payment_confirmation_dialog.dart';

void main() {
  testWidgets('queued and pending receipts never announce completed entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StripePaymentConfirmationDialog(
          maxAttempts: 1,
          loadStatus: () async => {
            'received': true,
            'queued': true,
            'completed': false,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirmation pending'), findsOneWidget);
    expect(find.text('Payment confirmed'), findsNothing);
    expect(find.text('Check again'), findsOneWidget);
  });
  testWidgets('a subsequent saved completion confirms the registration', (
    tester,
  ) async {
    var complete = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StripePaymentConfirmationDialog(
          maxAttempts: 1,
          loadStatus: () async => {'completed': complete},
        ),
      ),
    );
    await tester.pumpAndSettle();
    complete = true;
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Payment confirmed'), findsOneWidget);
  });
  testWidgets('status request failure keeps payment outcome unconfirmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StripePaymentConfirmationDialog(
          maxAttempts: 1,
          loadStatus: () async => throw Exception('temporarily unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirmation pending'), findsOneWidget);
    expect(find.text('Payment confirmed'), findsNothing);
  });
}
