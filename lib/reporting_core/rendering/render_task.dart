final class RenderTask {
  const RenderTask({
    required this.id,
    required this.artifactId,
    required this.showId,
    required this.finalizeRunId,
    required this.scopeKey,
    required this.attemptCount,
    required this.maxAttempts,
    required this.payload,
    this.claimedAt,
  });

  factory RenderTask.fromJson(Map<String, dynamic> json) {
    final payload = _map(json['payload']);
    return RenderTask(
      id: _required(json, 'id'),
      artifactId: _required(json, 'report_artifact_id'),
      showId: _required(json, 'show_id'),
      finalizeRunId: _required(json, 'finalize_run_id'),
      scopeKey: _required(json, 'scope_key'),
      attemptCount: _integer(json['attempt_count']),
      maxAttempts: _integer(json['max_attempts']),
      payload: payload,
      claimedAt: DateTime.tryParse(json['claimed_at']?.toString() ?? ''),
    );
  }

  final String id;
  final String artifactId;
  final String showId;
  final String finalizeRunId;
  final String scopeKey;
  final int attemptCount;
  final int maxAttempts;
  final Map<String, dynamic> payload;
  final DateTime? claimedAt;
}

final class RenderArtifact {
  const RenderArtifact({
    required this.id,
    required this.showId,
    required this.finalizeRunId,
    required this.scopeKey,
    required this.reportName,
    required this.sectionIds,
    required this.metadata,
    required this.storageBucket,
    required this.storagePath,
    required this.generation,
  });

  factory RenderArtifact.fromJson(Map<String, dynamic> json) {
    return RenderArtifact(
      id: _required(json, 'id'),
      showId: _required(json, 'show_id'),
      finalizeRunId: _required(json, 'finalize_run_id'),
      scopeKey: _required(json, 'scope_key'),
      reportName: _required(json, 'report_name'),
      sectionIds: _strings(json['section_ids']),
      metadata: _map(json['metadata']),
      storageBucket: _required(json, 'storage_bucket'),
      storagePath: _required(json, 'storage_path'),
      generation: _integer(json['generation']),
    );
  }

  final String id;
  final String showId;
  final String finalizeRunId;
  final String scopeKey;
  final String reportName;
  final List<String> sectionIds;
  final Map<String, dynamic> metadata;
  final String storageBucket;
  final String storagePath;
  final int generation;

  void validateFor(RenderTask task, {String? configuredBucket}) {
    if (id != task.artifactId ||
        showId != task.showId ||
        finalizeRunId != task.finalizeRunId ||
        scopeKey != task.scopeKey) {
      throw const RenderFailure.permanent(
        'scope_mismatch',
        'The queued report no longer matches its artifact scope.',
      );
    }
    if (sectionIds.isEmpty || metadata['scope_key'] != scopeKey) {
      throw const RenderFailure.permanent(
        'invalid_scope',
        'The report artifact has incomplete structured scope metadata.',
      );
    }
    if (task.payload['report_name']?.toString() != reportName ||
        _integer(task.payload['generation']) != generation) {
      throw const RenderFailure.permanent(
        'stale_task',
        'The render task references a stale artifact generation.',
      );
    }
    final artifactSections = sectionIds.toSet();
    if (!_sameSet(
          _strings(task.payload['section_ids']).toSet(),
          artifactSections,
        ) ||
        !_sameSet(
          _strings(metadata['section_ids']).toSet(),
          artifactSections,
        )) {
      throw const RenderFailure.permanent(
        'section_scope_mismatch',
        'The queued report section scope is inconsistent.',
      );
    }
    if (configuredBucket != null && configuredBucket != storageBucket) {
      throw const RenderFailure.permanent(
        'storage_bucket_mismatch',
        'The configured Storage bucket does not match the artifact.',
      );
    }
    final expectedPath =
        'shows/$showId/reports/versions/$finalizeRunId/artifacts/$id/generation-$generation/report.pdf';
    if (storageBucket.isEmpty || storagePath != expectedPath) {
      throw const RenderFailure.permanent(
        'invalid_storage_location',
        'The artifact Storage location is invalid.',
      );
    }
  }
}

final class RenderFailure implements Exception {
  const RenderFailure(this.category, this.userMessage, this.diagnostic)
    : retryable = true;

  const RenderFailure.permanent(
    this.category,
    this.userMessage, [
    this.diagnostic = '',
  ]) : retryable = false;

  final String category;
  final String userMessage;
  final String diagnostic;
  final bool retryable;

  @override
  String toString() => diagnostic.isEmpty ? userMessage : diagnostic;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const <String>[];

String _required(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing required field: $key');
  return value;
}

int _integer(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
