import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/results_readiness.dart';

void main() {
  test('parses missing final awards in database display order', () {
    final readiness = ResultsReadinessDto.fromJson({
      'ready': false,
      'missing_placement_count': 0,
      'missing_judge_count': 0,
      'duplicate_placement_group_count': 0,
      'missing_final_award_count': 2,
      'duplicate_final_award_count': 0,
      'missing_final_awards': [
        {
          'section_id': 'open-a',
          'section_label': 'Open A',
          'award_code': '1RIS',
          'award_label': 'First Reserve in Show',
        },
        {
          'section_id': 'open-b',
          'section_label': 'Open B',
          'award_code': 'BIS',
          'award_label': 'Best in Show',
        },
      ],
      'suggested_final_award_count': 1,
      'suggested_final_awards': [
        {
          'section_id': 'open-c',
          'section_label': 'Open C',
          'award_code': '2RIS',
          'award_label': 'Second Reserve in Show',
        },
      ],
    });

    expect(readiness.missingFinalAwardCount, 2);
    expect(
      readiness.missingFinalAwards.map(
        (item) => '${item.sectionLabel}: ${item.awardLabel}',
      ),
      ['Open A: First Reserve in Show', 'Open B: Best in Show'],
    );
    expect(readiness.suggestedFinalAwardCount, 1);
    expect(readiness.suggestedFinalAwards.single.awardCode, '2RIS');
  });

  test('older readiness responses remain compatible', () {
    final readiness = ResultsReadinessDto.fromJson({
      'ready': false,
      'missing_final_award_count': 1,
    });

    expect(readiness.missingFinalAwardCount, 1);
    expect(readiness.missingFinalAwards, isEmpty);
    expect(readiness.suggestedFinalAwardCount, 0);
    expect(readiness.suggestedFinalAwards, isEmpty);
  });

  test('migration keeps count and detail rows on the same award matrix', () {
    final migration = File(
      'supabase/migrations/'
      '20260722203058_make_second_reserve_suggested.sql',
    ).readAsStringSync();

    expect(migration, contains("('BIS', 'Best in Show', 1, true)"));
    expect(migration, contains("('1RIS', 'First Reserve in Show', 2, true)"));
    expect(migration, contains("('2RIS', 'Second Reserve in Show', 3, false)"));
    expect(migration, contains("'missing_final_awards', missing_final_awards"));
    expect(
      migration,
      contains("'suggested_final_awards', suggested_final_awards"),
    );
    expect(migration, contains('and required_for_readiness'));
    expect(
      migration,
      contains(
        'create or replace function public.show_results_readiness_scoped',
      ),
    );
  });
}
