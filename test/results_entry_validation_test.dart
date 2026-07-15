import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/cavy_results_validation.dart';
import 'package:ringmaster_show/services/results/rabbit_results_validation.dart';
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
      expect(resultsSpeciesForEntry({'sex': 'Boar'}), isEmpty);
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
    ) {
      final commonSpecies = resultsSpeciesForEntry(entries.first);
      if (commonSpecies == 'rabbit') {
        return validateRabbitResults(
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
      }
      return validateCavyResults(
        entries: entries,
        requireGroupAwards: false,
        requireBreedAwards: true,
        hasBasicOutcome: (e) => (e['placement'] as String).isNotEmpty,
        isEligibleForSpecialAward: (e) => e['placement'] == '1',
        isExcludedFromSpecials: (_) => false,
        awardCodes: (e) => List<String>.from(e['_awards'] as List),
        entryLabel: (e) => e['id'] as String,
        sectionId: (e) => e['section_id'] as String,
        breed: (e) => e['breed'] as String,
        group: (_) => '',
        sex: (e) => e['sex'] as String,
      );
    }

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

        final issue = issues.singleWhere(
          (issue) => issue.code == 'missing_bosb',
        );
        expect(issue.level, ResultsValidationIssueLevel.breed);
        expect(issue.awardCode, 'BOSB');
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

  group('results status and structured issue ownership', () {
    Map<String, dynamic> cavy(
      String id,
      String breed,
      String group, {
      String placement = '1',
    }) => {
      'id': id,
      'section_id': 'open-c',
      'species': 'Cavy',
      'breed_id': breed.toLowerCase(),
      'breed': breed,
      'group_name': group,
      'placement': placement,
    };

    test('completed results remain complete with no validation issues', () {
      final summary = buildResultsEntryStatusSummary(
        entries: [cavy('t1', 'Teddy', 'Self')],
        hasBasicOutcome: (entry) => entry['placement'] == '1',
        validationIssueCount: 0,
      );

      expect(summary.dataEntryComplete, isTrue);
      expect(summary.completionLabel, 'Results complete');
      expect(summary.needsAttention, isFalse);
    });

    test('award issues do not erase completed placement state', () {
      final summary = buildResultsEntryStatusSummary(
        entries: [cavy('t1', 'Teddy', 'Self')],
        hasBasicOutcome: (entry) => entry['placement'] == '1',
        validationIssueCount: 3,
      );

      expect(summary.dataEntryComplete, isTrue);
      expect(summary.completionLabel, 'Results complete');
      expect(summary.needsAttention, isTrue);
    });

    test('breed filtering excludes unrelated breed issues', () {
      final teddy = [cavy('t1', 'Teddy', 'Self')];
      final americanIssue = ResultsEntryBlockingIssue(
        code: 'missing_bob',
        title: 'Missing BOB',
        message: 'American needs BOB',
        entry: cavy('a1', 'American', 'Self'),
        level: ResultsValidationIssueLevel.breed,
        awardCode: 'BOB',
      );

      expect(resultsIssueAppliesToEntries(americanIssue, teddy), isFalse);
    });

    test('section conflict appears only for breeds containing a winner', () {
      final teddy = [cavy('t1', 'Teddy', 'Self')];
      final american = [cavy('a1', 'American', 'Self')];
      final conflict = ResultsEntryBlockingIssue(
        code: 'duplicate_award',
        title: 'Duplicate Best 6-Class',
        message: 'Two winners',
        entry: teddy.first,
        conflictsWith: american.first,
        level: ResultsValidationIssueLevel.section,
        awardCode: 'Best 6-Class',
      );
      final unrelated = ResultsEntryBlockingIssue(
        code: 'duplicate_award',
        title: 'Duplicate Best 6-Class',
        message: 'Two other winners',
        entry: cavy('a2', 'American', 'Solid'),
        conflictsWith: cavy('p1', 'Peruvian', 'Solid'),
        level: ResultsValidationIssueLevel.section,
        awardCode: 'Best 6-Class',
      );

      expect(resultsIssueAppliesToEntries(conflict, teddy), isTrue);
      expect(resultsIssueAppliesToEntries(unrelated, teddy), isFalse);
    });

    test('group issue marks only its structured group', () {
      final self = [cavy('t1', 'Teddy', 'Self')];
      final broken = [cavy('t2', 'Teddy', 'Broken')];
      final issue = ResultsEntryBlockingIssue(
        code: 'missing_bog',
        title: 'Missing BOG',
        message: 'Select BOG',
        entry: self.first,
        level: ResultsValidationIssueLevel.group,
        awardCode: 'BOG',
      );

      expect(resultsIssueAppliesToGroup(issue, self), isTrue);
      expect(resultsIssueAppliesToGroup(issue, broken), isFalse);
    });

    test('breed issue does not mark every group', () {
      final issue = ResultsEntryBlockingIssue(
        code: 'missing_bob',
        title: 'Missing BOB',
        message: 'Select BOB',
        entry: cavy('t1', 'Teddy', 'Self'),
        level: ResultsValidationIssueLevel.breed,
        awardCode: 'BOB',
      );

      expect(
        resultsIssueAppliesToGroup(issue, [cavy('t1', 'Teddy', 'Self')]),
        isFalse,
      );
    });
  });
}
