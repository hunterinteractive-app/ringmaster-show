class SweepstakesReportData {
  final String showId;
  final String breedName;
  final String scope;
  final String ruleSource;
  final String verificationStatus;
  final String engineType;
  final List<SweepstakesReportRow> rows;

  const SweepstakesReportData({
    required this.showId,
    required this.breedName,
    required this.scope,
    required this.ruleSource,
    required this.verificationStatus,
    required this.engineType,
    required this.rows,
  });

  bool get showVarietyPoints =>
      rows.any((r) => r.varietyPoints != 0);

  bool get showGroupPoints =>
      rows.any((r) => r.groupPoints != 0);

  bool get showBobPoints =>
      rows.any((r) => r.bobPoints != 0);

  bool get showBisPoints =>
      rows.any((r) => r.bisPoints != 0);

  bool get showFurPoints =>
      rows.any((r) => r.furPoints != 0);

  bool get isProvisional =>
      verificationStatus.toUpperCase() == 'PROVISIONAL' ||
      ruleSource.toUpperCase() == 'INFERRED' ||
      ruleSource.toUpperCase() == 'DEFAULT';

  String get disclaimer =>
      'These sweepstakes totals were calculated using RingMaster’s current rules profile for this breed. '
      'If your club uses different rules or you wish to review how points are calculated, '
      'please contact support@ringmasterone.com so we can verify and update the profile.';
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
    double toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    return SweepstakesReportRow(
      rank: (map['rank'] as num?)?.toInt() ?? 0,
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