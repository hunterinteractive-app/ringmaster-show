// lib/screens/admin/closeout/models/exhibitor/best_display_report_data.dart

class BestDisplayReportData {
  final String showId;
  final String showName;
  final String showDate;
  final String showLocation;
  final int minimumEntriesRequired;
  final List<BestDisplaySectionData> sections;
  final List<BestDisplayBreedSectionData> breedSections;

  const BestDisplayReportData({
    required this.showId,
    required this.showName,
    required this.showDate,
    required this.showLocation,
    required this.minimumEntriesRequired,
    required this.sections,
    this.breedSections = const <BestDisplayBreedSectionData>[],
  });

  bool get isEmpty => sections.every((section) => section.rows.isEmpty);

  int get totalStandingRows => sections.fold<int>(
        0,
        (total, section) => total + section.rows.length,
      );

  List<BestDisplayStandingRow> get allRows => sections
      .expand((section) => section.rows)
      .toList(growable: false);
}

class BestDisplayBreedSectionData {
  final String sectionId;
  final String scope;
  final String showLetter;
  final String species;
  final String breedName;
  final List<BestDisplayBreedStandingRow> rows;

  const BestDisplayBreedSectionData({
    required this.sectionId,
    required this.scope,
    required this.showLetter,
    required this.species,
    required this.breedName,
    required this.rows,
  });

  String get displayName {
    final normalizedScope = scope.trim().toLowerCase();
    final scopeLabel = normalizedScope.isEmpty
        ? 'Show'
        : '${normalizedScope[0].toUpperCase()}${normalizedScope.substring(1)}';
    final speciesLabel = species.toUpperCase() == 'CAVY' ? 'Cavies' : 'Rabbits';
    final letter = showLetter.trim();
    final sectionLabel = letter.isEmpty ? scopeLabel : '$scopeLabel $letter';

    return '$sectionLabel — $speciesLabel — $breedName';
  }

  BestDisplayBreedStandingRow? get winner {
    for (final row in rows) {
      if (row.isWinner) return row;
    }
    return null;
  }

  bool get hasWinner => winner != null;

  bool get hasFirstPlaceTie => rows.any(
        (row) => row.isEligible && row.rank == 1 && row.isTied,
      );
}

class BestDisplayBreedStandingRow {
  final String exhibitorId;
  final String exhibitorName;
  final int qualifyingEntryCount;
  final int pointEarningEntryCount;
  final double displayPoints;
  final int minimumEntriesRequired;
  final int? rank;
  final bool isEligible;
  final bool isTied;
  final bool isWinner;

  const BestDisplayBreedStandingRow({
    required this.exhibitorId,
    required this.exhibitorName,
    required this.qualifyingEntryCount,
    required this.pointEarningEntryCount,
    required this.displayPoints,
    required this.minimumEntriesRequired,
    required this.rank,
    required this.isEligible,
    required this.isTied,
    required this.isWinner,
  });

  String get rankLabel {
    if (!isEligible || rank == null) return 'Not eligible';
    return rank.toString();
  }

  String get statusLabel {
    if (!isEligible) {
      return '$qualifyingEntryCount of $minimumEntriesRequired entries';
    }
    if (isWinner) return 'Winner';
    if (rank == 1 && isTied) return 'First-place tie';
    if (isTied) return 'Tied';
    return 'Eligible';
  }
}

class BestDisplaySectionData {
  final String sectionId;
  final String scope;
  final String showLetter;
  final String species;
  final List<BestDisplayStandingRow> rows;

  const BestDisplaySectionData({
    required this.sectionId,
    required this.scope,
    required this.showLetter,
    required this.species,
    required this.rows,
  });

  String get displayName {
    final scopeLabel = scope.trim().isEmpty ? 'Show' : _titleCase(scope);
    final letterLabel = showLetter.trim();
    final speciesLabel = species.trim().isEmpty
        ? 'Animals'
        : species.toUpperCase() == 'CAVY'
            ? 'Cavies'
            : 'Rabbits';

    if (letterLabel.isEmpty) {
      return '$scopeLabel — $speciesLabel';
    }

    return '$scopeLabel $letterLabel — $speciesLabel';
  }

  BestDisplayStandingRow? get winner {
    for (final row in rows) {
      if (row.isWinner) return row;
    }
    return null;
  }

  bool get hasWinner => winner != null;

  bool get hasFirstPlaceTie => rows.any(
        (row) =>
            row.isEligible &&
            row.eligibleRank == 1 &&
            row.isTied,
      );

  static String _titleCase(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}

class BestDisplayStandingRow {
  final String showId;
  final String sectionId;
  final String scope;
  final String showLetter;
  final String species;

  final int standingRank;
  final int? eligibleRank;

  final String exhibitorId;
  final String exhibitorName;

  final int qualifyingEntryCount;
  final int pointEarningEntryCount;

  final int firstPlaceCount;
  final int secondPlaceCount;
  final int thirdPlaceCount;
  final int fourthPlaceCount;
  final int fifthPlaceCount;

  final double displayPoints;
  final int minimumEntriesRequired;

  final bool isEligible;
  final bool isTied;
  final bool isWinner;

  const BestDisplayStandingRow({
    required this.showId,
    required this.sectionId,
    required this.scope,
    required this.showLetter,
    required this.species,
    required this.standingRank,
    required this.eligibleRank,
    required this.exhibitorId,
    required this.exhibitorName,
    required this.qualifyingEntryCount,
    required this.pointEarningEntryCount,
    required this.firstPlaceCount,
    required this.secondPlaceCount,
    required this.thirdPlaceCount,
    required this.fourthPlaceCount,
    required this.fifthPlaceCount,
    required this.displayPoints,
    required this.minimumEntriesRequired,
    required this.isEligible,
    required this.isTied,
    required this.isWinner,
  });

  factory BestDisplayStandingRow.fromJson(Map<String, dynamic> json) {
    return BestDisplayStandingRow(
      showId: _string(json['show_id']),
      sectionId: _string(json['section_id']),
      scope: _string(json['scope']).toUpperCase(),
      showLetter: _string(json['show_letter']).toUpperCase(),
      species: _string(json['species']).toUpperCase(),
      standingRank: _int(json['standing_rank']),
      eligibleRank: _nullableInt(json['eligible_rank']),
      exhibitorId: _string(json['exhibitor_id']),
      exhibitorName: _string(json['exhibitor_name'], fallback: 'Unknown Exhibitor'),
      qualifyingEntryCount: _int(json['qualifying_entry_count']),
      pointEarningEntryCount: _int(json['point_earning_entry_count']),
      firstPlaceCount: _int(json['first_place_count']),
      secondPlaceCount: _int(json['second_place_count']),
      thirdPlaceCount: _int(json['third_place_count']),
      fourthPlaceCount: _int(json['fourth_place_count']),
      fifthPlaceCount: _int(json['fifth_place_count']),
      displayPoints: _double(json['display_points']),
      minimumEntriesRequired: _int(
        json['minimum_entries_required'],
        fallback: 6,
      ),
      isEligible: _bool(json['is_eligible']),
      isTied: _bool(json['is_tied']),
      isWinner: _bool(json['is_winner']),
    );
  }

  String get rankLabel {
    if (!isEligible || eligibleRank == null) return 'Not eligible';
    return eligibleRank.toString();
  }

  String get statusLabel {
    if (!isEligible) {
      return '$qualifyingEntryCount of $minimumEntriesRequired entries';
    }
    if (isWinner) return 'Winner';
    if (eligibleRank == 1 && isTied) return 'First-place tie';
    if (isTied) return 'Tied';
    return 'Eligible';
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double _double(Object? value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _bool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    switch (value?.toString().trim().toLowerCase()) {
      case 'true':
      case 't':
      case '1':
      case 'yes':
      case 'y':
        return true;
      case 'false':
      case 'f':
      case '0':
      case 'no':
      case 'n':
        return false;
      default:
        return fallback;
    }
  }
}