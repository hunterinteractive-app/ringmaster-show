import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/superintendent/lineup_timing.dart';
import 'package:ringmaster_show/superintendent/specialty_lineup_dialog.dart';

void main() {
  test('workload takes priority over avoiding timing conflicts', () {
    expect(preferLineupJudge(246, 354, 30, 0, 246, 354), true);
    expect(preferLineupJudge(354, 246, 0, 30, 354, 246), false);
    expect(preferLineupJudge(246, 246, 0, 30, 246, 246), true);
  });
  test('actual specialty display rows flag overlap with regular Dutch', () {
    final specialty = specialtyLineupRow({
      'name': 'IDDRC',
      'breed': 'Dutch',
      'entry_count': 8,
      'scope': 'open',
    });
    final regular = <String, dynamic>{'breed_id': 'Dutch', 'species': 'rabbit'};
    final timing = LineupTiming();
    timing.add('1', timingBreedKey(specialty), 8, 60, row: specialty);
    timing.add('2', timingBreedKey(regular), 28, 60, row: regular);
    expect(specialty['timing_overlap'], true);
    expect(regular['timing_overlap'], true);
  });
  test('refresh counts sums varieties and removes stale scratched counts', () {
    final rows = <Map<String, dynamic>>[
      {'section_id': 'a', 'breed_id': 'Dutch', 'entry_count_actual': 10},
      {'section_id': 'b', 'breed_id': 'Dutch', 'entry_count_actual': 1},
      {'is_external_specialty': true, 'entry_count_actual': 28},
    ];
    refreshLineupCounts(rows, [
      {
        'section_id': 'a',
        'breed': 'Dutch',
        'variety': 'Black',
        'entry_count': 5,
      },
      {
        'section_id': 'a',
        'breed': 'Dutch',
        'variety': 'Blue',
        'entry_count': 4,
      },
    ]);
    expect(rows.map((r) => r['entry_count_actual']), [9, 0, 28]);
  });

  test(
    'specialty workload delays following breeds and reduces cross-table overlap',
    () {
      final timing = LineupTiming();
      timing.add('1', 'rabbit|dutch|', 28, 60);
      expect(timing.clocks['1'], 28);
      timing.add('2', 'rabbit|havana|', 12, 60);
      expect(timing.overlap('1', 'rabbit|havana|', 12, 60), 0);
      expect(timing.overlap('3', 'rabbit|havana|', 12, 60), greaterThan(0));
    },
  );
  test('another breed can fill time before the same breed is called again', () {
    final timing = LineupTiming();
    timing.add('1', 'rabbit|havana|', 20, 60);
    expect(timing.overlap('2', 'rabbit|havana|', 20, 60), greaterThan(0));
    timing.add('2', 'rabbit|polish|', 30, 60);
    expect(timing.overlap('2', 'rabbit|havana|', 20, 60), 0);
  });
  test(
    'ten-minute buffer flags both rows, including faster judge estimates',
    () {
      final timing = LineupTiming();
      final first = <String, dynamic>{};
      final second = <String, dynamic>{};
      timing.add('1', 'rabbit|dutch|', 20, 60, row: first);
      timing.add('2', 'rabbit|havana|', 50, 120);
      timing.add('2', 'rabbit|dutch|', 10, 120, row: second);
      expect(second['estimated_start_minutes'], 25);
      expect(second['estimated_end_minutes'], 30);
      expect(first['timing_overlap'], true);
      expect(second['timing_overlap'], true);
    },
  );
  test('same table pairs and zero-count finals do not create overlaps', () {
    final timing = LineupTiming();
    final youth = <String, dynamic>{}, open = <String, dynamic>{};
    timing.add('1', 'rabbit|dutch|', 8, 60, row: youth);
    timing.add('1', 'rabbit|dutch|', 20, 60, row: open);
    timing.add('2', 'rabbit|dutch|', 0, 60);
    expect(youth['timing_overlap'], false);
    expect(open['timing_overlap'], false);
    expect(timing.clocks['1'], 28);
    expect(timing.windows.length, 2);
  });
  test(
    'missing or invalid pace uses declared fallback and identities separate species',
    () {
      expect(judgingRate(null), 60);
      expect(judgingRate({'average_entries_per_hour': 0}), 60);
      expect(judgingRate({'average_entries_per_hour': double.nan}), 60);
      expect(judgingRate({'average_entries_per_hour': 80}), 80);
      expect(
        timingBreedKey({'breed': 'Dutch'}),
        timingBreedKey({'breed_id': 'Dutch', 'species': 'rabbit'}),
      );
      expect(
        timingBreedKey({'breed': 'Dutch', 'species': 'cavy'}),
        isNot(timingBreedKey({'breed': 'Dutch'})),
      );
    },
  );
}
