import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/superintendent/lineup_timing.dart';

void main() {
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
