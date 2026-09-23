import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/superintendent/specialty_lineup_dialog.dart';

void main() {
  testWidgets('specialty requires name breed count and table before saving', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editSpecialtyLineup(
                context,
                save: (value) async {
                  saved = value;
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save specialty'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('Required'), findsNWidgets(4));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'IDDRC');
    await tester.enterText(fields.at(1), 'Dutch');
    expect(find.text('Judge name (optional)'), findsNothing);
    expect(find.text('Order at table (0 = first)'), findsNothing);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>).first);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Youth').last);
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(2), '45');
    await tester.enterText(fields.at(3), '3');
    await tester.tap(find.text('Save specialty'));
    await tester.pumpAndSettle();
    expect(saved?['entry_count'], 45);
    expect(saved?['scope'], 'youth');
    expect(saved?.containsKey('sort_order'), isFalse);
    expect(saved?['name'], 'IDDRC');
    expect(saved?['table_number'], '3');
    expect(saved?.containsKey('show_id'), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
  });
  test('specialty adapter keeps manual counts and label separate', () {
    final row = specialtyLineupRow({
      'id': 's',
      'name': 'IDDRC',
      'breed': 'Dutch',
      'entry_count': 45,
      'status': 'completed',
    });
    expect(row['is_external_specialty'], true);
    expect(row['breed_id'], 'IDDRC • Dutch');
    expect(row['entry_count_actual'], 45);
    expect(row['section_id'], isNull);
    expect(specialtyStatus(row['status']), 'Complete');
  });
}
