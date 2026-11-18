import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/class_population.dart';

void main() {
  for (final reason in ['Overweight', 'Weight', 'Wrong Tattoo', 'Other']) {
    test('$reason DQ still contributes to class population', () {
      expect(
        countsTowardClassPopulation({
          'is_shown': true,
          'is_disqualified': true,
          'result_status': 'Disqualified - $reason',
        }),
        isTrue,
      );
    });
  }
  for (final reason in ['Wrong Sex', 'Wrong Variety', 'Wrong Class']) {
    for (final field in ['result_status', 'disqualified_reason']) {
      test('$reason in $field is excluded from class population', () {
        expect(countsTowardClassPopulation({field: reason}), isFalse);
      });
    }
  }
  for (final status in [
    'No Show',
    'no_show',
    'no-show',
    'noshow',
    'Scratched',
  ]) {
    test('$status is excluded', () {
      expect(countsTowardClassPopulation({'result_status': status}), isFalse);
    });
  }
  test('shown and unworthy count; scratch and not shown do not', () {
    expect(countsTowardClassPopulation({'result_status': 'Shown'}), isTrue);
    expect(
      countsTowardClassPopulation({'result_status': 'Unworthy of Award'}),
      isTrue,
    );
    expect(countsTowardClassPopulation({'is_shown': false}), isFalse);
    expect(
      countsTowardClassPopulation({'scratched_at': '2026-11-17'}),
      isFalse,
    );
  });
}
