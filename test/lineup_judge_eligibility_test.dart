import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/superintendent/lineup_judge_eligibility.dart';

void main() {
  test('rabbit, cavy and dual judges match only their recorded species', () {
    for (final type in [
      'Rabbit',
      'RABBIT',
      ' Cavy ',
      'Dual',
      '',
      'unknown',
      null,
    ]) {
      for (final species in [
        <String>['rabbit'],
        <String>['cavy'],
        <String>['rabbit', 'cavy'],
      ]) {
        final normalized = type?.trim().toLowerCase();
        final expected =
            normalized == 'dual' ||
            (species.length == 1 && species.single == normalized);
        expect(
          lineupJudgeSupportsSpecies({'judge_type': type}, species),
          expected,
          reason: '$type for $species',
        );
      }
    }
  });
  test('disabled judges and unidentified species are not auto assigned', () {
    expect(
      lineupJudgeSupportsSpecies(
        {'judge_type': 'Dual', 'is_enabled': false},
        ['cavy'],
      ),
      isFalse,
    );
    for (final species in [
      <String>[],
      [''],
      ['rabbit', 'unknown'],
    ]) {
      expect(
        lineupJudgeSupportsSpecies({'judge_type': 'Dual'}, species),
        isFalse,
      );
    }
  });
}
