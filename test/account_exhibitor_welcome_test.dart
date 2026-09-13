import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/account_exhibitor_welcome.dart';

void main() {
  const exhibitors = [
    {'id': 'one', 'display_name': 'Alex Example', 'exhibitor_number': 1003},
    {'id': 'two', 'display_name': 'Sam Example', 'exhibitor_number': 2045},
  ];
  testWidgets('switches welcome name and number between account exhibitors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: AccountExhibitorWelcome(
              exhibitors: exhibitors,
              initialExhibitorId: 'one',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Welcome, Alex Example').hitTestable(), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam Example\nExhibitor #2045').last);
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Sam Example').hitTestable(), findsOneWidget);
    expect(find.text('Exhibitor #2045').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'single exhibitor shows name and missing number without a picker',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccountExhibitorWelcome(
              exhibitors: [
                {'id': 'one', 'first_name': 'Alex', 'last_name': 'Example'},
              ],
              initialExhibitorId: 'one',
            ),
          ),
        ),
      );
      expect(find.text('Welcome, Alex Example'), findsOneWidget);
      expect(find.text('Exhibitor number not assigned'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
    },
  );
}
