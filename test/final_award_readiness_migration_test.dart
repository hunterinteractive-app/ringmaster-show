import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/'
    '20260906142025_restore_all_final_award_readiness_modes.sql',
  ).readAsStringSync();

  test('closeout readiness installs every supported final-award mode', () {
    expect(migration, contains("ss.final_award_mode = 'four_six_bis'"));
    expect(migration, contains("ss.final_award_mode = 'bis_ris'"));
    expect(migration, contains("ss.final_award_mode = 'bis_1ris_2ris'"));
  });

  test('four/six mode requires its class winners and best in show', () {
    expect(
      migration,
      contains("'B4C'::text as award_kind, 'Best 4-Class'::text"),
    );
    expect(migration, contains("'B6C', 'Best 6-Class', 2, true"));
    expect(migration, contains("'BIS', 'Best in Show', 3, true"));
    expect(migration, contains("qualifier.award_kind in ('B4C', 'B6C')"));
  });

  test('BIS/RIS mode requires both awards when multiple breeds compete', () {
    expect(migration, contains("'BIS', 'Best in Show', 1, true"));
    expect(migration, contains("'RIS', 'Reserve in Show', 2, true"));
    expect(migration, contains(') > 1'));
  });

  test('legacy reserve mode keeps second reserve non-blocking', () {
    expect(migration, contains("('2RIS', 'Second Reserve in Show', 3, false)"));
  });

  test('placement zero and invoker security remain intact', () {
    expect(migration, contains("placement is not null and placement <> '0'"));
    expect(migration, contains('security invoker'));
    expect(
      migration,
      contains(
        'revoke all on function public.show_results_readiness_scoped'
        '(uuid, uuid[]) from public, anon',
      ),
    );
  });
}
