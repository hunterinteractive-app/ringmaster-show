List<List<Map<String, dynamic>>> groupReportDeliveriesForDisplay(
  Iterable<Map<String, dynamic>> rows,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final providerId = (row['provider_message_id'] ?? '').toString().trim();
    final key = providerId.isNotEmpty
        ? 'provider:$providerId'
        : [
            'attempt',
            (row['recipient_email'] ?? '').toString().trim().toLowerCase(),
            (row['subject'] ?? '').toString().trim().toLowerCase(),
            (row['created_at'] ?? '').toString().trim(),
          ].join('|');
    grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
  }
  return grouped.values.toList();
}

const reportDeliveryErrorStatuses = {
  'failed',
  'bounced',
  'complained',
  'suppressed',
};

const reportDeliverySuccessfulStatuses = {
  'sent',
  'delivered',
  'opened',
  'clicked',
};

bool reportDeliveryGroupHasError(List<Map<String, dynamic>> group) {
  return group.any(
    (row) => reportDeliveryErrorStatuses.contains(
      (row['delivery_status'] ?? '').toString().toLowerCase(),
    ),
  );
}

bool reportDeliveryGroupWasSuccessful(List<Map<String, dynamic>> group) {
  return group.any(
    (row) => reportDeliverySuccessfulStatuses.contains(
      (row['delivery_status'] ?? '').toString().toLowerCase(),
    ),
  );
}

String reportDeliveryGroupKey(List<Map<String, dynamic>> group) {
  final row = group.first;
  final providerId = (row['provider_message_id'] ?? '').toString().trim();
  if (providerId.isNotEmpty) return 'provider:$providerId';
  return 'delivery:${row['id']}';
}

Set<String> resolvedReportDeliveryFailureKeys(
  Iterable<List<Map<String, dynamic>>> groups,
) {
  final ordered = groups.toList()
    ..sort(
      (a, b) =>
          _reportDeliveryAttemptAt(b).compareTo(_reportDeliveryAttemptAt(a)),
    );
  final successfulPackageTimes = <String, DateTime>{};
  final resolved = <String>{};

  for (final group in ordered) {
    final packageKey = _reportDeliveryPackageKey(group);
    if (packageKey.isEmpty) continue;
    final attemptAt = _reportDeliveryAttemptAt(group);
    if (reportDeliveryGroupWasSuccessful(group)) {
      successfulPackageTimes[packageKey] = attemptAt;
      continue;
    }
    if (!reportDeliveryGroupHasError(group)) continue;
    final successfulAt = successfulPackageTimes[packageKey];
    if (successfulAt != null && successfulAt.isAfter(attemptAt)) {
      resolved.add(reportDeliveryGroupKey(group));
    }
  }
  return resolved;
}

int compareReportDeliveryGroupsForDisplay(
  List<Map<String, dynamic>> a,
  List<Map<String, dynamic>> b, {
  Set<String> resolvedFailureKeys = const {},
}) {
  final aHasError =
      reportDeliveryGroupHasError(a) &&
      !resolvedFailureKeys.contains(reportDeliveryGroupKey(a));
  final bHasError =
      reportDeliveryGroupHasError(b) &&
      !resolvedFailureKeys.contains(reportDeliveryGroupKey(b));
  if (aHasError != bHasError) return aHasError ? -1 : 1;

  return _reportDeliveryAttemptAt(b).compareTo(_reportDeliveryAttemptAt(a));
}

String _reportDeliveryPackageKey(List<Map<String, dynamic>> group) {
  final artifactIds =
      group
          .map((row) => (row['artifact_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return artifactIds.join('|');
}

DateTime _reportDeliveryAttemptAt(List<Map<String, dynamic>> group) {
  final fallback = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return group
      .map(
        (row) =>
            DateTime.tryParse('${row['sent_at'] ?? row['created_at'] ?? ''}') ??
            fallback,
      )
      .fold(
        fallback,
        (latest, value) => value.isAfter(latest) ? value : latest,
      );
}
