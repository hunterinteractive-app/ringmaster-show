import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/details_by_breed_report_loader.dart';

void main() {
  test('details by breed treats first reserve as standard RIS', () {
    expect(
      normalizeDetailsByBreedAwardCodes([
        '1RIS',
        '1st RIS',
        'First Reserve in Show',
      ]),
      {'RIS'},
    );
  });

  test('details by breed omits second reserve recognition', () {
    expect(
      normalizeDetailsByBreedAwardCodes([
        'BIS',
        '2RIS',
        '2nd RIS',
        'Second Reserve in Show',
      ]),
      {'BIS'},
    );
  });

  test('cavy sweepstakes migration maps 1RIS and ignores 2RIS', () {
    final migration = File(
      'supabase/migrations/'
      '20260722202518_normalize_first_reserve_for_cavy_reports.sql',
    ).readAsStringSync();

    expect(migration, contains("when '1RIS' then 'RIS'"));
    expect(migration, contains("when 'FIRST RESERVE IN SHOW' then 'RIS'"));
    expect(migration, contains("when '2RIS' then null"));
    expect(migration, contains('where n.award_code is not null'));
  });
}
