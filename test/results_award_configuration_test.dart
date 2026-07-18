import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/results_award_configuration.dart';

void main() {
  Map<String, dynamic> cavy() => {
    'species': 'Cavy',
    'breed_id': 'american-satin',
    'breed': 'American Satin',
    'variety': 'Self',
    'uses_group_awards': false,
    'uses_variety_awards': true,
    'class_name': 'Senior Sow',
  };

  test('cavy catalog configuration resolves to the variety award flow', () {
    expect(resultsAwardModeForEntry(cavy()), ResultsAwardMode.cavyGroup);
    expect(sourceAwardCodesForMode(ResultsAwardMode.cavyGroup), {
      'BOV',
      'BOSV',
    });
  });

  test('cavy labels use variety and explicit age levels', () {
    expect(
      resultsAwardLabel('BOV', ResultsAwardMode.cavyGroup),
      'Best of Variety',
    );
    expect(
      resultsAwardLabel('BSV', ResultsAwardMode.cavyGroup),
      'Best Senior Variety',
    );
    expect(
      resultsAwardLabel('BSB', ResultsAwardMode.cavyGroup),
      'Best Senior of Breed',
    );
  });

  test('visible cavy awards include age, variety, and breed stages', () {
    final awards = visibleResultsAwardCodes(
      mode: ResultsAwardMode.cavyGroup,
      className: 'Senior Sow',
      classSystem: 'six',
      finalAwardMode: 'bis_ris',
    );
    expect(awards, containsAll(['BSV', 'BSB', 'BOV', 'BOSV', 'BOB', 'BOSB']));
    expect(awards, isNot(contains('BOG')));
  });

  test('cavy breed awards require variety award sources', () {
    expect(
      validateAwardModeCompatibility(
        mode: ResultsAwardMode.cavyGroup,
        entry: cavy(),
        selectedAwards: {'BOV', 'BOB'},
      ),
      isNull,
    );
    expect(
      validateAwardModeCompatibility(
        mode: ResultsAwardMode.cavyGroup,
        entry: cavy(),
        selectedAwards: {'BOB'},
      ),
      contains('Best of Variety'),
    );
  });

  test('rabbit variety award behavior remains separate', () {
    final mode = resolveResultsAwardMode(
      species: 'Rabbit',
      breedId: 'mini-rex',
      usesGroupAwards: false,
      usesVarietyAwards: true,
    );
    expect(mode, ResultsAwardMode.rabbitVariety);
    expect(sourceAwardCodesForMode(mode), {'BOV', 'BOSV'});
  });
}
