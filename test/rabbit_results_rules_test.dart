import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/rabbit_results_rules.dart';
import 'package:ringmaster_show/services/results/rabbit_results_structure.dart';
import 'package:ringmaster_show/services/results/rabbit_results_validation.dart';

void main() {
  const rules = RabbitResultsRules();

  Map<String, dynamic> rabbit({
    String id = 'rabbit-1',
    String breed = 'Mini Rex',
    String variety = 'Black',
    String varietyId = 'black-id',
    String group = 'Self',
    String groupId = 'self-id',
    bool usesGroups = true,
    bool usesVarieties = true,
    String sex = 'Doe',
    String className = 'Senior Doe',
    bool isNationalShow = false,
    List<String> awards = const [],
  }) => {
    'id': id,
    'entry_id': id,
    'species': 'Rabbit',
    'section_id': 'rabbit-open-a',
    'breed_id': breed.toLowerCase().replaceAll(' ', '-'),
    'breed': breed,
    'rabbit_variety_id': varietyId,
    'rabbit_variety_name': variety,
    'variety': variety,
    'rabbit_group_id': groupId,
    'rabbit_group_name': group,
    'uses_variety_awards': usesVarieties,
    'uses_group_awards': usesGroups,
    'placement': '1',
    'result_status': 'Shown',
    'class_name': className,
    'is_national_show': isNationalShow,
    'sex': sex,
    '_awards': awards,
  };

  test('rabbit breed flags select all four supported structures', () {
    expect(
      rabbitBreedStructure(rabbit(usesGroups: false, usesVarieties: false)),
      RabbitBreedStructure.directBreed,
    );
    expect(
      rabbitBreedStructure(rabbit(usesGroups: false, usesVarieties: true)),
      RabbitBreedStructure.varietyOnly,
    );
    expect(
      rabbitBreedStructure(rabbit(usesGroups: true, usesVarieties: false)),
      RabbitBreedStructure.groupOnly,
    );
    expect(
      rabbitBreedStructure(rabbit()),
      RabbitBreedStructure.groupedVarieties,
    );
  });

  test('Mini Rex groups contain their catalog varieties', () {
    final rows = [
      rabbit(id: 'black', variety: 'Black', varietyId: 'black'),
      rabbit(id: 'blue', variety: 'Blue', varietyId: 'blue'),
      rabbit(
        id: 'castor',
        variety: 'Castor',
        varietyId: 'castor',
        group: 'Agouti',
        groupId: 'agouti',
      ),
    ];
    final groups = rules.buildGroupGroups(rows);
    expect(groups.map((group) => group.displayName), {'Self', 'Agouti'});
    final self = groups.singleWhere((group) => group.displayName == 'Self');
    expect(rules.buildVarietyGroups(self.entries).map((v) => v.displayName), {
      'Black',
      'Blue',
    });
  });

  test('Netherland Dwarf preserves stable group and variety navigation', () {
    final row = rabbit(
      id: 'nd-opal',
      breed: 'Netherland Dwarf',
      variety: 'Opal',
      varietyId: 'opal-id',
      group: 'Group 3 Agouti',
      groupId: 'group-3',
    );
    final target = rules.buildFixTarget(row);
    expect(target.groupKey, 'rabbit-group:netherland-dwarf:group-3');
    expect(target.varietyKey, 'variety:netherland-dwarf:opal-id');
    expect(target.classSexKey, 'Senior Doe');
    expect(target.entryId, 'nd-opal');
  });

  for (final fixture in const [
    ('Jersey Wooly', 'AOV'),
    ('English Angora', 'Colored'),
    ('French Angora', 'White'),
    ('Giant Angora', 'Colored'),
    ('Satin Angora', 'White'),
  ]) {
    test('${fixture.$1} uses its catalog variety row as rabbit group', () {
      final row = rabbit(
        breed: fixture.$1,
        variety: fixture.$2,
        varietyId: '${fixture.$2}-id',
        group: '',
        groupId: '',
        usesGroups: true,
        usesVarieties: false,
      );
      expect(rules.usesGroupLayer(row), isTrue);
      expect(rules.usesVarietyLayer(row), isFalse);
      expect(rules.groupIdentity(row).displayName, fixture.$2);
      expect(rules.groupIdentity(row).stableKey, startsWith('rabbit-group:'));
    });
  }

  test('variety-only rabbit stays out of rabbit group navigation', () {
    final row = rabbit(
      breed: 'Harlequin',
      variety: 'Magpie',
      usesGroups: false,
      usesVarieties: true,
    );
    expect(rules.usesGroupLayer(row), isFalse);
    expect(rules.usesVarietyLayer(row), isTrue);
    expect(rules.childIdentity(row).displayName, 'Magpie');
  });

  test('direct rabbit has no group or variety layer', () {
    final row = rabbit(
      breed: 'Direct Breed',
      variety: '',
      varietyId: '',
      group: '',
      groupId: '',
      usesGroups: false,
      usesVarieties: false,
    );
    expect(rules.usesChildLayer(row), isFalse);
    expect(rules.childIdentity(row).stableKey, 'direct:direct-breed');
  });

  test('historical rabbit BOG/BOSG are valid only for group breeds', () {
    expect(
      rules
          .validateAwardSelection(
            entry: rabbit(usesGroups: true, usesVarieties: false),
            selectedAwards: {'BOG', 'BOB'},
          )
          .valid,
      isTrue,
    );
    final incompatible = rules.validateAwardSelection(
      entry: rabbit(usesGroups: false, usesVarieties: true),
      selectedAwards: {'BOG'},
    );
    expect(incompatible.valid, isFalse);
    expect(incompatible.message, contains('rabbit breed structure'));
  });

  test('grouped rabbit editor exposes both rabbit hierarchy award levels', () {
    final options = rules.buildAwardOptions(
      entry: rabbit(),
      classSystem: 'four',
      finalAwardMode: 'bis_ris',
    );
    expect(options, containsAll(['BOV', 'BOSV', 'BOG', 'BOSG', 'BOB', 'BOSB']));
    expect(rules.awardLabel('BOG'), 'Best of Rabbit Group');
    expect(options, isNot(contains('HM')));
    expect(options, isNot(contains('Best 4-Class')));
    expect(options, isNot(contains('Best 6-Class')));
    expect(rules.normalizeStoredAwards(['BOV', 'BOSV']), {'BOV', 'BOSV'});
  });

  test('four/six finals require matching BOB hierarchy', () {
    final entry = rabbit(usesGroups: false, usesVarieties: false);
    final options = rules.buildAwardOptions(
      entry: entry,
      classSystem: 'four',
      finalAwardMode: 'four_six_bis',
    );
    expect(
      options,
      containsAll(['Best 4-Class', 'Best 6-Class', 'Best In Show']),
    );

    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Best 4-Class',
        selectedAwards: {'BOB'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'four_six_bis',
      ),
      isTrue,
    );
    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Best 6-Class',
        selectedAwards: {'BOB'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'four_six_bis',
      ),
      isFalse,
    );
    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Best In Show',
        selectedAwards: {'BOB'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'four_six_bis',
      ),
      isFalse,
    );
    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Best In Show',
        selectedAwards: {'BOB', 'Best 4-Class'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'four_six_bis',
      ),
      isTrue,
    );
    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Best 6-Class',
        selectedAwards: {'BOB'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'six',
        finalAwardMode: 'four_six_bis',
      ),
      isTrue,
    );
    expect(
      rules
          .validateAwardSelection(
            entry: entry,
            selectedAwards: {'BOB', 'Best 4-Class'},
          )
          .valid,
      isTrue,
    );
  });

  test('BIS/RIS mode remains independent from four/six final awards', () {
    final entry = rabbit(usesGroups: false, usesVarieties: false);
    final options = rules.buildAwardOptions(
      entry: entry,
      classSystem: 'four',
      finalAwardMode: 'bis_ris',
    );

    expect(options, containsAll(['Best In Show', 'Reserve In Show']));
    expect(options, isNot(contains('Best 4-Class')));
    expect(options, isNot(contains('Best 6-Class')));

    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Best In Show',
        selectedAwards: {'BOB'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      ),
      isTrue,
    );
    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Reserve In Show',
        selectedAwards: {'BOB'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      ),
      isTrue,
    );
    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Reserve In Show',
        selectedAwards: {'BOB', 'Best In Show'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      ),
      isFalse,
    );
    expect(
      rules.canUseAward(
        entry: entry,
        award: 'Best 4-Class',
        selectedAwards: {'BOB'},
        effectiveStatus: 'Shown',
        effectivePlacement: '1',
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      ),
      isFalse,
    );
  });

  test(
    'Himalayan specialty awards use breed-level junior and senior awards',
    () {
      final senior = rabbit(
        breed: 'Himalayan',
        usesGroups: false,
        usesVarieties: true,
        className: 'Senior Doe',
      );
      final junior = rabbit(
        breed: 'Himalayan',
        usesGroups: false,
        usesVarieties: true,
        className: 'Junior Buck',
      );

      final seniorOptions = rules.buildAwardOptions(
        entry: senior,
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      );
      final juniorOptions = rules.buildAwardOptions(
        entry: junior,
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      );
      expect(seniorOptions, contains('BSB'));
      expect(seniorOptions, isNot(contains('BSV')));
      expect(juniorOptions, contains('BJB'));
      expect(juniorOptions, isNot(contains('BJV')));
      expect(
        rules.canUseAward(
          entry: senior,
          award: 'BSB',
          selectedAwards: const {},
          effectiveStatus: 'Shown',
          effectivePlacement: '1',
          classSystem: 'four',
          finalAwardMode: 'bis_ris',
        ),
        isTrue,
      );

      final nationalSenior = {...senior, 'is_national_show': true};
      final nationalJunior = {...junior, 'is_national_show': true};
      final nationalOptions = rules.buildAwardOptions(
        entry: nationalSenior,
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      );
      final nationalJuniorOptions = rules.buildAwardOptions(
        entry: nationalJunior,
        classSystem: 'four',
        finalAwardMode: 'bis_ris',
      );
      expect(nationalOptions, containsAll(['BSV', 'BSB']));
      expect(nationalJuniorOptions, containsAll(['BJV', 'BJB']));
      expect(
        rules.canUseAward(
          entry: nationalSenior,
          award: 'BSB',
          selectedAwards: const {},
          effectiveStatus: 'Shown',
          effectivePlacement: '1',
          classSystem: 'four',
          finalAwardMode: 'bis_ris',
        ),
        isTrue,
      );
    },
  );

  test('display metadata alone never enables rabbit group awards', () {
    final row = rabbit(usesGroups: false, usesVarieties: true);
    final options = rules.buildAwardOptions(
      entry: row,
      classSystem: 'four',
      finalAwardMode: 'bis_ris',
    );
    expect(row['rabbit_group_id'], isNotEmpty);
    expect(options, isNot(contains('BOG')));
    expect(options, isNot(contains('BOSG')));
  });

  test('class-only validation does not inherit rabbit hierarchy issues', () {
    final row = rabbit(awards: const []);
    final issues = validateRabbitResults(
      entries: [row],
      requireVarietyAwards: false,
      requireGroupAwards: false,
      requireBreedAwards: false,
      hasBasicOutcome: (_) => true,
      isEligibleForSpecialAward: (_) => true,
      isExcludedFromSpecials: (_) => false,
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      entryLabel: (entry) => entry['id'].toString(),
      sectionId: (entry) => entry['section_id'].toString(),
      breed: (entry) => entry['breed_id'].toString(),
      variety: (entry) => rules.varietyIdentity(entry).stableKey,
      group: (entry) => rules.groupIdentity(entry).stableKey,
      sex: (entry) => entry['sex'].toString(),
    );
    expect(issues, isEmpty);
  });

  test('rabbit group validation owns its exact rabbit group scope', () {
    final rows = [
      rabbit(id: 'black-1', awards: const ['BOG']),
      rabbit(id: 'black-2', awards: const ['BOG']),
      rabbit(
        id: 'castor',
        variety: 'Castor',
        varietyId: 'castor',
        group: 'Agouti',
        groupId: 'agouti',
        awards: const ['BOG'],
      ),
    ];
    final issues = validateRabbitResults(
      entries: rows,
      requireVarietyAwards: false,
      requireGroupAwards: true,
      requireBreedAwards: false,
      hasBasicOutcome: (_) => true,
      isEligibleForSpecialAward: (_) => true,
      isExcludedFromSpecials: (_) => false,
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      entryLabel: (entry) => entry['id'].toString(),
      sectionId: (entry) => entry['section_id'].toString(),
      breed: (entry) => entry['breed_id'].toString(),
      variety: (entry) => rules.varietyIdentity(entry).stableKey,
      group: (entry) => rules.groupIdentity(entry).stableKey,
      sex: (entry) => entry['sex'].toString(),
    );
    final duplicate = issues.singleWhere((i) => i.code == 'duplicate_bog');
    expect(duplicate.groupScope, contains('self-id'));
  });

  test('rabbit implementation never imports cavy resolution', () {
    final rulesSource = File(
      'lib/services/results/rabbit_results_rules.dart',
    ).readAsStringSync();
    final structureSource = File(
      'lib/services/results/rabbit_results_structure.dart',
    ).readAsStringSync();
    expect('$rulesSource$structureSource', isNot(contains('resolveCavyGroup')));
    expect('$rulesSource$structureSource', isNot(contains('CavyResultsRules')));
    expect('$rulesSource$structureSource', isNot(contains('cavy_sop')));
  });
}
