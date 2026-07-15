enum ResultsSpecies { rabbit, cavy }

class UnsupportedResultsSpecies implements Exception {
  final String value;
  const UnsupportedResultsSpecies(this.value);

  @override
  String toString() => value.trim().isEmpty
      ? 'Results species is missing.'
      : 'Unsupported results species: $value.';
}

String normalizeResultsSpeciesStrict(Object? value) {
  final species = (value ?? '').toString().trim().toLowerCase();
  if (species == 'rabbit' || species == 'rabbits') return 'rabbit';
  if (species == 'cavy' || species == 'cavies') return 'cavy';
  return '';
}

String resultsRuleText(Map<String, dynamic> entry, List<String> keys) {
  for (final key in keys) {
    final value = (entry[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String normalizeResultsRuleKey(Object? value) => (value ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

bool resultsRuleBool(Object? value) {
  if (value == true) return true;
  final normalized = normalizeResultsRuleKey(value);
  return normalized == 'true' || normalized == 't' || normalized == '1';
}

class ResultChildGroup {
  final String stableKey;
  final String displayName;
  final List<Map<String, dynamic>> entries;

  const ResultChildGroup({
    required this.stableKey,
    required this.displayName,
    required this.entries,
  });
}

class AwardCompatibilityResult {
  final bool valid;
  final String? message;

  const AwardCompatibilityResult._(this.valid, this.message);
  const AwardCompatibilityResult.valid() : this._(true, null);
  const AwardCompatibilityResult.invalid(String message)
    : this._(false, message);
}

class ResultsNavigationTarget {
  final String childKey;
  final String? groupKey;
  final String? varietyKey;
  final String? classSexKey;
  final String? entryId;

  const ResultsNavigationTarget({
    required this.childKey,
    this.groupKey,
    this.varietyKey,
    this.classSexKey,
    this.entryId,
  });
}

enum ResultNavigationNodeType {
  breed,
  rabbitGroup,
  rabbitVariety,
  cavyGroup,
  classSex,
  entry,
}

class ResultNavigationNode {
  final ResultNavigationNodeType nodeType;
  final String stableId;
  final String displayName;
  final List<ResultNavigationNode> children;
  final List<Map<String, dynamic>> entries;

  const ResultNavigationNode({
    required this.nodeType,
    required this.stableId,
    required this.displayName,
    this.children = const [],
    this.entries = const [],
  });
}

abstract class ResultsRules {
  ResultsSpecies get species;
  String get speciesName;

  ResultChildGroup childIdentity(Map<String, dynamic> entry);
  List<ResultChildGroup> buildChildGroups(List<Map<String, dynamic>> entries);
  bool usesChildLayer(Map<String, dynamic> entry);
  ResultChildGroup groupIdentity(Map<String, dynamic> entry);
  ResultChildGroup varietyIdentity(Map<String, dynamic> entry);
  List<ResultChildGroup> buildGroupGroups(List<Map<String, dynamic>> entries);
  List<ResultChildGroup> buildVarietyGroups(List<Map<String, dynamic>> entries);
  bool usesGroupLayer(Map<String, dynamic> entry);
  bool usesVarietyLayer(Map<String, dynamic> entry);

  Set<String> normalizeStoredAwards(Iterable<Object?> awards);
  List<String> buildAwardOptions({
    required Map<String, dynamic> entry,
    required String classSystem,
    required String finalAwardMode,
  });
  AwardCompatibilityResult validateAwardSelection({
    required Map<String, dynamic> entry,
    required Set<String> selectedAwards,
  });
  bool canUseAward({
    required Map<String, dynamic> entry,
    required String award,
    required Set<String> selectedAwards,
    required String effectiveStatus,
    required String effectivePlacement,
    required String classSystem,
    required String finalAwardMode,
  });
  String disabledAwardReason({
    required Map<String, dynamic> entry,
    required String award,
  });
  Set<String> sourceAwardsForBreedAward(
    Map<String, dynamic> entry,
    String breedAward,
  );
  String awardLabel(String award);
  String buildSpecialsSummary(
    List<Map<String, dynamic>> entries,
    List<String> awardCodes,
  );
  ResultsNavigationTarget buildFixTarget(Map<String, dynamic> entry);
}
