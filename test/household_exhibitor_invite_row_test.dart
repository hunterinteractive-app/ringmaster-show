import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/household_exhibitor_invite_row.dart';

void main() {
  testWidgets('shows the showing name and saves the edited email', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 650,
            child: HouseholdExhibitorInviteRow(
              exhibitor: const {
                'id': '1',
                'showing_name': 'Example Rabbitry',
                'display_name': 'Alex Example',
                'type': 'adult',
                'email': 'old@example.com',
              },
              enabled: true,
              onSave: (email) async {
                saved = email;
                return 'Saved';
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('Example Rabbitry'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' NEW@example.com ');
    await tester.tap(find.text('Save and Send'));
    await tester.pumpAndSettle();
    expect(saved, 'new@example.com');
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow layout displays ineligible youth without a send action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: HouseholdExhibitorInviteRow(
              exhibitor: const {
                'id': '2',
                'showing_name': 'Youth Exhibitor',
                'type': 'youth',
              },
              enabled: true,
              onSave: (_) async => throw StateError('Must not send'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Youth Exhibitor'), findsOneWidget);
    expect(find.text('Save and Send'), findsNothing);
    expect(find.textContaining('must be 14 or older'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
