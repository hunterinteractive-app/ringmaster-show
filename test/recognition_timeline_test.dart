import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/catalog/recognition_timeline.dart';
import 'package:ringmaster_show/services/results/cod_eligibility.dart';
import 'package:ringmaster_show/services/results/rabbit_results_rules.dart';

void main() {
  final changes = [
    RecognitionTransition(
      id: '1',
      varietyName: 'Brindle (COD)',
      status: RecognitionStatus.cod,
      effectiveDate: DateTime(2026, 1, 1),
    ),
    RecognitionTransition(
      id: '2',
      varietyName: 'Brindle (COD)',
      status: RecognitionStatus.recognized,
      effectiveDate: DateTime(2026, 12, 1),
    ),
    RecognitionTransition(
      id: '3',
      varietyName: 'Brindle (COD)',
      status: RecognitionStatus.retired,
      effectiveDate: DateTime(2028, 1, 1),
    ),
  ];
  RecognitionStatus resolve(
    DateTime? date, {
    String variety = 'Brindle (COD)',
    List<RecognitionTransition>? events,
  }) => resolveRecognitionStatus(
    breedName: 'Mini Rex',
    varietyName: variety,
    judgingDate: date,
    transitions: events ?? changes,
  );
  test('each transition applies at its inclusive date boundary', () {
    expect(resolve(DateTime(2026, 11, 30)), RecognitionStatus.cod);
    expect(resolve(DateTime(2026, 12, 1)), RecognitionStatus.recognized);
    expect(resolve(DateTime(2027, 12, 31)), RecognitionStatus.recognized);
    expect(resolve(DateTime(2028, 1, 1)), RecognitionStatus.retired);
  });
  test(
    'canonical identity survives COD suffix and capitalization differences',
    () {
      expect(
        resolve(DateTime(2026, 11, 30), variety: 'brindle'),
        RecognitionStatus.cod,
      );
      expect(
        resolve(DateTime(2026, 12, 1), variety: ' BRINDLE (cod) '),
        RecognitionStatus.recognized,
      );
    },
  );
  test('unrelated variety retains recognized status', () {
    expect(
      resolve(DateTime(2026, 11, 30), variety: 'Black'),
      RecognitionStatus.recognized,
    );
  });
  test('missing judging date never unlocks configured recognition', () {
    expect(resolve(null), RecognitionStatus.unrecognized);
  });
  test('COD or retired breed overrides a recognized variety', () {
    for (final status in [RecognitionStatus.cod, RecognitionStatus.retired]) {
      expect(
        resolve(
          DateTime(2027),
          events: [
            ...changes,
            RecognitionTransition(
              id: 'breed',
              varietyName: '',
              status: status,
              effectiveDate: DateTime(2026),
            ),
          ],
        ),
        status,
      );
    }
  });
  test('dated recognition overrides old COD labels in awards and legs', () {
    final row = {
      'breed': 'Mini Rex',
      'variety': 'Brindle (COD)',
      'recognition_status': 'recognized',
    };
    expect(isCodEntry(row), false);
    expect(isRecognitionRestricted(row), false);
    expect(recognitionAwardsDisallowed(row, ['BOV', 'BOB', 'BIS']), false);
  });
  test('unmarked COD variety is still restricted by server status', () {
    final row = {
      'breed': 'Mini Rex',
      'variety': 'Brindle',
      'recognition_status': 'cod',
    };
    expect(isCodEntry(row), true);
    expect(recognitionAwardsDisallowed(row, ['BOV', 'BOSV']), false);
    expect(recognitionAwardsDisallowed(row, ['BOB']), true);
    expect(isRecognitionRestricted(row), true);
  });
  test('retirement blocks even variety awards', () {
    final row = {
      'breed': 'Mini Rex',
      'variety': 'Brindle',
      'recognition_status': 'retired',
    };
    expect(recognitionAwardsDisallowed(row, ['BOV']), true);
    expect(
      const RabbitResultsRules()
          .validateAwardSelection(entry: row, selectedAwards: {'BOV'})
          .valid,
      false,
    );
  });
  test('legacy COD behavior remains for unmigrated records', () {
    expect(isCodEntry({'variety': 'Blue (COD)'}), true);
    expect(isCodEntry({'breed': 'Codsworth'}), false);
  });
}
