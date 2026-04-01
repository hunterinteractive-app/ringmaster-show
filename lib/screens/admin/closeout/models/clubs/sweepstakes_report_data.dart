// lib/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart

class SweepstakesReportData {
  const SweepstakesReportData({
    required this.showId,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.ruleSource,
    required this.verificationStatus,
    required this.engineType,
    required this.rows,
  });

  final String showId;
  final String breedName;
  final String scope;
  final String showLetter;
  final String ruleSource;
  final String verificationStatus;
  final String engineType;
  final List<SweepstakesReportRow> rows;

  bool get isProvisional => verificationStatus.toUpperCase() != 'VERIFIED';

  bool get showVarietyPoints =>
      rows.any((r) => (r.varietyPoints).abs() > 0.0001);

  bool get showGroupPoints =>
      rows.any((r) => (r.groupPoints).abs() > 0.0001);

  bool get showBobPoints =>
      rows.any((r) => (r.bobPoints).abs() > 0.0001);

  bool get showBisPoints =>
      rows.any((r) => (r.bisPoints).abs() > 0.0001);

  bool get showFurPoints =>
      rows.any((r) => (r.furPoints).abs() > 0.0001);

  String get disclaimer =>
      'These sweepstakes totals were calculated using RingMaster Show rules currently configured for this breed and show letter. Please review the breakdown and verify calculations with your club before posting official standings.';
}

class SweepstakesReportRow {
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

  final int rank;
  final String exhibitorName;
  final double classPoints;
  final double varietyPoints;
  final double groupPoints;
  final double bobPoints;
  final double bisPoints;
  final double furPoints;
  final double totalPoints;

  factory SweepstakesReportRow.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return SweepstakesReportRow(
      rank: toInt(map['rank']),
      exhibitorName: (map['exhibitor_name'] ?? '').toString(),
      classPoints: toDouble(map['class_points']),
      varietyPoints: toDouble(map['variety_points']),
      groupPoints: toDouble(map['group_points']),
      bobPoints: toDouble(map['bob_points']),
      bisPoints: toDouble(map['bis_points']),
      furPoints: toDouble(map['fur_points']),
      totalPoints: toDouble(map['total_points']),
    );
  }
}