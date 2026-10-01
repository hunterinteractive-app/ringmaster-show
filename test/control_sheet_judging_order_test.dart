import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/print_packs/control_sheet_judging_order.dart';

void main() {
  Map<String, dynamic> assignment(
    String breed,
    String table,
    int position, {
    String section = 'A',
    String variety = '',
  }) => {
    'id': '$section-$breed-$variety',
    'breed_id': breed,
    'section_id': section,
    'species': 'rabbit',
    'judge_id': 'judge',
    'table_number': table,
    'sort_order': position,
    'variety_key': variety,
  };
  Map<String, dynamic> page(
    String breed, {
    String section = 'A',
    String color = '',
  }) => {
    'breed': breed,
    'sectionId': section,
    'species': 'rabbit',
    'color': color,
  };
  test('empty and judge-only lineups do not enable print order', () {
    expect(ControlSheetJudgingOrder([]).isAvailable, isFalse);
    expect(
      ControlSheetJudgingOrder([
        assignment('__judge_change__', '1', 0),
      ]).isAvailable,
      isFalse,
    );
  });
  test(
    'orders numerically by table then saved sequence, retains unassigned last',
    () {
      final order = ControlSheetJudgingOrder([
        assignment('Rex', '10', 0),
        assignment('Dutch', '2', 8),
        assignment('Mini Satin', '2', 1),
      ]);
      final pages = [
        page('Rex'),
        page('Unassigned'),
        page('Dutch'),
        page('Mini Satin'),
      ]..sort((a, b) => order.rank(a).compareTo(order.rank(b)));
      expect(pages.map((p) => p['breed']), [
        'Mini Satin',
        'Dutch',
        'Rex',
        'Unassigned',
      ]);
    },
  );
  test('respects section and split variety assignments and ignores case', () {
    final order = ControlSheetJudgingOrder([
      assignment('Mini Satin', '1', 1, variety: 'Blue'),
      assignment('Mini Satin', '1', 2, variety: 'Black'),
      assignment('Mini Satin', '1', 0, section: 'B'),
    ]);
    expect(order.rank(page('Mini Satin', section: 'B')), 0);
    expect(order.rank(page('mini satin', color: ' blue ')), 1);
    expect(order.rank(page('Mini Satin', color: 'Black')), 2);
    expect(order.rank(page('Mini Satin', section: 'C')), 3);
  });
}
