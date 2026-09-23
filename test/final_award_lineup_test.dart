import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/superintendent/final_award_lineup.dart';
import 'package:ringmaster_show/superintendent/specialty_lineup_dialog.dart';

void main() {
  test('four six BIS requires three separate decisions', () {
    expect(finalAwardPlanningOptions('four_six_bis'), {
      'BEST4': 'Best 4',
      'BEST6': 'Best 6',
      'BIS': 'BIS',
    });
  });
  test('reserve formats require only one decision per section', () {
    for (final mode in ['bis_ris', 'bis_1ris_2ris', 'bis_1ris_2ris_bbos']) {
      expect(finalAwardPlanningOptions(mode).keys, ['FINALS']);
    }
    expect(finalAwardPlanningOptions('unknown'), isEmpty);
  });
  test('award rows remain distinct from outside specialties', () {
    final row = specialtyLineupRow({
      'award_code': 'BIS',
      'award_section_id': 's',
      'name': 'Show',
      'breed': 'BIS',
      'scope': 'open',
      'entry_count': 0,
    });
    expect(row['is_award_plan'], true);
    expect(row['is_external_specialty'], false);
    expect(row['section_id'], 's');
    expect(row['breed_id'], 'BIS');
  });
}
