import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/class_payback.dart';

void main() {
  // Independent expected amounts indexed by class size; blank places pay zero.
  final open = <List<int>>[
    [],
    [2],
    [4, 2],
    [4, 2],
    [6, 4, 2],
    [6, 4, 2],
    [8, 6, 4, 2],
    [8, 6, 4, 2],
    [10, 8, 6, 4, 2],
  ];
  final youthRabbit = <List<int>>[
    [10],
    [10],
    [10],
    [12, 11, 10],
    [12, 11, 10],
    [14, 13, 12, 11],
    [14, 13, 12, 11],
    [15, 14, 13, 12, 11],
    [15, 14, 13, 12, 11],
    for (var n = 10; n <= 14; n++) [18, 16, 15, 14, 13],
    [23, 21, 20, 19, 18],
  ];
  final youthCavy = <List<int>>[
    [10],
    [10],
    [10],
    [12, 11],
    [12, 11],
    [14, 13, 12],
    [14, 13, 12],
    [15, 14, 13, 12],
    [15, 14, 13, 12],
    [18, 16, 15, 14, 13],
  ];
  for (final preset in HoustonPaybackPreset.values) {
    test('${preset.label}: every size 1–50 and placement 1–6', () {
      final expected = preset.kind == 'open'
          ? open
          : preset.species == 'rabbit'
          ? youthRabbit
          : youthCavy;
      final rows = preset.rows();
      expect(validateClassPaybackRanges(rows), isNull);
      final rpc = rows.expand((r) => r.toRpcRows()).toList();
      for (var n = 1; n <= 50; n++) {
        final amounts =
            expected[n <= expected.length ? n - 1 : expected.length - 1];
        for (var place = 1; place <= 6; place++) {
          final matches = rpc.where(
            (r) =>
                n >= r['min_shown'] &&
                (r['max_shown'] == null || n <= r['max_shown']) &&
                r['placement'] == place,
          );
          final cents = place <= amounts.length ? amounts[place - 1] * 100 : 0;
          expect(
            matches.length,
            cents == 0 ? 0 : 1,
            reason: '$n shown / $place place',
          );
          if (cents > 0) expect(matches.single['amount_cents'], cents);
        }
      }
    });
  }
  ClassPaybackRow row(int min, int? max, {String species = 'rabbit'}) =>
      ClassPaybackRow(
        appliesToSpecies: species,
        minShown: min,
        maxShown: max,
        amountsByPlacement: {1: 200},
      );
  test(
    'inclusive overlap and duplicate/open-ended ranges rejected; species and gaps allowed',
    () {
      expect(
        validateClassPaybackRanges([row(2, 4), row(4, 6)]),
        contains('overlap'),
      );
      expect(
        validateClassPaybackRanges([row(2, 4), row(2, 4)]),
        contains('overlap'),
      );
      expect(
        validateClassPaybackRanges([row(9, null), row(15, null)]),
        contains('overlap'),
      );
      expect(validateClassPaybackRanges([row(2, 4), row(5, null)]), isNull);
      expect(validateClassPaybackRanges([row(2, 4), row(8, null)]), isNull);
      expect(
        validateClassPaybackRanges([row(2, 4), row(2, 4, species: 'cavy')]),
        isNull,
      );
      expect(validateClassPaybackRanges([row(0, 1)]), isNotNull);
      expect(validateClassPaybackRanges([row(4, 2)]), isNotNull);
    },
  );
  test('invalid premium text cannot silently turn into zero', () {
    for (final v in ['-1', '1.001', 'abc', 'NaN', 'Infinity', '21474836.48']) {
      expect(validatePremiumAmount(v), isNotNull, reason: v);
    }
    for (final v in ['', '0', '12', '12.50', r'$12.50']) {
      expect(validatePremiumAmount(v), isNull, reason: v);
    }
    final r = row(2, 2)..amountErrors[1] = 'Invalid amount';
    expect(validateClassPaybackRanges([r.copy()]), 'Invalid amount');
    expect(
      validateClassPaybackRanges([row(2, 2)..amountsByPlacement[3] = 100]),
      isNotNull,
    );
  });
}
