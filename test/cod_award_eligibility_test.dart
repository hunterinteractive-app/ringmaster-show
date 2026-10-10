import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/cod_eligibility.dart';
import 'package:ringmaster_show/services/results/rabbit_results_rules.dart';
import 'package:ringmaster_show/services/results/rabbit_results_validation.dart';

Map<String, dynamic> rabbit(
  String id,
  String variety,
  String sex, {
  String breed = 'Silver Fox',
  List<String> awards = const [],
  String? placement = '1',
}) => {
  'id': id,
  'species': 'rabbit',
  'section_id': 'youth-b',
  'breed': breed,
  'variety': variety,
  'sex': sex,
  'placement': placement,
  '_awards': awards,
};

void main() {
  const rules = RabbitResultsRules();
  List<dynamic> validate(List<Map<String, dynamic>> entries) =>
      validateRabbitResults(
        entries: entries,
        requireVarietyAwards: true,
        requireGroupAwards: true,
        requireBreedAwards: true,
        hasBasicOutcome: (e) => e['placement'] != null,
        isEligibleForSpecialAward: (e) => e['placement'] == '1',
        isExcludedFromSpecials: (_) => false,
        awardCodes: (e) => List<String>.from(e['_awards'] as List),
        entryLabel: (e) => e['id'] as String,
        sectionId: (e) => e['section_id'] as String,
        breed: (e) => e['breed'] as String,
        variety: (e) => e['variety'] as String,
        group: (_) => '',
        sex: (e) => e['sex'] as String,
      );
  test('recognizes whole COD marker in either breed or variety', () {
    for (final name in ['Blue (COD)', 'COD Blue', 'blue (cod)']) {
      expect(isCodEntry(rabbit('cod', name, 'Doe')), isTrue);
    }
    expect(
      isCodEntry(rabbit('cod', 'Solid', 'Doe', breed: 'Velveteen Lop (COD)')),
      isTrue,
    );
    expect(isCodEntry(rabbit('ordinary', 'Chocolate', 'Doe')), isFalse);
    expect(isCodEntry({'breed_name': 'COD Breed'}), isTrue);
    expect(isCodEntry({'breed': 'Codsworth'}), isFalse);
    expect(isCodEntry({'notes': 'COD', 'tattoo': 'COD'}), isFalse);
  });
  test('COD cannot receive any higher award even when first place', () {
    final entry = rabbit('cod', 'Blue (COD)', 'Doe');
    for (final award in [
      'BOV',
      'BOSV',
      'BOG',
      'BOSG',
      'BOB',
      'BOSB',
      'Best 4-Class',
      'Best 6-Class',
      'Best In Show',
      'Reserve In Show',
      '1RIS',
      '2RIS',
      'BBOS',
    ]) {
      expect(
        rules.canUseAward(
          entry: entry,
          award: award,
          selectedAwards: {'BOB', 'BOV', 'BOG', 'BOSB', 'Best 4-Class'},
          effectiveStatus: 'Shown',
          effectivePlacement: '1',
          classSystem: 'six',
          finalAwardMode: 'bis_1ris_2ris_bbos',
        ),
        isFalse,
        reason: award,
      );
      expect(
        rules
            .validateAwardSelection(entry: entry, selectedAwards: {award})
            .valid,
        isFalse,
      );
    }
    expect(
      rules.validateAwardSelection(entry: entry, selectedAwards: {}).valid,
      isTrue,
    );
  });
  test(
    'Youth B Silver Fox does not require BOS for only a COD opposite sex',
    () {
      final black = rabbit('black', 'Black', 'Buck', awards: ['BOV', 'BOB']);
      final blue = rabbit('blue', 'Blue (COD)', 'Doe');
      expect(validate([black, blue]), isEmpty);
      final recognizedDoe = rabbit('doe', 'Black', 'Doe');
      expect(
        validate([black, blue, recognizedDoe]).map((i) => i.code),
        contains('missing_bosb'),
      );
    },
  );
  test('COD-only results still require class placements but no specials', () {
    expect(validate([rabbit('cod', 'Blue (COD)', 'Doe')]), isEmpty);
    expect(
      validate([
        rabbit('cod', 'Blue (COD)', 'Doe', placement: null),
      ]).single.code,
      'missing_basic_outcome',
    );
  });
  test('existing incorrect COD awards are flagged for correction', () {
    expect(
      validate([
        rabbit('cod', 'Blue (COD)', 'Doe', awards: ['BOSB']),
      ]).single.code,
      'cod_special_award',
    );
  });
}
