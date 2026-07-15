import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results/cavy_results_rules.dart';
import 'package:ringmaster_show/services/results/rabbit_results_rules.dart';
import 'package:ringmaster_show/services/results/results_rules.dart';
import 'package:ringmaster_show/services/results/results_rules_router.dart';

void main() {
  test('strict router selects exactly one implementation', () {
    expect(rulesForSpecies('Rabbits'), isA<RabbitResultsRules>());
    expect(rulesForSpecies('Cavies'), isA<CavyResultsRules>());
    expect(rulesForSpecies('rabbit'), same(rulesForSpecies('rabbit')));
    expect(rulesForSpecies('cavy'), same(rulesForSpecies('cavy')));
    expect(rulesForSpecies('rabbit'), isNot(isA<CavyResultsRules>()));
  });

  test('missing and unknown species never fall back', () {
    expect(
      () => rulesForSpecies(''),
      throwsA(isA<UnsupportedResultsSpecies>()),
    );
    expect(
      () => rulesForEntry({'sex': 'Boar', 'uses_group_awards': true}),
      throwsA(isA<UnsupportedResultsSpecies>()),
    );
    expect(
      () => rulesForEntry({'species': 'goat', 'uses_variety_awards': true}),
      throwsA(isA<UnsupportedResultsSpecies>()),
    );
  });

  test('species-specific variety aliases do not cross-normalize', () {
    const rabbit = RabbitResultsRules();
    const cavy = CavyResultsRules();
    expect(rabbit.normalizeStoredAwards(['Best of Group']), {'BOG'});
    expect(cavy.normalizeStoredAwards(['Best of Variety']), {
      'Best of Variety',
    });
  });

  test('validation entry points are physically separate', () {
    final rabbitSource = File(
      'lib/services/results/rabbit_results_validation.dart',
    ).readAsStringSync();
    final cavySource = File(
      'lib/services/results/cavy_results_validation.dart',
    ).readAsStringSync();
    final sharedSource = File(
      'lib/services/results_entry_validation.dart',
    ).readAsStringSync();
    expect(rabbitSource, contains('validateRabbitResults'));
    expect(rabbitSource, isNot(contains('validateCavyResults')));
    expect(cavySource, contains('validateCavyResults'));
    expect(cavySource, isNot(contains('validateRabbitResults')));
    expect(rabbitSource, contains('BOG'));
    expect(cavySource, isNot(contains('BOV')));
    expect(sharedSource, isNot(contains('buildBreedCompletionIssues')));
    expect(sharedSource, isNot(contains("requiredAwards: const ['BOV'")));
    expect(sharedSource, isNot(contains("requiredAwards: const ['BOG'")));
  });
}
