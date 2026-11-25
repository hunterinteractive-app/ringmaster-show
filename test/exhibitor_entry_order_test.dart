import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/utils/exhibitor_entry_order.dart';

void main() {
  test(
    'rabbit stays together across changed class, tattoo and fur with A before B',
    () {
      final sections = <String, Map<String, dynamic>>{
        'a': {'kind': 'open', 'letter': 'A', 'sort_order': 99},
        'b': {'kind': 'open', 'letter': 'B', 'sort_order': 1},
        'y': {'kind': 'youth', 'letter': 'A'},
      };
      Map<String, dynamic> row(
        String id,
        String animal,
        String section, {
        bool fur = false,
      }) => {
        'id': id,
        'animal_id': animal,
        'section_id': section,
        'tattoo': animal,
        'breed': 'Havana',
        'class_name': 'Junior',
        'is_fur': fur,
      };
      final input = [
        row('r2b', 'R2', 'b'),
        row('r1b', 'R1', 'b'),
        row('r1af', 'R1', 'a', fur: true),
        row('r2a', 'R2', 'a'),
        {
          ...row('r1a', 'R1', 'a'),
          'class_name': 'Senior',
          'tattoo': 'CORRECTED',
        },
        row('r1y', 'R1', 'y'),
      ];
      final groups = groupExhibitorEntries(input, sections);
      expect(groups.length, 2);
      expect(groups.first.map((r) => r['id']), ['r1a', 'r1af', 'r1b', 'r1y']);
      expect(groups.last.map((r) => r['id']), ['r2a', 'r2b']);
      expect(input.first['id'], 'r2b');
    },
  );
  test('same tattoo on different animals or exhibitors never merges', () {
    final rows = [
      {'id': '1', 'tattoo': 'SAME', 'animal_id': 'one', 'exhibitor_id': 'x'},
      {'id': '2', 'tattoo': 'SAME', 'animal_id': 'two', 'exhibitor_id': 'x'},
      {'id': '3', 'tattoo': 'SAME', 'animal_id': 'one', 'exhibitor_id': 'y'},
      {'id': '4'},
      {'id': '5'},
    ];
    expect(groupExhibitorEntries(rows, {}).length, 5);
  });
}
