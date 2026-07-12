class ResultsEntryBlockingIssue {
  final String code;
  final String title;
  final String message;
  final Map<String, dynamic> entry;
  final Map<String, dynamic>? conflictsWith;

  const ResultsEntryBlockingIssue({
    required this.code,
    required this.title,
    required this.message,
    required this.entry,
    this.conflictsWith,
  });
}

String normalizeResultsSpecies(Object? value) {
  final species = (value ?? '').toString().trim().toLowerCase();
  if (species == 'rabbit' || species == 'rabbits') return 'rabbit';
  if (species == 'cavy' || species == 'cavies') return 'cavy';
  return species;
}

String resultsSpeciesForEntry(Map<String, dynamic> entry) {
  final explicit = normalizeResultsSpecies(entry['species']);
  if (explicit.isNotEmpty) return explicit;

  // Some legacy result rows omit species. Sex terminology is reliable here;
  // breed names are not (for example, American exists in both species).
  final sex = (entry['sex'] ?? '').toString().trim().toLowerCase();
  if (sex.contains('boar') || sex.contains('sow')) return 'cavy';
  if (sex.contains('buck') || sex.contains('doe')) return 'rabbit';
  return '';
}

String resultsSpeciesLabel(Map<String, dynamic> entry) {
  return switch (resultsSpeciesForEntry(entry)) {
    'cavy' => 'Cavy',
    'rabbit' => 'Rabbit',
    final value when value.isNotEmpty =>
      '${value[0].toUpperCase()}${value.substring(1)}',
    _ => 'Animal',
  };
}

String resultsSectionScopeForEntry(Map<String, dynamic> entry) {
  for (final key in const [
    'section_id',
    'show_section_id',
    'show_letter',
    'section_letter',
    'section_label',
  ]) {
    final value = (entry[key] ?? '').toString().trim().toLowerCase();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String resultsFinalAwardScopeKey(Map<String, dynamic> entry, String awardCode) {
  final showId = (entry['show_id'] ?? '').toString().trim().toLowerCase();
  final sectionId = resultsSectionScopeForEntry(entry);
  final species = resultsSpeciesForEntry(entry);
  final award = awardCode.trim().toUpperCase();
  // Award remains the second component for existing issue-label extraction.
  return '$sectionId|$award|$species|$showId';
}

List<ResultsEntryBlockingIssue> buildBreedCompletionIssues({
  required List<Map<String, dynamic>> entries,
  required bool requireVarietyAwards,
  required bool requireGroupAwards,
  required bool requireBreedAwards,
  required bool Function(Map<String, dynamic>) hasBasicOutcome,
  required bool Function(Map<String, dynamic>) isEligibleForSpecialAward,
  required bool Function(Map<String, dynamic>) isExcludedFromSpecials,
  required List<String> Function(Map<String, dynamic>) awardCodes,
  required String Function(Map<String, dynamic>) entryLabel,
  required String Function(Map<String, dynamic>) sectionId,
  required String Function(Map<String, dynamic>) breed,
  required String Function(Map<String, dynamic>) variety,
  required String Function(Map<String, dynamic>) group,
  required String Function(Map<String, dynamic>) sex,
}) {
  final issues = <ResultsEntryBlockingIssue>[];
  final allBasicsComplete =
      entries.isNotEmpty && entries.every(hasBasicOutcome);

  for (final entry in entries.where((entry) => !hasBasicOutcome(entry))) {
    issues.add(
      ResultsEntryBlockingIssue(
        code: 'missing_basic_outcome',
        title: 'Incomplete placement or result',
        message:
            '${entryLabel(entry)} needs a placement or a No Show, scratched, disqualified, or unworthy result.',
        entry: entry,
      ),
    );
  }

  final normalEntries = entries
      .where((e) => !isExcludedFromSpecials(e))
      .toList();

  void validateBuckets({
    required Iterable<List<Map<String, dynamic>>> buckets,
    required List<String> requiredAwards,
    required String scopeLabel,
  }) {
    for (final bucket in buckets) {
      if (bucket.isEmpty) continue;
      final eligible = bucket.where(isEligibleForSpecialAward).toList();

      Map<String, dynamic>? winner(String award) {
        for (final entry in bucket) {
          if (awardCodes(entry).contains(award)) return entry;
        }
        return null;
      }

      for (final award in requiredAwards) {
        final winners = bucket
            .where((entry) => awardCodes(entry).contains(award))
            .toList();
        if (winners.length > 1) {
          issues.add(
            ResultsEntryBlockingIssue(
              code: 'duplicate_${award.toLowerCase()}',
              title: 'Duplicate $award winner',
              message:
                  '$award is assigned to more than one ${resultsSpeciesLabel(winners.first)} in this $scopeLabel: ${entryLabel(winners[0])} and ${entryLabel(winners[1])}.',
              entry: winners.first,
              conflictsWith: winners[1],
            ),
          );
        }
      }

      if (!allBasicsComplete || eligible.isEmpty) continue;
      final primary = requiredAwards.first;
      final primaryWinner = winner(primary);
      if (primaryWinner == null) {
        issues.add(
          ResultsEntryBlockingIssue(
            code: 'missing_${primary.toLowerCase()}',
            title: 'Missing $primary winner',
            message:
                'Select one eligible $primary winner for this ${resultsSpeciesLabel(bucket.first)} $scopeLabel.',
            entry: eligible.first,
          ),
        );
        continue;
      }

      if (requiredAwards.length < 2) continue;
      final opposite = requiredAwards[1];
      final primarySex = sex(primaryWinner);
      final hasOppositeCandidate = eligible.any(
        (entry) =>
            !identical(entry, primaryWinner) &&
            primarySex.isNotEmpty &&
            sex(entry).isNotEmpty &&
            sex(entry) != primarySex,
      );
      final oppositeWinner = winner(opposite);
      if (hasOppositeCandidate && oppositeWinner == null) {
        issues.add(
          ResultsEntryBlockingIssue(
            code: 'missing_${opposite.toLowerCase()}',
            title: 'Missing $opposite winner',
            message:
                'Select the eligible opposite-sex $opposite winner for this ${resultsSpeciesLabel(bucket.first)} $scopeLabel.',
            entry: eligible.firstWhere(
              (entry) => sex(entry).isNotEmpty && sex(entry) != primarySex,
            ),
          ),
        );
      } else if (!hasOppositeCandidate && oppositeWinner != null) {
        issues.add(
          ResultsEntryBlockingIssue(
            code: 'unexpected_${opposite.toLowerCase()}',
            title: '$opposite has no eligible candidate',
            message:
                'Remove $opposite from ${entryLabel(oppositeWinner)} because this $scopeLabel has no eligible opposite-sex animal.',
            entry: oppositeWinner,
          ),
        );
      }
    }
  }

  Map<String, List<Map<String, dynamic>>> buckets(
    String Function(Map<String, dynamic>) scope,
  ) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in normalEntries) {
      final key = scope(entry);
      if (key.isEmpty) continue;
      result.putIfAbsent(key, () => []).add(entry);
    }
    return result;
  }

  if (requireVarietyAwards) {
    validateBuckets(
      buckets: buckets((e) {
        final values = [sectionId(e), breed(e), variety(e)];
        return values.any((value) => value.isEmpty) ? '' : values.join('|');
      }).values,
      requiredAwards: const ['BOV', 'BOSV'],
      scopeLabel: 'variety',
    );
  }
  if (requireGroupAwards) {
    validateBuckets(
      buckets: buckets((e) {
        final values = [sectionId(e), breed(e), group(e)];
        return values.any((value) => value.isEmpty) ? '' : values.join('|');
      }).values,
      requiredAwards: const ['BOG', 'BOSG'],
      scopeLabel: 'group',
    );
  }
  if (requireBreedAwards) {
    validateBuckets(
      buckets: buckets((e) {
        final values = [sectionId(e), breed(e)];
        return values.any((value) => value.isEmpty) ? '' : values.join('|');
      }).values,
      requiredAwards: const ['BOB', 'BOSB'],
      scopeLabel: 'breed',
    );
  }

  return issues;
}
