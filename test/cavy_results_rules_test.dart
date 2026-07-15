import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/cavy_results_rules.dart';
import 'package:ringmaster_show/services/results/cavy_results_validation.dart';

void main() {
  const rules = CavyResultsRules();

  Map<String, dynamic> cavy({
    String id = 'cavy-1',
    String breed = 'American',
    String group = 'Black',
    String sex = 'Boar',
    List<String> awards = const [],
  }) => {
    'id': id,
    'entry_id': id,
    'species': 'Cavy',
    'section_id': 'cavy-open-a',
    'breed_id': breed.toLowerCase(),
    'breed': breed,
    'exact_variety_name': group,
    'variety': group,
    'uses_group_awards': true,
    'uses_variety_awards': true,
    'placement': '1',
    'result_status': 'Shown',
    'class_name': 'Senior $sex',
    'sex': sex,
    '_awards': awards,
  };

  for (final group in const ['Black', 'Cream', 'White']) {
    test('American $group resolves as an independent cavy group', () {
      final child = rules.childIdentity(cavy(group: group));
      expect(child.displayName, group);
      expect(child.stableKey, 'fallback:american:${group.toLowerCase()}');
    });
  }

  test('Teddy catalog group remains authoritative', () {
    final row = cavy(breed: 'Teddy', group: 'Teddy')
      ..['group_id'] = 'teddy-marked'
      ..['group_name'] = 'Marked';
    final child = rules.childIdentity(row);
    expect(child.displayName, 'Marked');
    expect(child.stableKey, 'explicit:teddy:teddy-marked');
  });

  test('American groups remain separate child cards', () {
    final groups = rules.buildChildGroups([
      cavy(id: 'black', group: 'Black'),
      cavy(id: 'cream', group: 'Cream'),
      cavy(id: 'white', group: 'White'),
    ]);
    expect(groups, hasLength(3));
    expect(groups.map((group) => group.displayName).toSet(), {
      'Black',
      'Cream',
      'White',
    });
  });

  test(
    'cavy normalizer preserves BOG/BOSG and stored awards reopen checked',
    () {
      expect(
        rules.normalizeStoredAwards(['bog', 'Best Opposite Sex of Group']),
        {'BOG', 'BOSG'},
      );
    },
  );

  test('cavy editor options show group awards and never variety awards', () {
    final options = rules.buildAwardOptions(
      entry: cavy(),
      classSystem: 'four',
      finalAwardMode: 'bis_ris',
    );
    expect(options, containsAll(['BOG', 'BOSG', 'BOB', 'BOSB', 'HM']));
    expect(options, isNot(contains('BOV')));
    expect(options, isNot(contains('BOSV')));
  });

  test('valid BOG/BOB selection is accepted for Save and Save & Next', () {
    final selected = rules.normalizeStoredAwards(['BOG', 'BOB']);
    final compatibility = rules.validateAwardSelection(
      entry: cavy(),
      selectedAwards: selected,
    );
    expect(compatibility.valid, isTrue);
    expect(
      rules.canUseAward(
        entry: cavy(),
        award: 'BOB',
        selectedAwards: selected,
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      ),
      isTrue,
    );
  });

  test('cavy BOB must come from BOG while BOSB may come from BOG/BOSG', () {
    expect(
      rules
          .validateAwardSelection(
            entry: cavy(),
            selectedAwards: {'BOSG', 'BOB'},
          )
          .valid,
      isFalse,
    );
    expect(
      rules
          .validateAwardSelection(
            entry: cavy(),
            selectedAwards: {'BOSG', 'BOSB'},
          )
          .valid,
      isTrue,
    );
  });

  test(
    'cavy validation rejects rabbit legacy awards without requiring them',
    () {
      final invalid = rules.validateAwardSelection(
        entry: cavy(),
        selectedAwards: {'BOV'},
      );
      expect(invalid.valid, isFalse);
      expect(invalid.message, contains('Rabbit variety awards'));
      expect(invalid.message, isNot(contains('requires BOV')));
    },
  );

  test('group conflicts and ownership are scoped to exact cavy group', () {
    final rows = [
      cavy(id: 'black-1', group: 'Black', awards: const ['BOG']),
      cavy(id: 'black-2', group: 'Black', awards: const ['BOG']),
      cavy(id: 'cream-1', group: 'Cream', awards: const ['BOG']),
    ];
    final issues = validateCavyResults(
      entries: rows,
      requireGroupAwards: true,
      requireBreedAwards: true,
      hasBasicOutcome: (_) => true,
      isEligibleForSpecialAward: (_) => true,
      isExcludedFromSpecials: (_) => false,
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      entryLabel: (entry) => entry['id'].toString(),
      sectionId: (entry) => entry['section_id'].toString(),
      breed: (entry) => entry['breed_id'].toString(),
      group: (entry) => rules.childIdentity(entry).stableKey,
      sex: (entry) => entry['sex'].toString(),
    );
    final duplicates = issues.where((issue) => issue.code == 'duplicate_bog');
    expect(duplicates, hasLength(1));
    expect(duplicates.single.groupScope, contains('black'));
    expect(duplicates.single.level.name, 'group');
  });

  test('failed SOP enrichment cannot erase variety fallback identity', () {
    final row = cavy(group: 'Cream')
      ..remove('cavy_sop_group_name')
      ..remove('group_name')
      ..remove('group_id');
    final child = rules.childIdentity(row);
    expect(child.displayName, 'Cream');
    expect(child.stableKey, 'fallback:american:cream');
  });

  test('cavy implementation cannot import a rabbit variety resolver', () {
    final source = File(
      'lib/services/results/cavy_results_rules.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('rabbit_results')));
    expect(source, isNot(contains('resolveRabbitVariety')));
  });
}
