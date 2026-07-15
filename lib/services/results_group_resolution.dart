String normalizeResultsGroupKey(Object? value) {
  return (value ?? '').toString().trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
}

String _firstGroupText(Map<String, dynamic> entry, List<String> keys) {
  for (final key in keys) {
    final value = (entry[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

bool _entryBool(Object? value) {
  if (value == true) return true;
  final normalized = normalizeResultsGroupKey(value);
  return normalized == 'true' || normalized == 't' || normalized == '1';
}

bool _isCavyGroupEntry(Map<String, dynamic> entry) {
  if (!_entryBool(entry['uses_group_awards'])) return false;
  final species = normalizeResultsGroupKey(entry['species']);
  if (species == 'cavy' || species == 'cavies') return true;
  return false;
}

class ResolvedCavyGroup {
  final String? stableId;
  final String stableKey;
  final String displayName;
  final bool recognized;
  final String source;
  final String confidence;

  const ResolvedCavyGroup({
    required this.stableId,
    required this.stableKey,
    required this.displayName,
    required this.recognized,
    required this.source,
    required this.confidence,
  });

  String get name => displayName;
  String get normalizedKey => stableKey;
  bool get isRecognized => recognized;

  static const unresolved = ResolvedCavyGroup(
    stableId: null,
    stableKey: '',
    displayName: '',
    recognized: false,
    source: 'unresolved',
    confidence: 'none',
  );
}

ResolvedCavyGroup resolveCavyGroup(Map<String, dynamic> entry) {
  final breedId = _firstGroupText(entry, const [
    'breed_id',
    'breed_catalog_id',
  ]);
  final breedName = _firstGroupText(entry, const ['breed_name', 'breed']);
  final breedScope = normalizeResultsGroupKey(
    breedId.isNotEmpty ? breedId : breedName,
  );

  ResolvedCavyGroup resolved({
    required String id,
    required String name,
    required String stablePrefix,
    required String source,
    required String confidence,
  }) {
    final displayName = name.trim();
    final stableId = id.trim();
    final identity = normalizeResultsGroupKey(
      stableId.isNotEmpty ? stableId : displayName,
    );
    if (identity.isEmpty) return ResolvedCavyGroup.unresolved;
    return ResolvedCavyGroup(
      stableId: stableId.isEmpty ? null : stableId,
      stableKey: stablePrefix.isEmpty
          ? identity
          : '$stablePrefix:${breedScope.isEmpty ? 'unknown-breed' : breedScope}:$identity',
      displayName: displayName.isNotEmpty ? displayName : stableId,
      recognized: true,
      source: source,
      confidence: confidence,
    );
  }

  final explicitId = _firstGroupText(entry, const [
    'group_id',
    'breed_group_id',
  ]);
  final explicitName = _firstGroupText(entry, const [
    'group_name',
    'group_display_name',
    'group_label',
    'group',
    'group_code',
  ]);
  if (explicitId.isNotEmpty || explicitName.isNotEmpty) {
    return resolved(
      id: explicitId,
      name: explicitName,
      stablePrefix: 'explicit',
      source: 'explicitGroup',
      confidence: 'high',
    );
  }

  final mappedId = _firstGroupText(entry, const [
    'breed_variety_group_id',
    'variety_group_id',
    'catalog_group_id',
  ]);
  final mappedName = _firstGroupText(entry, const [
    'breed_variety_group_name',
    'variety_group_name',
    'configured_group_name',
    'catalog_group_name',
  ]);
  if (mappedId.isNotEmpty || mappedName.isNotEmpty) {
    return resolved(
      id: mappedId,
      name: mappedName,
      stablePrefix: 'catalog',
      source: 'catalogMapping',
      confidence: 'high',
    );
  }

  final exactName = _firstGroupText(entry, const ['exact_group_name']);
  if (exactName.isNotEmpty) {
    return resolved(
      id: '',
      name: exactName,
      stablePrefix: 'exact',
      source: 'exactRpcGroup',
      confidence: 'high',
    );
  }

  if (_isCavyGroupEntry(entry)) {
    final fallbackName = _firstGroupText(entry, const [
      'exact_variety_name',
      'variety_name',
      'variety',
      // Retained for rows enriched by the previous implementation. SOP data
      // confirms the name and ordering but is not itself a group relation.
      'cavy_sop_group_name',
    ]);
    if (fallbackName.isNotEmpty) {
      return resolved(
        id: '',
        name: fallbackName,
        stablePrefix: 'fallback',
        source: 'varietyFallback',
        confidence: 'fallback',
      );
    }
  }

  return ResolvedCavyGroup.unresolved;
}

String unresolvedCavyGroupMessage(Map<String, dynamic> entry) {
  final breed = _firstGroupText(entry, const ['breed_name', 'breed']);
  final variety = _firstGroupText(entry, const [
    'exact_variety_name',
    'variety_name',
    'variety',
  ]);
  final breedLabel = breed.isEmpty ? 'This cavy breed' : breed;
  if (variety.isNotEmpty) {
    return '$breedLabel • variety $variety is not mapped to a cavy group in the breed catalog.';
  }
  return '$breedLabel does not have a recognized cavy group or variety value.';
}
