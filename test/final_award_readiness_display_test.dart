import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/final_award_readiness.dart';

void main() {
  test('turns missing and invalid final awards into actionable messages', () {
    final issues = blockingFinalAwardReadinessIssues({
      'missing_final_award_count': 1,
      'missing_final_awards': [
        {
          'section_label': 'Open B Saturday',
          'award_code': 'BIS',
          'award_label': 'Best in Show',
        },
      ],
      'invalid_final_award_count': 1,
      'invalid_final_awards': [
        {
          'section_label': 'Open B Saturday',
          'award_label': 'Best 6-Class',
          'reason': 'Best 6-Class must come from a six-class BOB winner.',
        },
      ],
      'duplicate_final_award_count': 1,
      'suggested_final_award_count': 1,
    });

    expect(issues, hasLength(3));
    expect(issues[0].title, 'Missing Best in Show');
    expect(issues[0].message, contains('Open B Saturday'));
    expect(issues[1].title, 'Invalid Best 6-Class');
    expect(issues[1].message, contains('six-class BOB winner'));
    expect(issues[2].title, 'Duplicate final award winners');
  });

  test('falls back to counts when an older response omits details', () {
    final issues = blockingFinalAwardReadinessIssues({
      'missing_final_award_count': 2,
      'invalid_final_award_count': 1,
    });

    expect(issues, hasLength(2));
    expect(issues[0].message, contains('2 required final awards'));
    expect(issues[1].message, contains('1 final award selection'));
  });

  test('Results Entry scopes the canonical validator to selected section', () {
    final source = File(
      'lib/screens/admin/results/admin_results_entry_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'show_results_readiness_scoped'"));
    expect(source, contains("'p_section_ids': [sectionId]"));
    expect(source, contains('blockingFinalAwardReadinessIssues'));
  });
}
