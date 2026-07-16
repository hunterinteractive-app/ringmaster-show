import '../utils/club_report_grouping.dart';

enum CloseoutReportUiStatus {
  generated,
  generating,
  failed,
  needsAttention,
  notApplicable,
}

class ReportArtifactSummary {
  final String id;
  final String? showId;
  final String? finalizeRunId;
  final String reportName;
  final String artifactStatus;
  final String? fileName;
  final String? storageBucket;
  final String? storagePath;
  final String? generatedAt;
  final bool isCurrent;
  final String? scopeKey;
  final List<String> sectionIds;
  final int generation;
  final String? createdAt;
  final int errorCount;
  final Map<String, dynamic> metadata;

  ReportArtifactSummary({
    required this.id,
    this.showId,
    this.finalizeRunId,
    required this.reportName,
    required this.artifactStatus,
    this.fileName,
    this.storageBucket,
    this.storagePath,
    this.generatedAt,
    required this.isCurrent,
    this.scopeKey,
    this.sectionIds = const <String>[],
    this.generation = 1,
    this.createdAt,
    this.errorCount = 0,
    required this.metadata,
  });

  factory ReportArtifactSummary.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : <String, dynamic>{};
    final sectionIds = _stringList(json['section_ids']);
    if (!metadata.containsKey('section_ids') && sectionIds.isNotEmpty) {
      metadata['section_ids'] = sectionIds;
    }
    return ReportArtifactSummary(
      id: (json['id'] ?? '').toString(),
      showId: _nullableText(json['show_id']),
      finalizeRunId: _nullableText(json['finalize_run_id']),
      reportName: (json['report_name'] ?? '').toString(),
      artifactStatus: (json['artifact_status'] ?? 'queued').toString(),
      fileName: _nullableText(json['file_name']),
      storageBucket: _nullableText(json['storage_bucket']),
      storagePath: _nullableText(json['storage_path']),
      generatedAt: _nullableText(json['generated_at']),
      isCurrent: _boolValue(json['is_current']),
      scopeKey: _nullableText(json['scope_key']),
      sectionIds: sectionIds,
      generation: (json['generation'] as num?)?.toInt() ?? 1,
      createdAt: _nullableText(json['created_at']),
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
      metadata: metadata,
    );
  }
}

CloseoutReportUiStatus closeoutReportUiStatus(
  String? artifactStatus, {
  bool expected = true,
}) {
  final normalized = artifactStatus?.trim().toLowerCase() ?? '';
  if (normalized == 'generated') return CloseoutReportUiStatus.generated;
  if (normalized == 'needs attention' || normalized == 'missing') {
    return CloseoutReportUiStatus.needsAttention;
  }
  if (normalized == 'not applicable') {
    return CloseoutReportUiStatus.notApplicable;
  }
  if (const {
    'queued',
    'pending',
    'claimed',
    'running',
    'processing',
    'rendering',
    'uploading',
    'generating',
  }.contains(normalized)) {
    return CloseoutReportUiStatus.generating;
  }
  if (normalized == 'failed' || normalized == 'warning') {
    return CloseoutReportUiStatus.failed;
  }
  return expected
      ? CloseoutReportUiStatus.needsAttention
      : CloseoutReportUiStatus.notApplicable;
}

String closeoutReportStatusLabel(CloseoutReportUiStatus status) =>
    switch (status) {
      CloseoutReportUiStatus.generated => 'Generated',
      CloseoutReportUiStatus.generating => 'Generating',
      CloseoutReportUiStatus.failed => 'Failed',
      CloseoutReportUiStatus.needsAttention => 'Needs attention',
      CloseoutReportUiStatus.notApplicable => 'Not applicable',
    };

int compareCloseoutReportArtifacts(
  ReportArtifactSummary a,
  ReportArtifactSummary b, {
  String? selectedFinalizeRunId,
}) {
  int descending(int left, int right) => right.compareTo(left);
  final selectedRun = selectedFinalizeRunId?.trim() ?? '';
  final runCmp = descending(
    selectedRun.isNotEmpty && a.finalizeRunId == selectedRun ? 1 : 0,
    selectedRun.isNotEmpty && b.finalizeRunId == selectedRun ? 1 : 0,
  );
  if (runCmp != 0) return runCmp;
  final currentCmp = descending(a.isCurrent ? 1 : 0, b.isCurrent ? 1 : 0);
  if (currentCmp != 0) return currentCmp;
  int statusRank(ReportArtifactSummary artifact) =>
      switch (closeoutReportUiStatus(artifact.artifactStatus)) {
        CloseoutReportUiStatus.generated => 4,
        CloseoutReportUiStatus.generating => 3,
        CloseoutReportUiStatus.failed => 2,
        CloseoutReportUiStatus.needsAttention => 1,
        CloseoutReportUiStatus.notApplicable => 0,
      };
  final statusCmp = descending(statusRank(a), statusRank(b));
  if (statusCmp != 0) return statusCmp;
  final generationCmp = descending(a.generation, b.generation);
  if (generationCmp != 0) return generationCmp;
  final generatedCmp = _compareNullableDatesDescending(
    a.generatedAt,
    b.generatedAt,
  );
  if (generatedCmp != 0) return generatedCmp;
  final createdCmp = _compareNullableDatesDescending(a.createdAt, b.createdAt);
  if (createdCmp != 0) return createdCmp;
  return a.id.compareTo(b.id);
}

bool closeoutArtifactMatchesReportTarget(
  ReportArtifactSummary artifact, {
  required String reportName,
  String? exhibitorId,
  String? breedName,
  String? clubName,
  String? scope,
  String? showLetter,
}) {
  if (!artifact.isCurrent || artifact.reportName != reportName) return false;
  final metadata = artifact.metadata;
  final normalizedExhibitorId = exhibitorId?.trim() ?? '';
  if (normalizedExhibitorId.isNotEmpty &&
      (metadata['exhibitor_id'] ?? '').toString().trim() !=
          normalizedExhibitorId) {
    return false;
  }
  final normalizedBreed = _normalizedDimension(breedName);
  if (normalizedBreed.isNotEmpty) {
    final species = (metadata['species'] ?? '').toString().trim().toLowerCase();
    final targets = <String>{
      normalizedBreed,
      _normalizedDimension(
        displayBreedNameForClubReport(
          reportName: reportName,
          breedName: breedName,
          species:
              isCavyClubReportTarget(species: species, breedName: breedName)
              ? 'cavy'
              : '',
        ),
      ),
    };
    if (!targets.contains(_normalizedDimension(metadata['breed_name']))) {
      return false;
    }
  }
  final normalizedClub = _normalizedDimension(clubName);
  if (normalizedClub.isNotEmpty &&
      _normalizedDimension(metadata['club_name']) != normalizedClub) {
    return false;
  }
  final normalizedScope = scope?.trim().toUpperCase() ?? '';
  if (normalizedScope.isNotEmpty &&
      (metadata['scope'] ?? '').toString().trim().toUpperCase() !=
          normalizedScope) {
    return false;
  }
  final normalizedLetter = showLetter?.trim().toUpperCase() ?? '';
  return normalizedLetter.isEmpty ||
      (metadata['show_letter'] ?? '').toString().trim().toUpperCase() ==
          normalizedLetter;
}

String _normalizedDimension(Object? value) => (value?.toString() ?? '')
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

int _compareNullableDatesDescending(String? left, String? right) {
  final leftDate = DateTime.tryParse(left ?? '');
  final rightDate = DateTime.tryParse(right ?? '');
  if (leftDate == null && rightDate == null) return 0;
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  return rightDate.compareTo(leftDate);
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

bool _boolValue(Object? value) {
  if (value is bool) return value;
  return value?.toString().trim().toLowerCase() == 'true';
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
