// lib/screens/admin/closeout/models/base/report_request.dart

class ReportRequest {
  ReportRequest({
    required this.showId,
    required this.reportName,
    required this.finalizeRunId,
    this.artifactId,
    this.breedName,
    this.scope,
    this.showLetter,
    this.showName,
    this.showDate,
    this.sanctionNumber,
  });

  final String showId;
  final String reportName;
  final String finalizeRunId;
  final String? artifactId;

  final String? breedName;
  final String? scope;
  final String? showLetter;
  final String? showName;
  final String? showDate;
  final String? sanctionNumber;

  Map<String, dynamic> toJson() {
    return {
      'showId': showId,
      'reportName': reportName,
      'finalizeRunId': finalizeRunId,
      'artifactId': artifactId,
      'breedName': breedName,
      'scope': scope,
      'showLetter': showLetter,
      'showName': showName,
      'showDate': showDate,
      'sanctionNumber': sanctionNumber,
    };
  }

  ReportRequest copyWith({
    String? showId,
    String? reportName,
    String? finalizeRunId,
    String? artifactId,
    String? breedName,
    String? scope,
    String? showLetter,
    String? showName,
    String? showDate,
    String? sanctionNumber,
  }) {
    return ReportRequest(
      showId: showId ?? this.showId,
      reportName: reportName ?? this.reportName,
      finalizeRunId: finalizeRunId ?? this.finalizeRunId,
      artifactId: artifactId ?? this.artifactId,
      breedName: breedName ?? this.breedName,
      scope: scope ?? this.scope,
      showLetter: showLetter ?? this.showLetter,
      showName: showName ?? this.showName,
      showDate: showDate ?? this.showDate,
      sanctionNumber: sanctionNumber ?? this.sanctionNumber,
    );
  }
}