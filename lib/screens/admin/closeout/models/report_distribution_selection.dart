class CloseoutReportSelection {
  final String? group;
  final String? reportName;
  final String? arbaArtifactId;
  final String? exhibitorId;
  final String? breedName;
  final String? clubName;
  final String? showLetter;
  final String? scope;

  const CloseoutReportSelection({
    this.group,
    this.reportName,
    this.arbaArtifactId,
    this.exhibitorId,
    this.breedName,
    this.clubName,
    this.showLetter,
    this.scope,
  });

  factory CloseoutReportSelection.fromJson(Map<String, dynamic> json) =>
      CloseoutReportSelection(
        group: _text(json['group']),
        reportName: _text(json['report_name']),
        arbaArtifactId: _text(json['arba_artifact_id']),
        exhibitorId: _text(json['exhibitor_id']),
        breedName: _text(json['breed_name']),
        clubName: _text(json['club_name']),
        showLetter: _text(json['show_letter']),
        scope: _text(json['scope']),
      );

  Map<String, dynamic> toJson() => {
    'group': group,
    'report_name': reportName,
    'arba_artifact_id': arbaArtifactId,
    'exhibitor_id': exhibitorId,
    'breed_name': breedName,
    'club_name': clubName,
    'show_letter': showLetter,
    'scope': scope,
  };

  CloseoutReportSelection reconcile({
    required List<String> groupOrder,
    required Map<String, List<String>> reportNamesByGroup,
    required Iterable<String> arbaArtifactIds,
    required Map<String, Map<String, List<String>>> metadataByReport,
  }) {
    final resolvedGroup =
        _retain(group, groupOrder) ??
        (groupOrder.isEmpty ? null : groupOrder.first);
    final reportNames = reportNamesByGroup[resolvedGroup] ?? const <String>[];
    final resolvedReport =
        _retain(reportName, reportNames) ??
        (reportNames.isEmpty ? null : reportNames.first);
    final sameReport = resolvedGroup == group && resolvedReport == reportName;
    final metadata =
        metadataByReport[resolvedReport] ?? const <String, List<String>>{};
    final arbaIds = arbaArtifactIds.toList(growable: false);

    return CloseoutReportSelection(
      group: resolvedGroup,
      reportName: resolvedReport,
      arbaArtifactId:
          _retain(arbaArtifactId, arbaIds) ??
          (arbaIds.isEmpty ? null : arbaIds.first),
      exhibitorId: sameReport
          ? _retain(exhibitorId, metadata['exhibitor_id'] ?? const [])
          : null,
      breedName: sameReport
          ? _retain(breedName, metadata['breed_name'] ?? const [])
          : null,
      clubName: sameReport
          ? _retain(clubName, metadata['club_name'] ?? const [])
          : null,
      showLetter: sameReport
          ? _retain(showLetter, metadata['show_letter'] ?? const [])
          : null,
      scope: sameReport ? _retain(scope, metadata['scope'] ?? const []) : null,
    );
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String? _retain(String? value, Iterable<String> available) {
    if (value == null) return null;
    return available.contains(value) ? value : null;
  }
}
