import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/final_award_judge_reader.dart';

void main() {
  final legacy = {
    'id': 'legacy',
    'kind': 'open',
    'letter': 'D',
    'display_name': 'ACBA Open Show A',
    'is_enabled': false,
    'judging_date': '2026-10-31',
  };
  final current = {
    'id': 'current',
    'kind': 'open',
    'letter': 'A',
    'display_name': 'ARBA Open Show A',
    'is_enabled': true,
    'judging_date': '2026-10-31',
  };
  test(
    'legacy cavy finals follow their named show letter, not their physical D/E letter',
    () {
      expect(legacyCavyFinalsSections([legacy, current], {'current'}), {
        'legacy': 'current',
      });
    },
  );
  for (final change in [
    {'kind': 'youth'},
    {'letter': 'B'},
    {'judging_date': '2026-11-01'},
  ]) {
    test(
      'legacy cavy finals never cross a different scope, letter, or date: $change',
      () {
        expect(
          legacyCavyFinalsSections(
            [
              legacy,
              {...current, ...change},
            ],
            {'current'},
          ),
          isEmpty,
        );
      },
    );
  }
  test(
    'active or vaguely named sections are not treated as legacy aliases',
    () {
      expect(
        legacyCavyFinalsSections(
          [
            {...legacy, 'is_enabled': true},
            current,
          ],
          {'current'},
        ),
        isEmpty,
      );
      expect(
        legacyCavyFinalsSections(
          [
            {...legacy, 'display_name': 'Other cavy show'},
            current,
          ],
          {'current'},
        ),
        isEmpty,
      );
    },
  );
  test('ambiguous legacy finals fail rather than guessing', () {
    expect(
      () => legacyCavyFinalsSections(
        [
          legacy,
          {...legacy, 'id': 'duplicate'},
          current,
        ],
        {'current'},
      ),
      throwsStateError,
    );
  });
  final plan = {
    'award_section_id': 'youth-a',
    'award_code': 'FINALS',
    'table_number': '10',
    'sort_order': 4,
  };
  test(
    'no marker before finals does not borrow a later or other table judge',
    () {
      expect(
        resolveFinalAwardJudgeRefs(
          [plan],
          [
            {'table_number': '10', 'sort_order': 5, 'judge_id': 'later'},
            {'table_number': '1', 'sort_order': 0, 'judge_id': 'elsewhere'},
          ],
        ),
        {finalAwardJudgeKey('youth-a', 'FINALS'): ''},
      );
    },
  );
  test('unassigned current marker does not reuse the earlier judge', () {
    expect(
      resolveFinalAwardJudgeRefs(
        [plan],
        [
          {'table_number': '10', 'sort_order': 0, 'judge_id': 'old'},
          {'table_number': '10', 'sort_order': 3, 'judge_id': null},
        ],
      )[finalAwardJudgeKey('youth-a', 'FINALS')],
      '',
    );
  });
  test(
    'conflicting simultaneous judge changes cannot silently pick a judge',
    () {
      expect(
        () => resolveFinalAwardJudgeRefs(
          [plan],
          [
            {'table_number': '10', 'sort_order': 0, 'judge_id': 'one'},
            {'table_number': '10', 'sort_order': 0, 'judge_id': 'two'},
          ],
        ),
        throwsStateError,
      );
    },
  );
  test('conflicting duplicate plans cannot silently pick a judge', () {
    expect(
      () => resolveFinalAwardJudgeRefs(
        [
          plan,
          {...plan, 'table_number': '2'},
        ],
        [
          {'table_number': '10', 'sort_order': 0, 'judge_id': 'one'},
          {'table_number': '2', 'sort_order': 0, 'judge_id': 'two'},
        ],
      ),
      throwsStateError,
    );
  });
  test('BIS and combined finals plans retain distinct assignment keys', () {
    final refs = resolveFinalAwardJudgeRefs(
      [
        plan,
        {...plan, 'award_code': 'BIS', 'table_number': '2'},
      ],
      [
        {'table_number': '10', 'sort_order': 0, 'judge_id': 'one'},
        {'table_number': '2', 'sort_order': 0, 'judge_id': 'two'},
      ],
    );
    expect(refs[finalAwardJudgeKey('youth-a', 'FINALS')], 'one');
    expect(refs[finalAwardJudgeKey('youth-a', 'BIS')], 'two');
  });
}
