import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/cavy_results_validation.dart';
import 'package:ringmaster_show/services/results_award_configuration.dart';
import 'package:ringmaster_show/services/results_entry_validation.dart';
import 'package:ringmaster_show/services/results_group_resolution.dart';

void main() {
  Map<String, dynamic> teddy({
    String id = '014',
    String sex = 'Sow',
    String groupId = 'aos',
    List<String> awards = const ['BOG'],
    String sectionId = 'open-c',
  }) => {
    'id': id,
    'entry_id': id,
    'species': 'Cavy',
    'breed_id': 'teddy-id',
    'breed': 'Teddy',
    'group_id': groupId,
    'group_name': groupId == 'aos' ? 'Any Other Self' : 'Marked',
    'variety_id': 'teddy-variety',
    'variety': 'Teddy',
    'uses_group_awards': true,
    'uses_variety_awards': false,
    'class_name': 'Senior Sow',
    'class_system': 'six',
    'section_id': sectionId,
    'placement': '1',
    'sex': sex,
    '_awards': awards,
  };

  group('authoritative award mode', () {
    test('Teddy resolves to cavy group mode from structured fields', () {
      expect(resultsAwardModeForEntry(teddy()), ResultsAwardMode.cavyGroup);
    });

    test('rabbit variety and direct breed modes remain distinct', () {
      expect(
        resolveResultsAwardMode(
          species: 'Rabbit',
          breedId: 'mini-rex',
          usesGroupAwards: false,
          usesVarietyAwards: true,
          varietyId: 'black',
        ),
        ResultsAwardMode.rabbitVariety,
      );
      expect(
        resolveResultsAwardMode(
          species: 'Rabbit',
          breedId: 'direct',
          usesGroupAwards: false,
          usesVarietyAwards: false,
        ),
        ResultsAwardMode.directBreed,
      );
    });

    test('Teddy controls show group awards and not variety awards', () {
      final awards = visibleResultsAwardCodes(
        mode: resultsAwardModeForEntry(teddy()),
        className: 'Senior Sow',
        classSystem: 'six',
        finalAwardMode: 'four_six_bis',
      );

      expect(
        awards,
        containsAll(['Best Senior', 'BOG', 'BOSG', 'BOB', 'BOSB']),
      );
      expect(awards, isNot(contains('BOV')));
      expect(awards, isNot(contains('BOSV')));
      expect(
        resultsAwardLabel('Best Senior', ResultsAwardMode.cavyGroup),
        'Best Senior Group',
      );
    });

    test('rabbit controls preserve BOV/BOSV and exclude BOG/BOSG', () {
      final awards = visibleResultsAwardCodes(
        mode: ResultsAwardMode.rabbitVariety,
        className: 'Senior Doe',
        classSystem: 'four',
        finalAwardMode: 'four_six_bis',
      );

      expect(awards, containsAll(['BOV', 'BOSV', 'BOB', 'BOSB']));
      expect(awards, isNot(contains('BOG')));
      expect(awards, isNot(contains('BOSG')));
    });
  });

  group('normalized stored state and persistence', () {
    test('stored lowercase and display aliases reopen as checked BOG', () {
      expect(normalizedResultsAwardCodes(['bog']), {'BOG'});
      expect(normalizedResultsAwardCodes(['Best of Group']), {'BOG'});
    });

    test('summary and editor normalization resolve the same BOG record', () {
      final stored = teddy()['_awards'] as List<String>;
      final editorState = normalizedResultsAwardCodes(stored);
      final summaryState = normalizedResultsAwardCodes(stored);

      expect(editorState, contains('BOG'));
      expect(summaryState, editorState);
    });

    test('BOG serializes once and survives repeated Save & Next payloads', () {
      final first = serializeResultsAwardsForSave(['bog', 'BOG']);
      final second = serializeResultsAwardsForSave(first);

      expect(first, ['BOG']);
      expect(second, ['BOG']);
    });

    test('removing BOG removes it from persisted and summary state', () {
      final selected = normalizedResultsAwardCodes(['BOG'])..remove('BOG');
      final saved = serializeResultsAwardsForSave(selected);

      expect(saved, isEmpty);
    });
  });

  group('species-aware compatibility', () {
    test('valid Teddy BOG is accepted', () {
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: teddy(),
          selectedAwards: {'BOG'},
        ),
        isNull,
      );
    });

    test('BOG is rejected for a rabbit variety row', () {
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.rabbitVariety,
          entry: {
            'species': 'Rabbit',
            'variety_id': 'black',
            'uses_variety_awards': true,
          },
          selectedAwards: {'BOG'},
        ),
        contains('not valid for a rabbit'),
      );
    });

    test('cavy BOB and BOSB require group sources, not BOV or BOSV', () {
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: teddy(),
          selectedAwards: {'BOG', 'BOB'},
        ),
        isNull,
      );
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: teddy(),
          selectedAwards: {'BOSG', 'BOSB'},
        ),
        isNull,
      );
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: teddy(),
          selectedAwards: {'BOV', 'BOB'},
        ),
        contains('Variety awards are not valid'),
      );
    });

    test('direct breed mode does not require a variety or group source', () {
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.directBreed,
          entry: const {'species': 'Rabbit'},
          selectedAwards: {'BOB'},
        ),
        isNull,
      );
    });

    test('missing cavy group produces a precise compatibility message', () {
      final entry = teddy(groupId: '');
      entry['group_name'] = '';
      entry['variety'] = '';
      entry['variety_name'] = '';

      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: entry,
          selectedAwards: {'BOG'},
        ),
        'Teddy does not have a recognized cavy group or variety value. Best of Group cannot be assigned.',
      );
    });
  });

  group('scoped validation', () {
    List<ResultsEntryBlockingIssue> oppositeIssues(
      List<Map<String, dynamic>> entries,
    ) => buildOppositeSexAwardIssues(
      entries: entries,
      winnerCode: 'BOG',
      oppositeCode: 'BOSG',
      scopeLabel: 'cavy group',
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      scopeKey: (entry) => [
        entry['section_id'],
        entry['breed_id'],
        resultsAwardGroupScope(entry),
      ].join('|'),
      sex: (entry) => entry['sex'].toString(),
      entryLabel: (entry) => entry['id'].toString(),
    );

    test('different cavy groups can each have BOG and BOSG winners', () {
      final issues = oppositeIssues([
        teddy(id: 'a1', sex: 'Boar', awards: ['BOG']),
        teddy(id: 'a2', sex: 'Sow', awards: ['BOSG']),
        teddy(id: 'b1', sex: 'Boar', groupId: 'marked', awards: ['BOG']),
        teddy(id: 'b2', sex: 'Sow', groupId: 'marked', awards: ['BOSG']),
      ]);

      expect(issues, isEmpty);
    });

    test('valid Teddy BOG/BOB and BOSG/BOSB records complete without BOV', () {
      final entries = [
        teddy(id: '014', sex: 'Boar', awards: ['BOG', 'BOB']),
        teddy(id: '019', sex: 'Sow', awards: ['BOSG', 'BOSB']),
      ];
      final issues = validateCavyResults(
        entries: entries,
        requireGroupAwards: true,
        requireBreedAwards: true,
        hasBasicOutcome: (entry) => entry['placement'] == '1',
        isEligibleForSpecialAward: (entry) => entry['placement'] == '1',
        isExcludedFromSpecials: (_) => false,
        awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
        entryLabel: (entry) => entry['id'].toString(),
        sectionId: (entry) => entry['section_id'].toString(),
        breed: (entry) => entry['breed_id'].toString(),
        group: resultsAwardGroupScope,
        sex: (entry) => entry['sex'].toString().toLowerCase(),
      );

      expect(issues, isEmpty);
    });

    test('same-group same-sex BOG and BOSG produce an issue', () {
      final issues = oppositeIssues([
        teddy(id: '014', sex: 'Sow', awards: ['BOG']),
        teddy(id: '019', sex: 'Sow', awards: ['BOSG']),
      ]);

      expect(issues.single.code, 'opposite_sex');
    });

    test('different groups do not produce a false sex conflict', () {
      final issues = oppositeIssues([
        teddy(id: '014', sex: 'Sow', awards: ['BOG']),
        teddy(id: '019', sex: 'Sow', groupId: 'marked', awards: ['BOSG']),
      ]);

      expect(issues, isEmpty);
    });

    test('final award scope remains exact to section', () {
      expect(
        resultsFinalAwardScopeKey(teddy(sectionId: 'open-c'), 'Best 6-Class'),
        isNot(
          resultsFinalAwardScopeKey(
            teddy(sectionId: 'youth-c'),
            'Best 6-Class',
          ),
        ),
      );
    });
  });

  group('cavy SOP group resolution', () {
    Map<String, dynamic> american({
      required String id,
      required String variety,
      required String award,
      String sex = 'Sow',
      bool enriched = false,
    }) => {
      'id': id,
      'entry_id': id,
      'section_id': 'open-c',
      'species': 'cavy',
      'breed_id': 'american-id',
      'breed_name': 'American',
      'breed': 'American',
      'variety': variety,
      'variety_name': variety,
      if (enriched) 'exact_variety_name': variety,
      if (enriched) 'cavy_sop_variety_id': 'sop-$id',
      if (enriched) 'cavy_sop_variety_name': variety,
      'uses_group_awards': true,
      'uses_variety_awards': false,
      'placement': '1',
      'sex': sex,
      '_awards': [award],
    };

    test('American Black, Cream, and White resolve through row fallback', () {
      for (final variety in const ['Black', 'Cream', 'White']) {
        final group = resolveCavyGroup(
          american(id: variety, variety: variety, award: 'BOSG'),
        );
        expect(group.name, variety);
        expect(
          group.normalizedKey,
          'fallback:american-id:${variety.toLowerCase()}',
        );
        expect(group.isRecognized, isTrue);
        expect(group.source, 'varietyFallback');
        expect(group.confidence, 'fallback');
      }
    });

    test('successful SOP enrichment preserves the fallback identity', () {
      final before = american(id: '193', variety: 'Black', award: 'BOG');
      final after = american(
        id: '193',
        variety: 'Black',
        award: 'BOG',
        enriched: true,
      );

      expect(resolveCavyGroup(before).displayName, 'Black');
      expect(
        resolveCavyGroup(after).stableKey,
        resolveCavyGroup(before).stableKey,
      );
    });

    test('failed enrichment does not erase existing visible groups', () {
      final entry = american(id: '193', variety: 'Black', award: 'BOG');
      entry.remove('exact_variety_name');
      entry.remove('cavy_sop_variety_id');
      entry.remove('cavy_sop_variety_name');

      final group = resolveCavyGroup(entry);
      expect(group.displayName, 'Black');
      expect(group.recognized, isTrue);
      expect(group.source, 'varietyFallback');
    });

    test('missing species does not resolve from Sow sex fallback', () {
      final entry = american(id: '193', variety: 'Black', award: 'BOG')
        ..remove('species');

      expect(resolveCavyGroup(entry).displayName, isEmpty);
      expect(resolveCavyGroup(entry).stableKey, isEmpty);
    });

    test('five American entries retain three distinct group cards', () {
      final entries = [
        american(id: '193', variety: 'Black', award: 'BOG'),
        american(id: '160', variety: 'Black', award: 'BOSG'),
        american(id: 'black-3', variety: 'Black', award: ''),
        american(id: 'RGD104', variety: 'Cream', award: 'BOSG'),
        american(id: 'V214', variety: 'White', award: 'BOSG'),
      ];
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final entry in entries) {
        final group = resolveCavyGroup(entry);
        grouped.putIfAbsent(group.stableKey, () => []).add(entry);
      }

      expect(grouped, hasLength(3));
      expect(
        grouped['fallback:american-id:black']!.map((e) => e['id']),
        containsAll(['193', '160', 'black-3']),
      );
      expect(grouped['fallback:american-id:cream'], hasLength(1));
      expect(grouped['fallback:american-id:white'], hasLength(1));
      expect(grouped, isNot(contains('')));
    });

    test('group card label and award scope use the same resolved key', () {
      final entry = american(id: '193', variety: 'Black', award: 'BOG');
      final group = resolveCavyGroup(entry);

      expect(group.name, 'Black');
      expect(resultsAwardGroupScope(entry), group.normalizedKey);
    });

    test('existing American BOG reopens checked and enabled', () {
      final entry = american(id: '193', variety: 'Black', award: 'BOG');

      expect(normalizedResultsAwardCodes(entry['_awards'] as List), {'BOG'});
      expect(
        resultsAwardModeHasRecognizedSource(ResultsAwardMode.cavyGroup, entry),
        isTrue,
      );
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: entry,
          selectedAwards: {'BOG'},
        ),
        isNull,
      );
    });

    test('stored BOSG entries retain their exact American groups', () {
      expect(
        resolveCavyGroup(
          american(id: '160', variety: 'Black', award: 'BOSG'),
        ).name,
        'Black',
      );
      expect(
        resolveCavyGroup(
          american(id: 'RGD104', variety: 'Cream', award: 'BOSG'),
        ).name,
        'Cream',
      );
      expect(
        resolveCavyGroup(
          american(id: 'V214', variety: 'White', award: 'BOSG'),
        ).name,
        'White',
      );
    });

    List<ResultsEntryBlockingIssue> groupSexIssues(
      List<Map<String, dynamic>> entries,
    ) => buildOppositeSexAwardIssues(
      entries: entries,
      winnerCode: 'BOG',
      oppositeCode: 'BOSG',
      scopeLabel: 'group',
      awardCodes: (entry) => List<String>.from(entry['_awards'] as List),
      scopeKey: (entry) => resultsAwardGroupScope(entry),
      sex: (entry) => entry['sex'].toString(),
      entryLabel: (entry) => entry['id'].toString(),
    );

    test('Black BOG and BOSG are compared within Black', () {
      final issues = groupSexIssues([
        american(id: '193', variety: 'Black', award: 'BOG'),
        american(id: '160', variety: 'Black', award: 'BOSG'),
      ]);

      expect(issues.single.code, 'opposite_sex');
      expect(issues.single.groupScope, contains('black'));
    });

    test('Cream and White BOSG do not compare against Black BOG', () {
      final issues = groupSexIssues([
        american(id: '193', variety: 'Black', award: 'BOG'),
        american(id: 'RGD104', variety: 'Cream', award: 'BOSG'),
        american(id: 'V214', variety: 'White', award: 'BOSG'),
      ]);

      expect(issues, isEmpty);
    });

    test('fallback group issue count attaches only to Black', () {
      final black = american(id: '193', variety: 'Black', award: 'BOG');
      final cream = american(id: 'RGD104', variety: 'Cream', award: 'BOSG');
      final issue = ResultsEntryBlockingIssue(
        code: 'missing_bosg',
        title: 'Missing BOSG',
        message: 'Select BOSG for Black',
        entry: black,
        level: ResultsValidationIssueLevel.group,
        awardCode: 'BOSG',
      );

      expect(resultsIssueAppliesToGroup(issue, [black]), isTrue);
      expect(resultsIssueAppliesToGroup(issue, [cream]), isFalse);
    });

    test('mapped groups do not produce missing-group compatibility errors', () {
      final entry = american(id: '193', variety: 'Black', award: 'BOG');
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: entry,
          selectedAwards: {'BOG'},
        ),
        isNull,
      );
    });

    test('truly blank cavy group retains a precise error', () {
      final entry = {
        'species': 'cavy',
        'breed_name': 'American',
        'variety_name': '',
        'uses_group_awards': true,
      };

      expect(resolveCavyGroup(entry).isRecognized, isFalse);
      expect(
        validateAwardModeCompatibility(
          mode: ResultsAwardMode.cavyGroup,
          entry: entry,
          selectedAwards: {'BOG'},
        ),
        contains('American does not have a recognized cavy group'),
      );
    });

    test('blank group and blank variety remain unresolved', () {
      final entry = {
        'species': 'cavy',
        'breed_name': 'American',
        'variety_name': '',
        'uses_group_awards': true,
      };

      expect(resolveCavyGroup(entry), same(ResolvedCavyGroup.unresolved));
    });
  });
}
