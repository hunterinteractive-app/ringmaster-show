import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results_entry_validation.dart';

void main() {
  group('results species normalization', () {
    test('normalizes singular, plural, and case', () {
      expect(normalizeResultsSpecies('Rabbit'), 'rabbit');
      expect(normalizeResultsSpecies('rabbits'), 'rabbit');
      expect(normalizeResultsSpecies('CAVY'), 'cavy');
      expect(normalizeResultsSpecies('cavies'), 'cavy');
    });

    test('uses the explicit species before sex fallback', () {
      expect(
        resultsSpeciesForEntry({'species': 'Rabbits', 'sex': 'Sow'}),
        'rabbit',
      );
      expect(resultsSpeciesForEntry({'sex': 'Boar'}), 'cavy');
    });

    test('final award scope separates species, show, and section', () {
      final rabbit = {
        'show_id': 'show-1',
        'section_id': 'open-a',
        'species': 'Rabbits',
      };
      final cavy = {
        'show_id': 'show-1',
        'section_id': 'open-a',
        'species': 'Cavies',
      };

      expect(
        resultsFinalAwardScopeKey(rabbit, '1ris'),
        isNot(resultsFinalAwardScopeKey(cavy, '1RIS')),
      );
      expect(
        resultsFinalAwardScopeKey(rabbit, '1RIS'),
        isNot(
          resultsFinalAwardScopeKey({
            ...rabbit,
            'section_id': 'youth-a',
          }, '1RIS'),
        ),
      );
      expect(
        resultsFinalAwardScopeKey(rabbit, '1ris'),
        resultsFinalAwardScopeKey({...rabbit, 'species': 'rabbit'}, '1RIS'),
      );
    });

    test('uses show letter when a result row has no section id', () {
      expect(resultsSectionScopeForEntry({'show_letter': 'Open A'}), 'open a');
      expect(
        resultsFinalAwardScopeKey({
          'show_id': 'show-1',
          'show_letter': 'Open A',
          'species': 'Rabbit',
        }, 'BIS'),
        isNot(
          resultsFinalAwardScopeKey({
            'show_id': 'show-1',
            'show_letter': 'Youth A',
            'species': 'Rabbit',
          }, 'BIS'),
        ),
      );
    });
  });

  group('breed completion issues', () {
    Map<String, dynamic> entry({
      required String id,
      required String species,
      required String sex,
      String placement = '1',
      List<String> awards = const [],
    }) => {
      'id': id,
      'species': species,
      'sex': sex,
      'section_id': 'open-a',
      'breed': 'Test Breed',
      'variety': 'Test Variety',
      'placement': placement,
      '_awards': awards,
    };

    List<ResultsEntryBlockingIssue> validate(
      List<Map<String, dynamic>> entries,
    ) => buildBreedCompletionIssues(
      entries: entries,
      requireVarietyAwards: false,
      requireGroupAwards: false,
      requireBreedAwards: true,
      hasBasicOutcome: (e) => (e['placement'] as String).isNotEmpty,
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

    test('reports a duplicate breed award that blocks completion', () {
      final issues = validate([
        entry(id: 'R1', species: 'Rabbit', sex: 'buck', awards: ['BOB']),
        entry(id: 'R2', species: 'rabbit', sex: 'doe', awards: ['BOB']),
      ]);

      expect(issues.any((issue) => issue.code == 'duplicate_bob'), isTrue);
    });

    test(
      'reports missing opposite winner when an eligible candidate exists',
      () {
        final issues = validate([
          entry(id: 'C1', species: 'Cavy', sex: 'boar', awards: ['BOB']),
          entry(id: 'C2', species: 'cavies', sex: 'sow'),
        ]);

        expect(issues.any((issue) => issue.code == 'missing_bosb'), isTrue);
      },
    );

    test('reports incomplete placement or result', () {
      final issues = validate([
        entry(id: 'R1', species: 'Rabbit', sex: 'buck', placement: ''),
      ]);

      expect(
        issues.any((issue) => issue.code == 'missing_basic_outcome'),
        isTrue,
      );
    });
  });
}
