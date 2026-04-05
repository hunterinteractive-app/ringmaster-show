// lib/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart

class SweepstakesReportData {
  final String showId;
  final String breedName;
  final String scope;
  final String showLetter;
  final String ruleSource;
  final String verificationStatus;
  final String engineType;
  final List<SweepstakesReportRow> rows;
  final List<SweepstakesReportSection> sections;
  final bool noResultsFound;

  const SweepstakesReportData({
    required this.showId,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.ruleSource,
    required this.verificationStatus,
    required this.engineType,
    required this.rows,
    this.sections = const [],
    this.noResultsFound = false,
  });

  bool get isProvisional =>
      verificationStatus.trim().toUpperCase() != 'VERIFIED';

  bool get showVarietyPoints => rows.any((r) => r.varietyPoints != 0);
  bool get showGroupPoints => rows.any((r) => r.groupPoints != 0);
  bool get showBobPoints => rows.any((r) => r.bobPoints != 0);
  bool get showBisPoints => rows.any((r) => r.bisPoints != 0);
  bool get showFurPoints => rows.any((r) => r.furPoints != 0);
}

class SweepstakesReportSection {
  final String showLetter;
  final String ruleSource;
  final String verificationStatus;
  final String engineType;
  final List<SweepstakesReportRow> rows;
  final bool noResultsFound;

  const SweepstakesReportSection({
    required this.showLetter,
    required this.ruleSource,
    required this.verificationStatus,
    required this.engineType,
    required this.rows,
    this.noResultsFound = false,
  });
}

class SweepstakesReportRow {
  final int rank;
  final String exhibitorName;
  final double classPoints;
  final double varietyPoints;
  final double groupPoints;
  final double bobPoints;
  final double bisPoints;
  final double furPoints;
  final double totalPoints;

  const SweepstakesReportRow({
    required this.rank,
    required this.exhibitorName,
    required this.classPoints,
    required this.varietyPoints,
    required this.groupPoints,
    required this.bobPoints,
    required this.bisPoints,
    required this.furPoints,
    required this.totalPoints,
  });

  factory SweepstakesReportRow.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString()) ?? 0;
    }

    return SweepstakesReportRow(
      rank: ((map['rank'] ?? 0) as num).toInt(),
      exhibitorName: (map['exhibitor_name'] ?? '').toString(),
      classPoints: asDouble(map['class_points']),
      varietyPoints: asDouble(map['variety_points']),
      groupPoints: asDouble(map['group_points']),
      bobPoints: asDouble(map['bob_points']),
      bisPoints: asDouble(map['bis_points']),
      furPoints: asDouble(map['fur_points']),
      totalPoints: asDouble(map['total_points']),
    );
  }
}