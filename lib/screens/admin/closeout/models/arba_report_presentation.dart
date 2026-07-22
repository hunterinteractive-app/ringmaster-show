class ArbaReportSectionDescriptor {
  const ArbaReportSectionDescriptor({
    required this.id,
    required this.species,
    required this.kind,
    required this.letter,
    required this.displayName,
    required this.isAllBreed,
    required this.sortOrder,
  });

  final String id;
  final Set<String> species;
  final String kind;
  final String letter;
  final String displayName;
  final bool isAllBreed;
  final int sortOrder;
}

class ArbaArtifactDescriptor {
  const ArbaArtifactDescriptor({
    required this.id,
    required this.finalizeRunId,
    required this.reportName,
    required this.artifactStatus,
    required this.storageBucket,
    required this.storagePath,
    required this.isCurrent,
    required this.metadata,
  });

  final String id;
  final String finalizeRunId;
  final String reportName;
  final String artifactStatus;
  final String storageBucket;
  final String storagePath;
  final bool isCurrent;
  final Map<String, dynamic> metadata;
}

class ArbaReportOption {
  const ArbaReportOption({
    required this.artifactId,
    required this.sectionId,
    required this.sectionName,
    required this.label,
    required this.storagePath,
  });

  final String artifactId;
  final String sectionId;
  final String sectionName;
  final String label;
  final String storagePath;
}

List<ArbaArtifactDescriptor> selectBundledArbaArtifacts({
  required Iterable<ArbaArtifactDescriptor> artifacts,
  required String finalizeRunId,
  required String stableScopeKey,
  required Set<String> selectedSectionIds,
}) {
  final seenIds = <String>{};
  final seenPaths = <String>{};

  return artifacts.where((artifact) {
    if (artifact.reportName != 'arba_report' ||
        !artifact.isCurrent ||
        artifact.artifactStatus != 'generated' ||
        artifact.storageBucket.trim().isEmpty ||
        artifact.storagePath.trim().isEmpty ||
        artifact.finalizeRunId.trim() != finalizeRunId.trim() ||
        !_matchesScope(
          artifact.metadata,
          stableScopeKey: stableScopeKey,
          selectedSectionIds: selectedSectionIds,
        )) {
      return false;
    }

    final id = artifact.id.trim();
    final path = artifact.storagePath.trim();
    if (id.isNotEmpty && !seenIds.add(id)) return false;
    if (!seenPaths.add(path)) return false;
    return true;
  }).toList();
}

List<ArbaReportOption> buildArbaReportOptions({
  required Iterable<ArbaArtifactDescriptor> artifacts,
  required Iterable<ArbaReportSectionDescriptor> sections,
}) {
  final sectionsById = {for (final section in sections) section.id: section};
  final rows =
      artifacts
          .where(
            (artifact) =>
                artifact.reportName == 'arba_report' && artifact.isCurrent,
          )
          .map((artifact) {
            final sectionId = (artifact.metadata['section_id'] ?? '')
                .toString()
                .trim();
            final section = sectionsById[sectionId];
            final name = arbaSectionDisplayName(
              section: section,
              metadata: artifact.metadata,
            );
            return (
              artifact: artifact,
              section: section,
              sectionId: sectionId,
              name: name,
            );
          })
          .toList()
        ..sort(
          (a, b) => _compareSections(a.section, b.section, a.name, b.name),
        );

  return rows.map((row) {
    return ArbaReportOption(
      artifactId: row.artifact.id,
      sectionId: row.sectionId,
      sectionName: row.name,
      label: row.name,
      storagePath: row.artifact.storagePath,
    );
  }).toList();
}

String arbaSectionDisplayName({
  ArbaReportSectionDescriptor? section,
  required Map<String, dynamic> metadata,
}) {
  final kind = _title(
    section?.kind ?? (metadata['section_kind'] ?? metadata['scope'] ?? ''),
  );
  final letter = (section?.letter ?? metadata['show_letter'] ?? '')
      .toString()
      .trim()
      .toUpperCase();
  final species = _speciesLabel(
    section?.species ?? _metadataSpecies(metadata),
    fallbackText: (metadata['section_label'] ?? '').toString(),
  );
  final configuredName =
      (section?.displayName ??
              metadata['section_display_name'] ??
              metadata['section_name'] ??
              metadata['section_label'] ??
              '')
          .toString()
          .trim();
  if (configuredName.isNotEmpty) return configuredName;

  final suffix = [kind, letter].where((part) => part.isNotEmpty).join(' ');
  final standard = [species, suffix].where((part) => part.isNotEmpty).join(' ');
  return standard.isEmpty ? 'Selected Section' : standard;
}

String arbaDownloadFileName({
  required String showName,
  required String sectionName,
}) {
  final safeShow = sanitizeDownloadFilePart(showName, fallback: 'Show');
  final safeSection = sanitizeDownloadFilePart(
    sectionName,
    fallback: 'Selected Section',
  );
  return '$safeShow - ARBA Report - $safeSection.pdf';
}

String arbaEmailConfirmationText({
  required int reportCount,
  required String scopeLabel,
}) {
  return 'Email $reportCount ARBA ${reportCount == 1 ? 'report' : 'reports'} for $scopeLabel to ARBA?';
}

String sanitizeDownloadFilePart(String value, {required String fallback}) {
  final clean = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean.isEmpty ? fallback : clean;
}

String? normalizedArbaSelection(
  String? selectedArtifactId,
  List<ArbaReportOption> options,
) {
  if (options.isEmpty) return null;
  if (options.any((option) => option.artifactId == selectedArtifactId)) {
    return selectedArtifactId;
  }
  return options.first.artifactId;
}

ArbaReportOption? selectedArbaOption(
  String? selectedArtifactId,
  List<ArbaReportOption> options,
) {
  final normalized = normalizedArbaSelection(selectedArtifactId, options);
  if (normalized == null) return null;
  return options.firstWhere((option) => option.artifactId == normalized);
}

bool _matchesScope(
  Map<String, dynamic> metadata, {
  required String stableScopeKey,
  required Set<String> selectedSectionIds,
}) {
  final runScopeKey = (metadata['run_scope_key'] ?? '').toString().trim();
  if (runScopeKey.isNotEmpty && runScopeKey != stableScopeKey) return false;

  final sectionId = (metadata['section_id'] ?? '').toString().trim();
  if (sectionId.isNotEmpty) return selectedSectionIds.contains(sectionId);

  final rawIds = metadata['section_ids'];
  if (rawIds is List) {
    final ids = rawIds
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (ids.isNotEmpty) {
      return ids.every(selectedSectionIds.contains);
    }
  }

  if (runScopeKey.isNotEmpty) return true;

  // Legacy artifacts stored the finalize-run key in scope_key. Canonical
  // artifacts now store an artifact-specific key there, so it is only a safe
  // fallback when structured section scope is unavailable.
  final artifactKey = (metadata['scope_key'] ?? '').toString().trim();
  return artifactKey.isNotEmpty && artifactKey == stableScopeKey;
}

int _compareSections(
  ArbaReportSectionDescriptor? a,
  ArbaReportSectionDescriptor? b,
  String aName,
  String bName,
) {
  final species = _speciesRank(a?.species).compareTo(_speciesRank(b?.species));
  if (species != 0) return species;
  final kind = _kindRank(a?.kind).compareTo(_kindRank(b?.kind));
  if (kind != 0) return kind;
  final order = (a?.sortOrder ?? 1 << 20).compareTo(b?.sortOrder ?? 1 << 20);
  if (order != 0) return order;
  final letter = (a?.letter ?? '').compareTo(b?.letter ?? '');
  if (letter != 0) return letter;
  final allBreed = (a?.isAllBreed == true ? 0 : 1).compareTo(
    b?.isAllBreed == true ? 0 : 1,
  );
  if (allBreed != 0) return allBreed;
  return aName.toLowerCase().compareTo(bName.toLowerCase());
}

Set<String> _metadataSpecies(Map<String, dynamic> metadata) {
  final value = (metadata['species'] ?? '').toString().trim().toLowerCase();
  return value.isEmpty ? const {} : {value};
}

String _speciesLabel(Set<String>? species, {String fallbackText = ''}) {
  final normalized = species?.map((value) => value.toLowerCase()).toSet() ?? {};
  if (normalized.contains('cavy')) return 'Cavy';
  if (normalized.contains('rabbit')) return 'Rabbit';
  if (fallbackText.toLowerCase().contains('cavy')) return 'Cavy';
  return 'Rabbit';
}

int _speciesRank(Set<String>? species) {
  final normalized = species?.map((value) => value.toLowerCase()).toSet() ?? {};
  if (normalized.contains('rabbit')) return 0;
  if (normalized.contains('cavy')) return 1;
  return 2;
}

int _kindRank(String? kind) {
  return switch (kind?.trim().toLowerCase()) {
    'open' => 0,
    'youth' => 1,
    _ => 2,
  };
}

String _title(Object? value) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text.isEmpty) return '';
  return '${text[0].toUpperCase()}${text.substring(1)}';
}
