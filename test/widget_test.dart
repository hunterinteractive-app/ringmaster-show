import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/rm_widgets.dart';

void main() {
  testWidgets(
    'report card displays its content and opens the selected report',
    (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RMCard(
              onTap: () => opens++,
              child: const RMSectionHeader(
                title: 'Exhibitor reports',
                subtitle: '2,528 exhibitors',
              ),
            ),
          ),
        ),
      );
      expect(find.text('2,528 exhibitors'), findsOneWidget);
      await tester.tap(find.text('Exhibitor reports'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
