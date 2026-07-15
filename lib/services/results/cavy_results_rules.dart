import '../results_group_resolution.dart';
import 'results_rules.dart';

class CavyResultsRules implements ResultsRules {
  const CavyResultsRules();

  @override
  ResultsSpecies get species => ResultsSpecies.cavy;
  @override
  String get speciesName => 'Cavy';

  String _canonical(Object? award) {
    final raw = (award ?? '').toString().trim();
    return const {
          'bog': 'BOG',
          'best of group': 'BOG',
          'bosg': 'BOSG',
          'best opposite sex of group': 'BOSG',
          'bob': 'BOB',
          'best of breed': 'BOB',
          'bosb': 'BOSB',
          'best opposite sex of breed': 'BOSB',
          'bis': 'BIS',
          'best in show': 'Best In Show',
          'ris': 'RIS',
          'reserve in show': 'Reserve In Show',
          'hm': 'HM',
        }[raw.toLowerCase()] ??
        raw;
  }

  @override
  ResultChildGroup childIdentity(Map<String, dynamic> entry) {
    final group = resolveCavyGroup(entry);
    final entryId = resultsRuleText(entry, const ['entry_id', 'id']);
    return ResultChildGroup(
      stableKey: group.recognized
          ? group.stableKey
          : 'unresolved:${entryId.isEmpty ? 'unknown' : entryId}',
      displayName: group.displayName.isEmpty
          ? '(No Group Assigned)'
          : group.displayName,
      entries: [entry],
    );
  }

  @override
  List<ResultChildGroup> buildChildGroups(List<Map<String, dynamic>> entries) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final names = <String, String>{};
    for (final entry in entries) {
      final identity = childIdentity(entry);
      grouped.putIfAbsent(identity.stableKey, () => []).add(entry);
      names[identity.stableKey] = identity.displayName;
    }
    return grouped.entries
        .map(
          (group) => ResultChildGroup(
            stableKey: group.key,
            displayName: names[group.key]!,
            entries: group.value,
          ),
        )
        .toList();
  }

  @override
  bool usesChildLayer(Map<String, dynamic> entry) =>
      resultsRuleBool(entry['uses_group_awards']);

  @override
  ResultChildGroup groupIdentity(Map<String, dynamic> entry) =>
      childIdentity(entry);

  @override
  ResultChildGroup varietyIdentity(Map<String, dynamic> entry) =>
      childIdentity(entry);

  @override
  List<ResultChildGroup> buildGroupGroups(List<Map<String, dynamic>> entries) =>
      buildChildGroups(entries);

  @override
  List<ResultChildGroup> buildVarietyGroups(
    List<Map<String, dynamic>> entries,
  ) => const [];

  @override
  bool usesGroupLayer(Map<String, dynamic> entry) => usesChildLayer(entry);

  @override
  bool usesVarietyLayer(Map<String, dynamic> entry) => false;

  @override
  Set<String> normalizeStoredAwards(Iterable<Object?> awards) =>
      awards.map(_canonical).where((award) => award.isNotEmpty).toSet();

  @override
  List<String> buildAwardOptions({
    required Map<String, dynamic> entry,
    required String classSystem,
    required String finalAwardMode,
  }) {
    final className = normalizeResultsRuleKey(entry['class_name']);
    final awards = <String>[];
    if (className.contains('junior') && !className.contains('pre')) {
      awards.add('Best Junior');
    }
    if (classSystem.toLowerCase() == 'six' &&
        className.contains('intermediate')) {
      awards.add('Best Intermediate');
    }
    if (className.contains('senior')) awards.add('Best Senior');
    awards.addAll(['BOG', 'BOSG', 'BOB', 'BOSB']);
    if (finalAwardMode == 'bis_ris') {
      awards.addAll(['Best In Show', 'Reserve In Show', 'HM']);
    } else if (finalAwardMode == 'bis_1ris_2ris') {
      awards.addAll(['Best In Show', '1RIS', '2RIS']);
    } else {
      awards.addAll(['Best 4-Class', 'Best 6-Class', 'Best In Show']);
    }
    return awards;
  }

  @override
  AwardCompatibilityResult validateAwardSelection({
    required Map<String, dynamic> entry,
    required Set<String> selectedAwards,
  }) {
    final awards = normalizeStoredAwards(selectedAwards);
    if (awards.contains('BOV') || awards.contains('BOSV')) {
      return const AwardCompatibilityResult.invalid(
        'Rabbit variety awards are invalid for cavy results.',
      );
    }
    if ((awards.contains('BOG') || awards.contains('BOSG')) &&
        !resolveCavyGroup(entry).recognized) {
      return AwardCompatibilityResult.invalid(
        '${unresolvedCavyGroupMessage(entry)} Group awards cannot be assigned.',
      );
    }
    if (awards.contains('BOB') && !awards.contains('BOG')) {
      return const AwardCompatibilityResult.invalid(
        'Cavy BOB requires an eligible BOG source.',
      );
    }
    if (awards.contains('BOSB') &&
        !awards.any(const {'BOG', 'BOSG'}.contains)) {
      return const AwardCompatibilityResult.invalid(
        'Cavy BOSB requires an eligible BOG or BOSG source.',
      );
    }
    return const AwardCompatibilityResult.valid();
  }

  bool _eligible(String status, Map<String, dynamic> entry) {
    if (resultsRuleText(entry, const ['scratched_at']).isNotEmpty) return false;
    final value = status.trim().toLowerCase();
    return value != 'no show' &&
        value != 'unworthy of award' &&
        !value.startsWith('disqualified');
  }

  @override
  bool canUseAward({
    required Map<String, dynamic> entry,
    required String award,
    required Set<String> selectedAwards,
    required String effectiveStatus,
    required String effectivePlacement,
    required String classSystem,
    required String finalAwardMode,
  }) {
    if (!_eligible(effectiveStatus, entry) || effectivePlacement != '1') {
      return false;
    }
    final selected = normalizeStoredAwards(selectedAwards);
    final code = _canonical(award);
    final className = normalizeResultsRuleKey(entry['class_name']);
    switch (code) {
      case 'Best Junior':
        return className.contains('junior') && !className.contains('pre');
      case 'Best Intermediate':
        return classSystem == 'six' && className.contains('intermediate');
      case 'Best Senior':
        return className.contains('senior');
      case 'BOG':
      case 'BOSG':
        return usesChildLayer(entry) && resolveCavyGroup(entry).recognized;
      case 'BOV':
      case 'BOSV':
      case 'BJV':
      case 'BIV':
      case 'BSV':
        return false;
      case 'BOB':
        return selected.contains('BOG');
      case 'BOSB':
        return selected.intersection(const {'BOG', 'BOSG'}).isNotEmpty;
      case 'Best 4-Class':
        return classSystem == 'four' && selected.contains('BOB');
      case 'Best 6-Class':
        return classSystem == 'six' && selected.contains('BOB');
      case 'Best In Show':
        return finalAwardMode == 'four_six_bis'
            ? selected.intersection(const {
                'Best 4-Class',
                'Best 6-Class',
              }).isNotEmpty
            : selected.contains('BOB');
      case 'Reserve In Show':
        return finalAwardMode == 'bis_ris' &&
            selected.contains('BOB') &&
            !selected.contains('Best In Show');
      case 'HM':
        return finalAwardMode == 'bis_ris' &&
            selected.contains('BOB') &&
            !selected.contains('Best In Show') &&
            !selected.contains('Reserve In Show');
      case '1RIS':
        return finalAwardMode == 'bis_1ris_2ris' &&
            selected.contains('BOB') &&
            !selected.contains('Best In Show') &&
            !selected.contains('2RIS');
      case '2RIS':
        return finalAwardMode == 'bis_1ris_2ris' &&
            selected.contains('BOB') &&
            !selected.contains('Best In Show') &&
            !selected.contains('1RIS');
      default:
        return false;
    }
  }

  @override
  String disabledAwardReason({
    required Map<String, dynamic> entry,
    required String award,
  }) {
    final code = _canonical(award);
    if ((code == 'BOG' || code == 'BOSG') &&
        !resolveCavyGroup(entry).recognized) {
      return '${unresolvedCavyGroupMessage(entry)} ${awardLabel(code)} cannot be assigned.';
    }
    if (code == 'BOV' || code == 'BOSV') {
      return 'Rabbit variety awards cannot be assigned to cavies.';
    }
    if (code == 'BOB' || code == 'BOSB') {
      return 'Requires an eligible BOG or BOSG first.';
    }
    return '${awardLabel(code)} is not eligible for this cavy right now.';
  }

  @override
  Set<String> sourceAwardsForBreedAward(
    Map<String, dynamic> entry,
    String breedAward,
  ) => breedAward == 'BOB' ? const {'BOG'} : const {'BOG', 'BOSG'};

  @override
  String awardLabel(String award) => switch (_canonical(award)) {
    'BOG' => 'Best of Group',
    'BOSG' => 'Best Opposite Sex of Group',
    'BOB' => 'Best of Breed',
    'BOSB' => 'Best Opposite Sex of Breed',
    'HM' => 'Honorable Mention',
    final value => value,
  };

  @override
  String buildSpecialsSummary(
    List<Map<String, dynamic>> entries,
    List<String> awardCodes,
  ) {
    final parts = <String>[];
    for (final code in awardCodes) {
      final winners = entries.where((entry) {
        final awards = normalizeStoredAwards(entry['_awards'] as List? ?? []);
        return awards.contains(_canonical(code));
      }).toList();
      if (winners.isEmpty) continue;
      parts.add(
        '${awardLabel(code)}: ${winners.map((e) => resultsRuleText(e, const ['coop_number', 'tattoo', 'animal_name'])).join(', ')}',
      );
    }
    return parts.isEmpty ? '' : 'Specials: ${parts.join(' • ')}';
  }

  @override
  ResultsNavigationTarget buildFixTarget(Map<String, dynamic> entry) =>
      ResultsNavigationTarget(
        childKey: childIdentity(entry).stableKey,
        groupKey: childIdentity(entry).stableKey,
        classSexKey: resultsRuleText(entry, const ['class_name']),
        entryId: resultsRuleText(entry, const ['entry_id', 'id']),
      );
}
