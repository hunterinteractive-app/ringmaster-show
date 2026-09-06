class FinalAwardReadinessIssue {
  final String title;
  final String message;

  const FinalAwardReadinessIssue({required this.title, required this.message});
}

int _count(Map<String, dynamic> readiness, String key) =>
    int.tryParse(readiness[key]?.toString() ?? '') ?? 0;

List<Map<String, dynamic>> _details(
  Map<String, dynamic> readiness,
  String key,
) {
  final raw = readiness[key];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<FinalAwardReadinessIssue> blockingFinalAwardReadinessIssues(
  Map<String, dynamic> readiness,
) {
  final issues = <FinalAwardReadinessIssue>[];

  final missingCount = _count(readiness, 'missing_final_award_count');
  final missingDetails = _details(readiness, 'missing_final_awards');
  for (final detail in missingDetails) {
    final section = (detail['section_label'] ?? 'This section').toString();
    final award =
        (detail['award_label'] ?? detail['award_code'] ?? 'Final award')
            .toString();
    issues.add(
      FinalAwardReadinessIssue(
        title: 'Missing $award',
        message: '$section requires $award before results are complete.',
      ),
    );
  }
  final missingWithoutDetails = missingCount - missingDetails.length;
  if (missingWithoutDetails > 0) {
    issues.add(
      FinalAwardReadinessIssue(
        title: 'Missing final awards',
        message:
            '$missingWithoutDetails required final award${missingWithoutDetails == 1 ? ' is' : 's are'} still missing.',
      ),
    );
  }

  final invalidCount = _count(readiness, 'invalid_final_award_count');
  final invalidDetails = _details(readiness, 'invalid_final_awards');
  for (final detail in invalidDetails) {
    final section = (detail['section_label'] ?? 'This section').toString();
    final award =
        (detail['award_label'] ?? detail['award_code'] ?? 'Final award')
            .toString();
    final reason = (detail['reason'] ?? '').toString().trim();
    issues.add(
      FinalAwardReadinessIssue(
        title: 'Invalid $award',
        message: reason.isEmpty
            ? '$section has an invalid $award.'
            : '$section — $reason',
      ),
    );
  }
  final invalidWithoutDetails = invalidCount - invalidDetails.length;
  if (invalidWithoutDetails > 0) {
    issues.add(
      FinalAwardReadinessIssue(
        title: 'Invalid final awards',
        message:
            '$invalidWithoutDetails final award selection${invalidWithoutDetails == 1 ? ' is' : 's are'} invalid.',
      ),
    );
  }

  final duplicateCount = _count(readiness, 'duplicate_final_award_count');
  if (duplicateCount > 0) {
    issues.add(
      FinalAwardReadinessIssue(
        title: 'Duplicate final award winners',
        message:
            '$duplicateCount duplicate final award conflict${duplicateCount == 1 ? ' needs' : 's need'} correction.',
      ),
    );
  }

  return issues;
}
