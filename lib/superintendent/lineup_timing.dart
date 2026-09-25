import 'dart:math' as math;

/// Relative estimates: tables start together, with no invented waiting periods.
/// A ten-minute gap allows for transfers and modest variations in judging pace.
const lineupTransferMinutes = 10.0;
const defaultJudgingRate = 60.0;

String timingBreedKey(Map<String, dynamic> row) {
  final breed = (row['breed_id'] ?? row['breed'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final variety = breed == 'commercial'
      ? (row['variety_key'] ?? row['variety'] ?? '')
            .toString()
            .trim()
            .toLowerCase()
      : '';
  return '${(row['species'] ?? 'rabbit').toString().toLowerCase()}|$breed|$variety';
}

double judgingRate(Map<String, dynamic>? row) {
  final n = (row?['average_entries_per_hour'] as num?)?.toDouble();
  return n != null && n.isFinite && n > 0 ? n : defaultJudgingRate;
}

class BreedWindow {
  BreedWindow(this.table, this.breed, this.start, this.end, {this.row});
  final String table, breed;
  final double start, end;
  final Map<String, dynamic>? row;
}

class LineupTiming {
  final clocks = <String, double>{};
  final windows = <BreedWindow>[];

  double duration(int count, double rate) => math.max(0, count) * 60 / rate;

  double overlap(String table, String breed, int count, double rate) {
    final start = clocks[table] ?? 0;
    final end = start + duration(count, rate);
    if (end <= start) return 0;
    return windows
        .where((w) => w.table != table && w.breed == breed)
        .fold<double>(
          0,
          (sum, w) =>
              sum +
              math.max(
                0,
                math.min(
                      end + lineupTransferMinutes,
                      w.end + lineupTransferMinutes,
                    ) -
                    math.max(start, w.start),
              ),
        );
  }

  void add(
    String table,
    String breed,
    int count,
    double rate, {
    Map<String, dynamic>? row,
  }) {
    final start = clocks[table] ?? 0;
    final end = start + duration(count, rate);
    clocks[table] = end;
    if (row != null) {
      row['estimated_start_minutes'] = start.round();
      row['estimated_end_minutes'] = end.round();
      row['timing_overlap'] = false;
    }
    if (end <= start) return;
    final window = BreedWindow(table, breed, start, end, row: row);
    for (final previous in windows) {
      if (previous.table != table &&
          previous.breed == breed &&
          start < previous.end + lineupTransferMinutes &&
          previous.start < end + lineupTransferMinutes) {
        row?['timing_overlap'] = true;
        previous.row?['timing_overlap'] = true;
      }
    }
    windows.add(window);
  }
}
