import 'results_entry_validation.dart';
import 'results_group_resolution.dart';

enum ResultsAwardMode { rabbitVariety, cavyGroup, directBreed }

ResultsAwardMode resolveResultsAwardMode({
  required String species,
  required String breedId,
  required bool usesGroupAwards,
  required bool usesVarietyAwards,
  String? groupId,
  String? groupName,
  String? varietyId,
  String? varietyName,
}) {
  final normalizedSpecies = normalizeResultsSpecies(species);
  if (normalizedSpecies == 'cavy' && (usesGroupAwards || usesVarietyAwards)) {
    return ResultsAwardMode.cavyGroup;
  }
  if (normalizedSpecies == 'rabbit' && usesVarietyAwards) {
    return ResultsAwardMode.rabbitVariety;
  }
  return ResultsAwardMode.directBreed;
}

ResultsAwardMode resultsAwardModeForEntry(Map<String, dynamic> entry) {
  return resolveResultsAwardMode(
    species: resultsSpeciesForEntry(entry),
    breedId: _firstText(entry, const ['breed_id', 'breed_catalog_id']),
    usesGroupAwards: resultsEntryBool(entry['uses_group_awards']),
    usesVarietyAwards: resultsEntryBool(entry['uses_variety_awards']),
    groupId: _firstText(entry, const ['group_id', 'breed_group_id']),
    groupName: _firstText(entry, const [
      'group_name',
      'group_display_name',
      'group_label',
      'group',
      'group_code',
    ]),
    varietyId: _firstText(entry, const ['variety_id', 'breed_variety_id']),
    varietyName: _firstText(entry, const ['variety', 'variety_name']),
  );
}

bool resultsEntryBool(Object? value) {
  if (value == true) return true;
  final normalized = (value ?? '').toString().trim().toLowerCase();
  return normalized == 'true' || normalized == 't' || normalized == '1';
}

String canonicalResultsAwardCode(Object? award) {
  final raw = (award ?? '').toString().trim();
  final value = raw.toLowerCase();
  const aliases = {
    'bog': 'BOG',
    'best of group': 'BOG',
    'bosg': 'BOSG',
    'best opposite sex of group': 'BOSG',
    'best opposite of group': 'BOSG',
    'bov': 'BOV',
    'best of variety': 'BOV',
    'bosv': 'BOSV',
    'best opposite sex of variety': 'BOSV',
    'best opposite of variety': 'BOSV',
    'bob': 'BOB',
    'best of breed': 'BOB',
    'bosb': 'BOSB',
    'best opposite sex of breed': 'BOSB',
    'best opposite of breed': 'BOSB',
    'bjv': 'BJV',
    'best junior variety': 'BJV',
    'biv': 'BIV',
    'best intermediate variety': 'BIV',
    'bsv': 'BSV',
    'best senior variety': 'BSV',
    'bjb': 'BJB',
    'best junior breed': 'BJB',
    'best junior of breed': 'BJB',
    'bib': 'BIB',
    'best intermediate breed': 'BIB',
    'best intermediate of breed': 'BIB',
    'bsb': 'BSB',
    'best senior breed': 'BSB',
    'best senior of breed': 'BSB',
    'best junior': 'Best Junior',
    'best intermediate': 'Best Intermediate',
    'best senior': 'Best Senior',
    'b4c': 'Best 4-Class',
    'best 4 class': 'Best 4-Class',
    'best 4-class': 'Best 4-Class',
    'best four class': 'Best 4-Class',
    'best four-class': 'Best 4-Class',
    'b6c': 'Best 6-Class',
    'best 6 class': 'Best 6-Class',
    'best 6-class': 'Best 6-Class',
    'best six class': 'Best 6-Class',
    'best six-class': 'Best 6-Class',
    'best in show': 'Best In Show',
    'best in show rabbit': 'Best In Show',
    'reserve in show': 'Reserve In Show',
    'reserve best in show': 'Reserve In Show',
    'reserve in show rabbit': 'Reserve In Show',
    'bis': 'BIS',
    'ris': 'RIS',
    '1ris': '1RIS',
    '1st ris': '1RIS',
    'first ris': '1RIS',
    '1st reserve in show': '1RIS',
    'first reserve in show': '1RIS',
    '2ris': '2RIS',
    '2nd ris': '2RIS',
    'second ris': '2RIS',
    '2nd reserve in show': '2RIS',
    'second reserve in show': '2RIS',
    'hm': 'HM',
  };
  return aliases[value] ?? raw.toUpperCase();
}

Set<String> normalizedResultsAwardCodes(Iterable<Object?> awards) {
  return awards
      .map(canonicalResultsAwardCode)
      .where((award) => award.isNotEmpty)
      .toSet();
}

List<String> serializeResultsAwardsForSave(Iterable<Object?> awards) {
  final normalized = normalizedResultsAwardCodes(awards).toList()..sort();
  return normalized;
}

String resultsAwardGroupScope(Map<String, dynamic> entry) {
  return resolveCavyGroup(entry).normalizedKey;
}

bool resultsAwardModeHasRecognizedSource(
  ResultsAwardMode mode,
  Map<String, dynamic> entry,
) {
  return switch (mode) {
    ResultsAwardMode.cavyGroup => resultsAwardGroupScope(entry).isNotEmpty,
    ResultsAwardMode.rabbitVariety =>
      _firstText(entry, const ['variety_id', 'breed_variety_id']).isNotEmpty ||
          _firstText(entry, const ['variety', 'variety_name']).isNotEmpty,
    ResultsAwardMode.directBreed => true,
  };
}

Set<String> sourceAwardCodesForMode(ResultsAwardMode mode) {
  return switch (mode) {
    ResultsAwardMode.cavyGroup => const {'BOV', 'BOSV'},
    ResultsAwardMode.rabbitVariety => const {'BOV', 'BOSV'},
    ResultsAwardMode.directBreed => const {},
  };
}

String resultsAwardLabel(String award, ResultsAwardMode mode) {
  final code = canonicalResultsAwardCode(award);
  if (mode == ResultsAwardMode.cavyGroup) {
    return switch (code) {
      'BJV' => 'Best Junior Variety',
      'BIV' => 'Best Intermediate Variety',
      'BSV' => 'Best Senior Variety',
      'BJB' => 'Best Junior of Breed',
      'BIB' => 'Best Intermediate of Breed',
      'BSB' => 'Best Senior of Breed',
      'BOV' => 'Best of Variety',
      'BOSV' => 'Best Opposite Sex of Variety',
      'BOB' => 'Best of Breed',
      'BOSB' => 'Best Opposite Sex of Breed',
      'Best 4-Class' => 'Best 4-Class',
      'Best 6-Class' => 'Best 6-Class',
      'Best In Show' || 'BIS' => 'Best in Show',
      'Reserve In Show' || 'RIS' => 'Reserve in Show',
      '1RIS' => '1st Reserve in Show',
      '2RIS' => '2nd Reserve in Show',
      'HM' => 'Honorable Mention',
      _ => code,
    };
  }
  return switch (code) {
    'BOV' => 'Best of Variety',
    'BOSV' => 'Best Opposite Sex of Variety',
    'BOB' => 'Best of Breed',
    'BOSB' => 'Best Opposite Sex of Breed',
    _ => code,
  };
}

List<String> visibleResultsAwardCodes({
  required ResultsAwardMode mode,
  required String className,
  required String classSystem,
  required String finalAwardMode,
}) {
  final awards = <String>[];
  final normalizedClass = className.trim().toLowerCase();

  if (mode == ResultsAwardMode.cavyGroup) {
    if (normalizedClass.contains('junior') &&
        !normalizedClass.contains('pre-junior') &&
        !normalizedClass.contains('pre junior')) {
      awards.addAll(const ['BJV', 'BJB']);
    }
    if (classSystem.trim().toLowerCase() == 'six' &&
        normalizedClass.contains('intermediate')) {
      awards.addAll(const ['BIV', 'BIB']);
    }
    if (normalizedClass.contains('senior')) {
      awards.addAll(const ['BSV', 'BSB']);
    }
    awards.addAll(const ['BOV', 'BOSV', 'BOB', 'BOSB']);
  } else if (mode == ResultsAwardMode.rabbitVariety) {
    awards.addAll(const ['BOV', 'BOSV', 'BOB', 'BOSB']);
  } else {
    awards.addAll(const ['BOB', 'BOSB']);
  }

  if (finalAwardMode == 'bis_ris') {
    awards.addAll(const ['Best In Show', 'Reserve In Show']);
    if (mode == ResultsAwardMode.cavyGroup) awards.add('HM');
  } else if (finalAwardMode == 'bis_1ris_2ris') {
    awards.addAll(const ['Best In Show', '1RIS', '2RIS']);
  } else {
    awards.addAll(const ['Best 4-Class', 'Best 6-Class', 'Best In Show']);
  }
  return awards;
}

String? validateAwardModeCompatibility({
  required ResultsAwardMode mode,
  required Map<String, dynamic> entry,
  required Set<String> selectedAwards,
}) {
  final awards = normalizedResultsAwardCodes(selectedAwards);
  if (mode == ResultsAwardMode.cavyGroup) {
    if ((awards.contains('BOV') || awards.contains('BOSV')) &&
        !resultsAwardModeHasRecognizedSource(mode, entry)) {
      return '${unresolvedCavyGroupMessage(entry)} ${awards.contains('BOV') ? 'Best of Variety' : 'Best Opposite Sex of Variety'} cannot be assigned.';
    }
    if (awards.contains('BOG') || awards.contains('BOSG')) {
      return 'Group awards are not valid for cavy results. Use Best of Variety and Best Opposite Sex of Variety.';
    }
  }
  if (mode == ResultsAwardMode.rabbitVariety &&
      (awards.contains('BOG') || awards.contains('BOSG'))) {
    return 'Group awards are not valid for a rabbit breed configured to use variety awards.';
  }

  final sources = sourceAwardCodesForMode(mode);
  if ((awards.contains('BOB') || awards.contains('BOSB')) &&
      sources.isNotEmpty &&
      awards.intersection(sources).isEmpty) {
    final sourceLabel = mode == ResultsAwardMode.cavyGroup
        ? 'Best of Variety or Best Opposite Sex of Variety'
        : 'Best of Variety or Best Opposite Sex of Variety';
    return 'Best of Breed awards require $sourceLabel first.';
  }
  return null;
}

String _firstText(Map<String, dynamic> entry, List<String> keys) {
  for (final key in keys) {
    final value = (entry[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}
