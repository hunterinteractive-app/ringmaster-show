class BreedJudgedTotalsReportShowInfo {
  const BreedJudgedTotalsReportShowInfo({
    required this.showId,
    required this.showName,
    this.startDate,
    this.endDate,
    this.locationName = '',
    this.secretaryName,
    this.secretaryEmail,
    this.secretaryPhone,
  });

  final String showId;
  final String showName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String locationName;
  final String? secretaryName;
  final String? secretaryEmail;
  final String? secretaryPhone;
}

class BreedJudgedTotalsReportData {
  const BreedJudgedTotalsReportData({
    required this.show,
    required this.generatedAt,
    required this.scopeLabel,
    required this.breedRows,
    required this.furRows,
    this.showBreakdowns = const <BreedJudgedTotalsShowBreakdown>[],
  });

  final BreedJudgedTotalsReportShowInfo show;
  final DateTime generatedAt;
  final String scopeLabel;
  final List<BreedJudgedTotalsReportRow> breedRows;
  final List<BreedJudgedTotalsReportRow> furRows;
  final List<BreedJudgedTotalsShowBreakdown> showBreakdowns;

  int get totalBreedJudged =>
      breedRows.fold<int>(0, (sum, row) => sum + row.totalJudged);

  int get totalFurJudged =>
      furRows.fold<int>(0, (sum, row) => sum + row.totalJudged);

  int get totalJudged => totalBreedJudged + totalFurJudged;
}

class BreedJudgedTotalsReportRow {
  const BreedJudgedTotalsReportRow({
    required this.breed,
    required this.species,
    required this.totalJudged,
  });

  final String breed;
  final String species;
  final int totalJudged;

  BreedJudgedTotalsReportRow copyWith({int? totalJudged}) {
    return BreedJudgedTotalsReportRow(
      breed: breed,
      species: species,
      totalJudged: totalJudged ?? this.totalJudged,
    );
  }
}

class BreedJudgedTotalsShowBreakdown {
  const BreedJudgedTotalsShowBreakdown({
    required this.label,
    required this.breedRows,
    required this.furRows,
  });

  final String label;
  final List<BreedJudgedTotalsReportRow> breedRows;
  final List<BreedJudgedTotalsReportRow> furRows;

  int get totalBreedJudged =>
      breedRows.fold<int>(0, (sum, row) => sum + row.totalJudged);

  int get totalFurJudged =>
      furRows.fold<int>(0, (sum, row) => sum + row.totalJudged);

  int get totalJudged => totalBreedJudged + totalFurJudged;
}

class BreedJudgedTotalsAggregation {
  const BreedJudgedTotalsAggregation({
    required this.breedRows,
    required this.furRows,
  });

  final List<BreedJudgedTotalsReportRow> breedRows;
  final List<BreedJudgedTotalsReportRow> furRows;
}
