// lib/screens/admin/closeout/models/base/report_request.dart

bool reportScopeIsNationalShow({
  required bool isNationalShow,
  String? nationalShowSectionId,
  String? sectionId,
  Iterable<String> sectionIds = const <String>[],
}) {
  if (!isNationalShow) return false;
  final nationalId = nationalShowSectionId?.trim() ?? '';
  if (nationalId.isEmpty) return true;
  return sectionId?.trim() == nationalId ||
      sectionIds.any((id) => id.trim() == nationalId);
}

class ReportRequest {
  ReportRequest({
    required this.showId,
    required this.reportName,
    required this.finalizeRunId,
    this.artifactId,
    this.breedName,
    this.clubName,
    this.species,
    this.scope,
    this.showLetter,
    this.scopeLabel,
    this.sectionId,
    this.sectionIds,
    this.showName,
    this.showDate,
    this.sanctionNumber,
    this.exhibitorId,
    this.exhibitorName,
    this.hideZeroBalances = true,
    this.isNationalShow = false,
  });

  final String showId;
  final String reportName;
  final String finalizeRunId;
  final String? artifactId;

  final String? breedName;
  final String? clubName;
  final String? species;
  final String? scope;
  final String? showLetter;
  final String? scopeLabel;
  final String? sectionId;
  final List<String>? sectionIds;
  final String? showName;
  final String? showDate;
  final String? sanctionNumber;

  final String? exhibitorId;
  final String? exhibitorName;

  final bool hideZeroBalances;
  final bool isNationalShow;

  Map<String, dynamic> toJson() {
    return {
      'showId': showId,
      'reportName': reportName,
      'finalizeRunId': finalizeRunId,
      'artifactId': artifactId,
      'breedName': breedName,
      'clubName': clubName,
      'species': species,
      'scope': scope,
      'showLetter': showLetter,
      'scopeLabel': scopeLabel,
      'sectionId': sectionId,
      'sectionIds': sectionIds,
      'showName': showName,
      'showDate': showDate,
      'sanctionNumber': sanctionNumber,
      'exhibitorId': exhibitorId,
      'exhibitorName': exhibitorName,
      'hideZeroBalances': hideZeroBalances,
      'isNationalShow': isNationalShow,
    };
  }

  ReportRequest copyWith({
    String? showId,
    String? reportName,
    String? finalizeRunId,
    String? artifactId,
    String? breedName,
    String? clubName,
    String? species,
    String? scope,
    String? showLetter,
    String? scopeLabel,
    String? sectionId,
    List<String>? sectionIds,
    String? showName,
    String? showDate,
    String? sanctionNumber,
    String? exhibitorId,
    String? exhibitorName,
    bool? hideZeroBalances,
    bool? isNationalShow,
  }) {
    return ReportRequest(
      showId: showId ?? this.showId,
      reportName: reportName ?? this.reportName,
      finalizeRunId: finalizeRunId ?? this.finalizeRunId,
      artifactId: artifactId ?? this.artifactId,
      breedName: breedName ?? this.breedName,
      clubName: clubName ?? this.clubName,
      species: species ?? this.species,
      scope: scope ?? this.scope,
      showLetter: showLetter ?? this.showLetter,
      scopeLabel: scopeLabel ?? this.scopeLabel,
      sectionId: sectionId ?? this.sectionId,
      sectionIds: sectionIds ?? this.sectionIds,
      showName: showName ?? this.showName,
      showDate: showDate ?? this.showDate,
      sanctionNumber: sanctionNumber ?? this.sanctionNumber,
      exhibitorId: exhibitorId ?? this.exhibitorId,
      exhibitorName: exhibitorName ?? this.exhibitorName,
      hideZeroBalances: hideZeroBalances ?? this.hideZeroBalances,
      isNationalShow: isNationalShow ?? this.isNationalShow,
    );
  }
}
