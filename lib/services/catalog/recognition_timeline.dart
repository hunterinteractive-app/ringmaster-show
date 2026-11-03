/// Recognition is dated by a section's local judging date, never by entry or
/// report-generation time. Names retain legacy COD markers for old records.
enum RecognitionStatus {
  cod('COD'),
  recognized('Recognized'),
  retired('Retired'),
  unrecognized('Judging date required');

  const RecognitionStatus(this.label);
  final String label;
  bool get canEarnLeg => this == recognized;
  bool allowsAward(String award) =>
      this == recognized ||
      (this == cod && const {'BOV', 'BOSV'}.contains(award.toUpperCase()));
}

String recognitionKey(String name) => name
    .replaceAll(RegExp(r'\s*\(\s*COD\s*\)|\bCOD\b', caseSensitive: false), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

class RecognitionTransition {
  const RecognitionTransition({
    required this.id,
    required this.varietyName,
    required this.status,
    required this.effectiveDate,
    this.sourceNote = '',
  });
  final String id;
  final String varietyName;
  final RecognitionStatus status;
  final DateTime effectiveDate;
  final String sourceNote;

  factory RecognitionTransition.fromJson(Map<String, dynamic> row) =>
      RecognitionTransition(
        id: row['id'].toString(),
        varietyName: (row['variety_name'] ?? '').toString(),
        status: RecognitionStatus.values.byName(row['status'].toString()),
        effectiveDate: DateTime.parse(row['effective_date'].toString()),
        sourceNote: (row['source_note'] ?? '').toString(),
      );
}

RecognitionStatus resolveRecognitionStatus({
  required String breedName,
  String varietyName = '',
  required DateTime? judgingDate,
  required Iterable<RecognitionTransition> transitions,
}) {
  final applicable = transitions
      .where(
        (event) =>
            event.varietyName.isEmpty ||
            recognitionKey(event.varietyName) == recognitionKey(varietyName),
      )
      .toList();
  if (judgingDate == null && applicable.isNotEmpty) {
    return RecognitionStatus.unrecognized;
  }
  RecognitionStatus statusFor(String name, bool breed) {
    final matches =
        applicable
            .where(
              (event) =>
                  (breed
                      ? event.varietyName.isEmpty
                      : event.varietyName.isNotEmpty) &&
                  judgingDate != null &&
                  !event.effectiveDate.isAfter(
                    DateTime(
                      judgingDate.year,
                      judgingDate.month,
                      judgingDate.day,
                    ),
                  ),
            )
            .toList()
          ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    if (matches.isNotEmpty) return matches.first.status;
    return RegExp(r'\bCOD\b', caseSensitive: false).hasMatch(name)
        ? RecognitionStatus.cod
        : RecognitionStatus.recognized;
  }

  final statuses = [statusFor(breedName, true), statusFor(varietyName, false)];
  if (statuses.contains(RecognitionStatus.retired)) {
    return RecognitionStatus.retired;
  }
  if (statuses.contains(RecognitionStatus.cod)) return RecognitionStatus.cod;
  return RecognitionStatus.recognized;
}

/// Presentation only: never rename stored keys or historical entry identities.
String recognitionDisplayName(String name, RecognitionStatus status) {
  if (status == RecognitionStatus.unrecognized) return name.trim();
  final plain = name
      .replaceAll(RegExp(r'\s*\(\s*COD\s*\)|\bCOD\b', caseSensitive: false), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  return status == RecognitionStatus.cod ? '$plain (COD)' : plain;
}
