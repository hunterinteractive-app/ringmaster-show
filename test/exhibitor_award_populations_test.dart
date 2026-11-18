import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/exhibitor_award_populations.dart';

Map<String, dynamic> row(
  String id,
  String exhibitor, [
  Map<String, dynamic> overrides = const {},
]) => {
  'entry_id': id,
  'exhibitor_id': exhibitor,
  'section_id': 'open-a',
  'species': 'rabbit',
  'breed_name': 'Mini Rex',
  'variety_name': 'Black',
  'group_name': 'Self',
  'uses_group_awards': true,
  'sex': 'Buck',
  'class_name': 'Senior',
  'is_shown': true,
  ...overrides,
};

void main() {
  test(
    'special populations isolate section, breed, group, variety and sex',
    () {
      final winner = row('winner', 'one');
      final index = ExhibitorAwardPopulations([
        winner,
        row('two', 'one'),
        row('doe', 'two', {'sex': 'Doe'}),
        row('blue', 'three', {'variety_name': 'Blue'}),
        row('broken', 'four', {
          'variety_name': 'Broken',
          'group_name': 'Broken',
        }),
        row('other-breed', 'five', {'breed_name': 'Rex'}),
        row('youth', 'six', {'section_id': 'youth-a'}),
        row('cavy', 'seven', {'species': 'cavy'}),
        row('fur', 'eight', {'is_fur': true}),
        {...winner, 'is_fur': true},
        winner,
      ]);
      final counts = index.forEntry(winner, {
        'BOB',
        'BOG',
        'BOV',
        'BOSB',
        'BOSG',
        'BOSV',
        'UNRECOGNIZED',
      });
      expect([counts['BOB']!.animals, counts['BOB']!.exhibitors], [5, 4]);
      expect([counts['BOG']!.animals, counts['BOG']!.exhibitors], [4, 3]);
      expect([counts['BOV']!.animals, counts['BOV']!.exhibitors], [3, 2]);
      expect([counts['BOSB']!.animals, counts['BOSB']!.exhibitors], [4, 3]);
      expect([counts['BOSG']!.animals, counts['BOSG']!.exhibitors], [3, 2]);
      expect([counts['BOSV']!.animals, counts['BOSV']!.exhibitors], [2, 1]);
      expect(counts.containsKey('UNRECOGNIZED'), isFalse);
      final junior = row('junior', 'one', {'class_name': 'Junior'});
      final ages = ExhibitorAwardPopulations([
        junior,
        row('pre', 'two', {'class_name': 'Pre-Junior'}),
      ]);
      expect(ages.forEntry(junior, {'BJV'})['BJV']!.animals, 1);
    },
  );
  test(
    'shown DQs use their award scope and scratches/no shows are excluded',
    () {
      final winner = row('winner', 'one');
      final index = ExhibitorAwardPopulations([
        winner,
        row('weight', 'two', {'result_status': 'Disqualified - Overweight'}),
        row('class', 'three', {'disqualified_reason': 'Wrong Class'}),
        row('sex', 'four', {'disqualified_reason': 'Wrong Sex'}),
        row('variety', 'five', {'disqualified_reason': 'Wrong Variety'}),
        row('no-show', 'six', {'result_status': 'No Show'}),
        row('absent', 'seven', {'is_shown': false}),
        row('scratch', 'eight', {'scratched_at': '2026-11-17'}),
      ]);
      final counts = index.forEntry(winner, {'BOB', 'BOV', 'BSB', 'BSV'});
      expect(counts['BOB']!.animals, 4);
      expect(counts['BOV']!.animals, 3);
      expect(counts['BSB']!.animals, 3);
      expect(counts['BSV']!.animals, 2);
    },
  );
}
