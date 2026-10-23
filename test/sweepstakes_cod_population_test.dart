import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart';

void main() {
  test('COD class results remain visible but do not inflate breed totals', () {
    final rows = [
      {
        'breed_name': 'English Angora',
        'variety_name': 'Colored',
        'placement': '1',
      },
      {
        'breed_name': 'English Angora',
        'variety_name': 'White',
        'placement': '1',
      },
      {
        'breed_name': 'English Angora',
        'variety_name': 'Broken (COD)',
        'placement': '1',
      },
      {
        'breed_name': 'Velveteen Lop (COD)',
        'variety_name': 'Solid',
        'placement': '1',
      },
    ];
    expect(rows.where(breedResultsDetailIsCountableJudgedEntry).length, 4);
    expect(rows.where(breedResultsDetailIsSweepstakesCountable).length, 2);
    expect(rows.last['placement'], '1');
  });
  test('scratches, no-shows, and disqualifications stay excluded', () {
    for (final exclusion in [
      {'scratched_at': '2026-10-23'},
      {'is_shown': false},
      {'is_disqualified': true},
    ]) {
      expect(
        breedResultsDetailIsSweepstakesCountable({
          'breed_name': 'Satin Angora',
          'variety_name': 'Colored',
          ...exclusion,
        }),
        isFalse,
      );
    }
  });
  test('historical Broken grouping and placement are not merged', () {
    final row = {
      'breed_name': 'Satin Angora',
      'variety_name': 'Broken',
      'placement': '1',
    };
    expect(
      breedResultsDetailTopSectionName(row, groupByBreed: false),
      'Broken',
    );
    expect(breedResultsDetailIsSweepstakesCountable(row), isTrue);
    expect(row['placement'], '1');
  });
}
