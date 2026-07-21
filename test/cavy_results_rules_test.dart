import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/cavy_results_rules.dart';
import 'package:ringmaster_show/services/results/cavy_results_validation.dart';

void main() {
  const rules = CavyResultsRules();

  Map<String, dynamic> cavy({
    String id = 'cavy-1',
    String variety = 'Black',
    String sex = 'Boar',
    String className = 'Senior',
    List<String> awards = const [],
  }) => {
    'id': id,
    'entry_id': id,
    'species': 'Cavy',
    'section_id': 'open-a',
    'breed_id': 'american',
    'breed': 'American',
    'variety': variety,
    'exact_variety_name': variety,
    'uses_variety_awards': true,
    'placement': '1',
    'result_status': 'Shown',
    'class_name': '$className $sex',
    'sex': sex,
    '_awards': awards,
  };

  test('historical cavy group awards normalize to variety awards', () {
    expect(rules.normalizeStoredAwards(['BOG', 'Best Opposite Sex of Group']), {
      'BOV',
      'BOSV',
    });
  });

  test('cavy results use variety cards instead of group cards', () {
    final entries = [
      cavy(id: 'black', variety: 'Black'),
      cavy(id: 'cream', variety: 'Cream'),
    ];
    expect(rules.usesGroupLayer(entries.first), isFalse);
    expect(rules.usesVarietyLayer(entries.first), isTrue);
    expect(rules.buildGroupGroups(entries), isEmpty);
    expect(
      rules.buildVarietyGroups(entries).map((group) => group.displayName),
      containsAll(['Black', 'Cream']),
    );
  });

  test('senior cavy options expose variety and breed age winners', () {
    final options = rules.buildAwardOptions(
      entry: cavy(),
      classSystem: 'six',
      finalAwardMode: 'bis_ris',
    );
    expect(options, containsAll(['BSV', 'BSB', 'BOV', 'BOSV', 'BOB', 'BOSB']));
    expect(options, isNot(contains('BOG')));
    expect(options, isNot(contains('BOSG')));
  });

  test('breed age winner requires corresponding variety age winner', () {
    expect(
      rules.canUseAward(
        entry: cavy(),
        award: 'BSB',
        selectedAwards: const {},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'six',
        finalAwardMode: 'bis_ris',
      ),
      isFalse,
    );
    expect(
      rules.canUseAward(
        entry: cavy(),
        award: 'BSB',
        selectedAwards: const {'BSV'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'six',
        finalAwardMode: 'bis_ris',
      ),
      isTrue,
    );
  });

  test('validation requires age winners at variety and breed levels', () {
    final rows = [
      cavy(id: 'black-sr', awards: const ['BSV', 'BSB', 'BOV', 'BOB']),
      cavy(
        id: 'black-int',
        className: 'Intermediate',
        sex: 'Sow',
        awards: const ['BIV', 'BIB', 'BOSV', 'BOSB'],
      ),
      cavy(id: 'black-jr', className: 'Junior', awards: const ['BJV', 'BJB']),
    ];
    final issues = validateCavyResults(
      entries: rows,
      requireVarietyAwards: true,
      requireBreedAwards: true,
      hasBasicOutcome: (_) => true,
      isEligibleForSpecialAward: (_) => true,
      isExcludedFromSpecials: (_) => false,
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      entryLabel: (entry) => entry['id'].toString(),
      sectionId: (entry) => entry['section_id'].toString(),
      breed: (entry) => entry['breed_id'].toString(),
      variety: (entry) => entry['variety'].toString(),
      className: (entry) => entry['class_name'].toString(),
      sex: (entry) => entry['sex'].toString(),
    );
    expect(issues, isEmpty);
  });

  test('validation flags duplicate BOV within the same variety', () {
    final rows = [
      cavy(
        id: 'tattoo-190',
        variety: 'Any Other Marked',
        className: 'Intermediate',
        awards: const ['BOV'],
      ),
      cavy(
        id: 'tattoo-045',
        variety: 'Any Other Marked',
        sex: 'Sow',
        awards: const ['BOV'],
      ),
    ];
    final issues = validateCavyResults(
      entries: rows,
      requireVarietyAwards: true,
      requireBreedAwards: false,
      hasBasicOutcome: (_) => true,
      isEligibleForSpecialAward: (_) => true,
      isExcludedFromSpecials: (_) => false,
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      entryLabel: (entry) => entry['id'].toString(),
      sectionId: (entry) => entry['section_id'].toString(),
      breed: (entry) => entry['breed_id'].toString(),
      variety: (entry) => entry['variety'].toString(),
      className: (entry) => entry['class_name'].toString(),
      sex: (entry) => entry['sex'].toString(),
    );

    final duplicate = issues.singleWhere(
      (issue) => issue.code == 'duplicate_bov',
    );
    expect(duplicate.message, contains('tattoo-190'));
    expect(duplicate.message, contains('tattoo-045'));
  });

  test('validation flags every missing age winner at both levels', () {
    final rows = [
      cavy(id: 'black-sr', awards: const ['BOV', 'BOB']),
      cavy(
        id: 'black-int',
        className: 'Intermediate',
        sex: 'Sow',
        awards: const ['BOSV', 'BOSB'],
      ),
      cavy(id: 'black-jr', className: 'Junior'),
    ];
    final issues = validateCavyResults(
      entries: rows,
      requireVarietyAwards: true,
      requireBreedAwards: true,
      hasBasicOutcome: (_) => true,
      isEligibleForSpecialAward: (_) => true,
      isExcludedFromSpecials: (_) => false,
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      entryLabel: (entry) => entry['id'].toString(),
      sectionId: (entry) => entry['section_id'].toString(),
      breed: (entry) => entry['breed_id'].toString(),
      variety: (entry) => entry['variety'].toString(),
      className: (entry) => entry['class_name'].toString(),
      sex: (entry) => entry['sex'].toString(),
    );

    expect(
      issues.map((issue) => issue.code),
      containsAll(<String>[
        'missing_bjv',
        'missing_biv',
        'missing_bsv',
        'missing_bjb',
        'missing_bib',
        'missing_bsb',
      ]),
    );
  });
}
