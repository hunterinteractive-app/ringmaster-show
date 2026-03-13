class ReportRequest {
  ReportRequest({
    required this.showId,
    required this.reportName,
    required this.finalizeRunId,
    this.artifactId,
  });

  final String showId;
  final String reportName;
  final String finalizeRunId;
  final String? artifactId;
}