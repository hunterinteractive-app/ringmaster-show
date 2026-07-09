// lib/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart

class SweepstakesReportData {
  final String showId;
  final String breedName;
  final String scope;
  final String showLetter;
  final String ruleSource;
  final String verificationStatus;
  final String engineType;
  final String species;

  final String arbaSanction;
  final String nationalClubSanction;
  final String breedSanctionNumber;
  final String breedClubName;
  final String hostClubName;
  final String showLocation;
  final String secretaryName;
  final String secretaryEmail;
  final String secretaryPhone;

  final List<SweepstakesReportRow> rows;
  final List<SweepstakesReportSection> sections;
  final List<SweepstakesTopBreedRow> topBreedRows;
  final bool noResultsFound;
  final bool isNationalShow;

  const SweepstakesReportData({
    required this.showId,
    required this.breedName,
    required this.scope,
    required this.showLetter,
    required this.ruleSource,
    required this.verificationStatus,
    required this.engineType,
    required this.rows,
    this.species = '',
    this.arbaSanction = '',
    this.nationalClubSanction = '',
    this.breedSanctionNumber = '',
    this.breedClubName = '',
    this.hostClubName = '',
    this.showLocation = '',
    this.secretaryName = '',
    this.secretaryEmail = '',
    this.secretaryPhone = '',
    this.sections = const [],
    this.topBreedRows = const [],
    this.noResultsFound = false,
    this.isNationalShow = false,
  });

  bool get isProvisional =>
      verificationStatus.trim().toUpperCase() != 'VERIFIED';

  bool get showClassPoints => rows.any((r) => r.classPoints != 0);
  bool get showVarietyPoints => rows.any((r) => r.varietyPoints != 0);
  bool get showGroupPoints => rows.any((r) => r.groupPoints != 0);
  bool get showBobPoints => rows.any((r) => r.bobPoints != 0);
  bool get showBisPoints => rows.any((r) => r.bisPoints != 0);
  bool get showFurPoints => rows.any((r) => r.furPoints != 0);
  bool get showPointBreakdown =>
      showClassPoints ||
      showVarietyPoints ||
      showGroupPoints ||
      showBobPoints ||
      showBisPoints ||
      showFurPoints;
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
  final String exhibitorAddress;
  final double classPoints;
  final double arbaClassPoints;
  final double varietyPoints;
  final double groupPoints;
  final double bobPoints;
  final double bisPoints;
  final double furPoints;
  final double totalPoints;

  double get otherPoints => varietyPoints + groupPoints + bisPoints;

  const SweepstakesReportRow({
    required this.rank,
    required this.exhibitorName,
    required this.exhibitorAddress,
    required this.classPoints,
    required this.arbaClassPoints,
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
      exhibitorAddress: (map['exhibitor_address'] ?? '').toString(),
      classPoints: asDouble(map['class_points']),
      arbaClassPoints: asDouble(map['arba_class_points']),
      varietyPoints: asDouble(map['variety_points']),
      groupPoints: asDouble(map['group_points']),
      bobPoints: asDouble(map['bob_points']),
      bisPoints: asDouble(map['bis_points']),
      furPoints: asDouble(map['fur_points']),
      totalPoints: asDouble(map['total_points']),
    );
  }
}

class SweepstakesTopBreedRow {
  final int rank;
  final String breedName;
  final int entryCount;

  const SweepstakesTopBreedRow({
    required this.rank,
    required this.breedName,
    required this.entryCount,
  });

  factory SweepstakesTopBreedRow.fromMap(Map<String, dynamic> map) {
    return SweepstakesTopBreedRow(
      rank: ((map['rank'] ?? 0) as num).toInt(),
      breedName: (map['breed_name'] ?? '').toString(),
      entryCount: ((map['entry_count'] ?? 0) as num).toInt(),
    );
  }
}
