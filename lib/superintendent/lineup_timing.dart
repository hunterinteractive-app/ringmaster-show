import 'dart:math' as math;

/// Relative estimates honor explicit planned starts without inventing waits.
/// A ten-minute gap allows for transfers and modest variations in judging pace.
const lineupTransferMinutes = 10.0;
const defaultJudgingRate = 25.0;

String timingBreedKey(Map<String, dynamic> row) {
  final breed =
      (row['is_external_specialty'] == true
              ? (row['breed'] ?? '')
              : (row['breed_id'] ?? row['breed'] ?? ''))
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

/// Stored in the existing judge marker notes so it follows the judge block.
int plannedStartMinutes(Map<String, dynamic> row) {
  final match = RegExp(
    r'^Planned start: (\d+) minutes after show start\.$',
    multiLine: true,
  ).firstMatch((row['notes'] ?? '').toString());
  return int.tryParse(match?.group(1) ?? '') ?? 0;
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

  void startAt(String table, int minutes) {
    clocks[table] = math.max(clocks[table] ?? 0, minutes.toDouble());
  }

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

/// Use current entries, not the snapshot saved when the lineup was assigned.
void refreshLineupCounts(
  List<Map<String, dynamic>> assignments,
  List<Map<String, dynamic>> counts,
) {
  for (final row in assignments) {
    if (row['is_judge_change'] == true ||
        row['breed_id'] == '__judge_change__' ||
        row['is_external_specialty'] == true ||
        row['is_award_plan'] == true) {
      continue;
    }
    final matches = counts.where(
      (count) =>
          count['section_id'] == row['section_id'] &&
          timingBreedKey(count) == timingBreedKey(row),
    );
    row['entry_count_actual'] = matches.fold<int>(
      0,
      (total, count) => total + ((count['entry_count'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Timing is a tie-breaker; it must not overload one judge to avoid a call.
bool preferLineupJudge(
  int load,
  int bestLoad,
  double overlap,
  double bestOverlap,
  double preference,
  double bestPreference,
) {
  if (load != bestLoad) return load < bestLoad;
  if (overlap != bestOverlap) return overlap < bestOverlap;
  return preference < bestPreference;
}
