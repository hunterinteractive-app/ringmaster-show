import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/print_packs/control_sheet_labels.dart';

void main() {
  test('variety totals share a key across capitalization and spacing', () {
    expect(controlSheetCountLabel('otter'), controlSheetCountLabel('Otter'));
    expect(
      controlSheetCountLabel(' BLACK  Otter '),
      controlSheetCountLabel('Black Otter'),
    );
    expect(
      controlSheetCountLabel('Black'),
      isNot(controlSheetCountLabel('Otter')),
    );
  });
  test('assigned cavy judge does not label unassigned rabbit classes', () {
    expect(controlSheetJudgeLabel(['Cavy Judge', '', '']), '');
    expect(controlSheetJudgeLabel(['', '']), '');
    expect(controlSheetJudgeLabel([]), '');
    expect(controlSheetJudgeLabel(['Cathy', 'Cathy']), 'Cathy');
    expect(controlSheetJudgeLabel(['Cathy', 'Another Judge']), '');
    expect(controlSheetJudgeLabel(['Cathy', ' ']), '');
  });
  test('white and colored fur produce separate grouping labels', () {
    final rows = [
      {'variety': 'White', 'class_name': 'Fur / Wool'},
      {'variety': 'Colored', 'class_name': 'Fur / Wool'},
      {'variety': 'Black', 'fur_variety': 'White'},
      {'variety': 'coloured', 'class_name': 'Senior'},
    ];
    final groups = <String, int>{};
    for (final row in rows) {
      final label = controlSheetFurColor(row);
      groups.update(label, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(groups, {'White': 2, 'Colored': 2});
    expect(controlSheetFurColor({'variety': 'Fur / Wool'}), '');
    expect(controlSheetFurColor({}), '');
  });
}
