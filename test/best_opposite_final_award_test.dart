import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/final_award_format.dart';
import 'package:ringmaster_show/services/results/rabbit_results_rules.dart';
import 'package:ringmaster_show/services/results/cavy_results_rules.dart';
import 'package:ringmaster_show/services/results/results_rules.dart';
import 'package:ringmaster_show/services/results_award_configuration.dart';
import 'package:ringmaster_show/services/results/final_award_readiness.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/results_readiness.dart';

void main() {
  for (final rules in <ResultsRules>[
    const RabbitResultsRules(),
    const CavyResultsRules(),
  ]) {
    final entry = <String, dynamic>{
      'id': 'entry',
      'species': rules.speciesName,
      'class_name': 'Senior',
      'breed': 'American',
      'variety': 'Black',
      'uses_variety_awards': true,
    };
    bool canUse(
      Set<String> awards, {
      String mode = bestOppositeFinalAwardMode,
      String status = 'Shown',
      String placement = '1',
      String award = bestOppositeAwardCode,
      Map<String, dynamic>? row,
    }) => rules.canUseAward(
      entry: row ?? entry,
      award: award,
      selectedAwards: awards,
      effectiveStatus: status,
      effectivePlacement: placement,
      classSystem: 'four',
      finalAwardMode: mode,
    );

    group(rules.speciesName, () {
      test('new mode retains BIS and both reserves', () {
        final awards = rules.buildAwardOptions(
          entry: entry,
          classSystem: 'four',
          finalAwardMode: bestOppositeFinalAwardMode,
        );
        expect(awards, containsAll(['Best In Show', '1RIS', '2RIS', 'BBOS']));
        expect(awards, isNot(contains('Best 4-Class')));
        expect(canUse({'BOB'}, award: '1RIS'), isTrue);
        expect(canUse({'BOB'}, award: '2RIS'), isTrue);
        expect(canUse({'BOB', 'Best In Show'}, award: '1RIS'), isFalse);
        expect(canUse({'BOB', '1RIS'}, award: '2RIS'), isFalse);
      });
      test('only breed BOS qualifies, not BOB or lower opposite awards', () {
        expect(canUse({'BOSB'}), isTrue);
        expect(canUse({'BOS'}), isTrue);
        for (final awards in <Set<String>>[
          {},
          {'BOB'},
          {'BOSV'},
          {'BOSG'},
        ]) {
          expect(canUse(awards), isFalse, reason: '$awards');
        }
        expect(rules.awardLabel('BBOS'), bestOppositeAwardLabel);
      });
      test('not available in the existing formats', () {
        for (final mode in ['four_six_bis', 'bis_ris', 'bis_1ris_2ris']) {
          expect(canUse({'BOSB'}, mode: mode), isFalse);
          expect(
            rules.buildAwardOptions(
              entry: entry,
              classSystem: 'four',
              finalAwardMode: mode,
            ),
            isNot(contains('BBOS')),
          );
        }
      });
      test('requires an eligible shown first-place animal', () {
        for (final status in [
          'No Show',
          'Disqualified - Other',
          'Unworthy of Award',
        ]) {
          expect(canUse({'BOSB'}, status: status), isFalse);
        }
        for (final placement in ['', '0', '2']) {
          expect(canUse({'BOSB'}, placement: placement), isFalse);
        }
        expect(
          canUse({'BOSB'}, row: {...entry, 'scratched_at': '2026-09-14'}),
          isFalse,
        );
      });
      test('removing BOS makes a retained opposite award invalid', () {
        expect(
          rules
              .validateAwardSelection(
                entry: entry,
                selectedAwards: {'BOSV', 'BBOS'},
              )
              .valid,
          isFalse,
        );
        expect(
          rules
              .validateAwardSelection(
                entry: entry,
                selectedAwards: {'BOSV', 'BOSB', 'BBOS'},
              )
              .valid,
          isTrue,
        );
      });
    });
  }
  test('award aliases serialize to one persistent code', () {
    expect(
      serializeResultsAwardsForSave([
        'BBOS',
        'Best of the Best Opposite',
        'BOS',
      ]),
      ['BBOS', 'BOSB'],
    );
  });
  test('missing opposite award warns without blocking closeout', () {
    final json = <String, dynamic>{
      'ready': true,
      'suggested_final_award_count': 1,
      'suggested_final_awards': [
        {
          'section_id': 'open-a',
          'section_label': 'Open A',
          'award_code': 'BBOS',
          'award_label': bestOppositeAwardLabel,
        },
      ],
    };
    expect(blockingFinalAwardReadinessIssues(json), isEmpty);
    final readiness = ResultsReadinessDto.fromJson(json);
    expect(readiness.ready, isTrue);
    expect(
      readiness.suggestedFinalAwards.single.awardLabel,
      bestOppositeAwardLabel,
    );
  });
}
