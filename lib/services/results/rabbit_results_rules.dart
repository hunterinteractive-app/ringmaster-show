import 'rabbit_results_structure.dart';
import 'results_rules.dart';

class RabbitResultsRules implements ResultsRules {
  const RabbitResultsRules();

  @override
  ResultsSpecies get species => ResultsSpecies.rabbit;
  @override
  String get speciesName => 'Rabbit';

  String _canonical(Object? award) {
    final raw = (award ?? '').toString().trim();
    return const {
          'bov': 'BOV',
          'best of variety': 'BOV',
          'bosv': 'BOSV',
          'best opposite sex of variety': 'BOSV',
          'bjv': 'BJV',
          'biv': 'BIV',
          'bsv': 'BSV',
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
        }[raw.toLowerCase()] ??
        raw;
  }

  ResultChildGroup _group(
    Map<String, dynamic> entry,
    String stableKey,
    String displayName,
  ) => ResultChildGroup(
    stableKey: stableKey,
    displayName: displayName,
    entries: [entry],
  );

  List<ResultChildGroup> _groups(
    List<Map<String, dynamic>> entries,
    ResultChildGroup Function(Map<String, dynamic>) identity,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final names = <String, String>{};
    for (final entry in entries) {
      final child = identity(entry);
      grouped.putIfAbsent(child.stableKey, () => []).add(entry);
      names[child.stableKey] = child.displayName;
    }
    return grouped.entries
        .map(
          (item) => ResultChildGroup(
            stableKey: item.key,
            displayName: names[item.key]!,
            entries: item.value,
          ),
        )
        .toList();
  }

  @override
  ResultChildGroup groupIdentity(Map<String, dynamic> entry) {
    final value = resolveRabbitGroup(entry);
    return _group(entry, value.stableKey, value.displayName);
  }

  @override
  ResultChildGroup varietyIdentity(Map<String, dynamic> entry) {
    final value = resolveRabbitVariety(entry);
    return _group(entry, value.stableKey, value.displayName);
  }

  @override
  ResultChildGroup childIdentity(Map<String, dynamic> entry) {
    if (usesGroupLayer(entry)) return groupIdentity(entry);
    if (usesVarietyLayer(entry)) return varietyIdentity(entry);
    final breed = normalizeResultsRuleKey(
      resultsRuleText(entry, const ['breed_id', 'breed_name', 'breed']),
    );
    return _group(entry, 'direct:$breed', '(Direct Breed Awards)');
  }

  @override
  List<ResultChildGroup> buildGroupGroups(List<Map<String, dynamic>> entries) =>
      _groups(entries, groupIdentity);

  @override
  List<ResultChildGroup> buildVarietyGroups(
    List<Map<String, dynamic>> entries,
  ) => _groups(entries, varietyIdentity);

  @override
  List<ResultChildGroup> buildChildGroups(List<Map<String, dynamic>> entries) =>
      usesGroupLayer(entries.firstOrNull ?? const <String, dynamic>{})
      ? buildGroupGroups(entries)
      : buildVarietyGroups(entries);

  @override
  bool usesGroupLayer(Map<String, dynamic> entry) =>
      rabbitBreedStructure(entry) == RabbitBreedStructure.groupOnly ||
      rabbitBreedStructure(entry) == RabbitBreedStructure.groupedVarieties;

  @override
  bool usesVarietyLayer(Map<String, dynamic> entry) =>
      rabbitBreedStructure(entry) == RabbitBreedStructure.varietyOnly ||
      rabbitBreedStructure(entry) == RabbitBreedStructure.groupedVarieties;

  @override
  bool usesChildLayer(Map<String, dynamic> entry) =>
      usesGroupLayer(entry) || usesVarietyLayer(entry);

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
    final breed = normalizeResultsRuleKey(
      resultsRuleText(entry, const ['breed', 'breed_name']),
    );
    final supportsBestAge = const {
      'american sable',
      'american sables',
      'himalayan',
      'checkered giant',
    }.contains(breed);
    final awards = <String>[
      if (usesVarietyLayer(entry)) ...['BJV', 'BIV', 'BSV', 'BOV', 'BOSV'],
      if (usesGroupLayer(entry)) ...['BOG', 'BOSG'],
      'BOB',
      'BOSB',
    ];
    if (supportsBestAge) {
      if (className.contains('junior') && !className.contains('pre')) {
        awards.add('Best Junior');
      }
      if (classSystem.toLowerCase() == 'six' &&
          className.contains('intermediate')) {
        awards.add('Best Intermediate');
      }
      if (className.contains('senior')) awards.add('Best Senior');
    }
    if (finalAwardMode == 'bis_ris') {
      awards.addAll(['Best In Show', 'Reserve In Show']);
    } else if (finalAwardMode == 'bis_1ris_2ris') {
      awards.addAll(['Best In Show', '1RIS', '2RIS']);
    } else {
      awards.add('Best In Show');
    }
    return awards;
  }

  Set<String> _breedSources(Map<String, dynamic> entry, String breedAward) {
    if (usesGroupLayer(entry)) {
      return breedAward == 'BOB' ? const {'BOG'} : const {'BOG', 'BOSG'};
    }
    if (usesVarietyLayer(entry)) {
      return breedAward == 'BOB' ? const {'BOV'} : const {'BOV', 'BOSV'};
    }
    return const {};
  }

  @override
  AwardCompatibilityResult validateAwardSelection({
    required Map<String, dynamic> entry,
    required Set<String> selectedAwards,
  }) {
    final awards = normalizeStoredAwards(selectedAwards);
    if (awards.intersection(const {'BOG', 'BOSG'}).isNotEmpty &&
        !usesGroupLayer(entry)) {
      return const AwardCompatibilityResult.invalid(
        'Rabbit group awards are incompatible with this rabbit breed structure.',
      );
    }
    if (awards.intersection(const {'BOV', 'BOSV'}).isNotEmpty &&
        !usesVarietyLayer(entry)) {
      return const AwardCompatibilityResult.invalid(
        'Rabbit variety awards are incompatible with this rabbit breed structure.',
      );
    }
    if (awards.intersection(const {
      'Best 4-Class',
      'Best 6-Class',
    }).isNotEmpty) {
      return const AwardCompatibilityResult.invalid(
        'Best 4-Class and Best 6-Class are not rabbit result awards.',
      );
    }
    for (final breedAward in const ['BOB', 'BOSB']) {
      if (!awards.contains(breedAward)) continue;
      final sources = _breedSources(entry, breedAward);
      if (sources.isNotEmpty && awards.intersection(sources).isEmpty) {
        return AwardCompatibilityResult.invalid(
          'Rabbit $breedAward requires an eligible ${sources.join(' or ')} source.',
        );
      }
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
    if (const {'BJV', 'BIV', 'BSV', 'BOV', 'BOSV'}.contains(code)) {
      return usesVarietyLayer(entry);
    }
    if (const {'BOG', 'BOSG'}.contains(code)) return usesGroupLayer(entry);
    if (code == 'HM') return false;
    if (code == 'BOB' || code == 'BOSB') {
      final sources = _breedSources(entry, code);
      return sources.isEmpty || selected.intersection(sources).isNotEmpty;
    }
    if (code == 'Best 4-Class' || code == 'Best 6-Class') return false;
    if (code == 'Best In Show') {
      return selected.contains('BOB');
    }
    if (code == 'Reserve In Show') {
      return finalAwardMode == 'bis_ris' &&
          selected.contains('BOB') &&
          !selected.contains('Best In Show');
    }
    if (code == '1RIS') {
      return finalAwardMode == 'bis_1ris_2ris' &&
          selected.contains('BOB') &&
          !selected.contains('Best In Show') &&
          !selected.contains('2RIS');
    }
    if (code == '2RIS') {
      return finalAwardMode == 'bis_1ris_2ris' &&
          selected.contains('BOB') &&
          !selected.contains('Best In Show') &&
          !selected.contains('1RIS');
    }
    return true;
  }

  @override
  String disabledAwardReason({
    required Map<String, dynamic> entry,
    required String award,
  }) {
    final code = _canonical(award);
    if (const {'BOV', 'BOSV'}.contains(code)) {
      return 'Only rabbit breeds with variety awards use this award.';
    }
    if (const {'BOG', 'BOSG'}.contains(code)) {
      return 'Only rabbit breeds with configured group awards use this award.';
    }
    if (const {'BOB', 'BOSB'}.contains(code)) {
      final sources = _breedSources(entry, code);
      return sources.isEmpty
          ? 'Not eligible for this rabbit right now.'
          : 'Requires an eligible ${sources.join(' or ')} first.';
    }
    return 'Not eligible for this rabbit right now.';
  }

  @override
  Set<String> sourceAwardsForBreedAward(
    Map<String, dynamic> entry,
    String breedAward,
  ) => _breedSources(entry, breedAward);

  @override
  String awardLabel(String award) => switch (_canonical(award)) {
    'BJV' => 'Best Junior Variety',
    'BIV' => 'Best Intermediate Variety',
    'BSV' => 'Best Senior Variety',
    'BOV' => 'Best of Variety',
    'BOSV' => 'Best Opposite Sex of Variety',
    'BOG' => 'Best of Rabbit Group',
    'BOSG' => 'Best Opposite Sex of Rabbit Group',
    'BOB' => 'Best of Breed',
    'BOSB' => 'Best Opposite Sex of Breed',
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
  ResultsNavigationTarget buildFixTarget(Map<String, dynamic> entry) {
    final group = usesGroupLayer(entry) ? groupIdentity(entry) : null;
    final variety = usesVarietyLayer(entry) ? varietyIdentity(entry) : null;
    return ResultsNavigationTarget(
      childKey: (group ?? variety)?.stableKey ?? childIdentity(entry).stableKey,
      groupKey: group?.stableKey,
      varietyKey: variety?.stableKey,
      classSexKey: resultsRuleText(entry, const ['class_name']),
      entryId: resultsRuleText(entry, const ['entry_id', 'id']),
    );
  }
}
