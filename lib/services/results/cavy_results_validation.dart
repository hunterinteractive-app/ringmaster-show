import '../results_entry_validation.dart';

List<ResultsEntryBlockingIssue> validateCavyResults({
  required List<Map<String, dynamic>> entries,
  bool requireVarietyAwards = false,
  bool requireGroupAwards = false,
  required bool requireBreedAwards,
  required bool Function(Map<String, dynamic>) hasBasicOutcome,
  required bool Function(Map<String, dynamic>) isEligibleForSpecialAward,
  required bool Function(Map<String, dynamic>) isExcludedFromSpecials,
  required List<String> Function(Map<String, dynamic>) awardCodes,
  required String Function(Map<String, dynamic>) entryLabel,
  required String Function(Map<String, dynamic>) sectionId,
  required String Function(Map<String, dynamic>) breed,
  String Function(Map<String, dynamic>)? variety,
  String Function(Map<String, dynamic>)? group,
  String Function(Map<String, dynamic>)? className,
  required String Function(Map<String, dynamic>) sex,
}) {
  final issues = <ResultsEntryBlockingIssue>[];
  final requiresVarietyAwards = requireVarietyAwards || requireGroupAwards;
  final varietyValue =
      variety ??
      group ??
      (entry) => (entry['variety'] ?? entry['variety_name'] ?? '').toString();
  final classValue =
      className ?? (entry) => (entry['class_name'] ?? '').toString();
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

  final normal = entries
      .where((entry) => !isExcludedFromSpecials(entry))
      .toList();

  Map<String, List<Map<String, dynamic>>> buckets(
    String Function(Map<String, dynamic>) scope,
  ) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in normal) {
      final key = scope(entry);
      if (key.isNotEmpty) result.putIfAbsent(key, () => []).add(entry);
    }
    return result;
  }

  void validateBuckets({
    required Iterable<List<Map<String, dynamic>>> values,
    required List<String> requiredAwards,
    required String scopeLabel,
    required ResultsValidationIssueLevel level,
  }) {
    for (final bucket in values) {
      if (bucket.isEmpty) continue;
      final eligible = bucket.where(isEligibleForSpecialAward).toList();
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
                  '$award is assigned to more than one cavy in this $scopeLabel: ${entryLabel(winners[0])} and ${entryLabel(winners[1])}.',
              entry: winners[0],
              conflictsWith: winners[1],
              level: level,
              awardCode: award,
            ),
          );
        }
      }
      if (!allBasicsComplete || eligible.isEmpty) continue;
      final primary = requiredAwards.first;
      final primaryWinner = bucket
          .where((entry) => awardCodes(entry).contains(primary))
          .firstOrNull;
      if (primaryWinner == null) {
        issues.add(
          ResultsEntryBlockingIssue(
            code: 'missing_${primary.toLowerCase()}',
            title: 'Missing $primary winner',
            message:
                'Select one eligible $primary winner for this cavy $scopeLabel.',
            entry: eligible.first,
            level: level,
            awardCode: primary,
          ),
        );
        continue;
      }
      final opposite = requiredAwards[1];
      final primarySex = sex(primaryWinner);
      final oppositeCandidates = eligible.where(
        (entry) =>
            !identical(entry, primaryWinner) &&
            primarySex.isNotEmpty &&
            sex(entry).isNotEmpty &&
            sex(entry) != primarySex,
      );
      final oppositeWinner = bucket
          .where((entry) => awardCodes(entry).contains(opposite))
          .firstOrNull;
      if (oppositeCandidates.isNotEmpty && oppositeWinner == null) {
        issues.add(
          ResultsEntryBlockingIssue(
            code: 'missing_${opposite.toLowerCase()}',
            title: 'Missing $opposite winner',
            message:
                'Select the eligible opposite-sex $opposite winner for this cavy $scopeLabel.',
            entry: oppositeCandidates.first,
            level: level,
            awardCode: opposite,
          ),
        );
      }
    }
  }

  if (requiresVarietyAwards) {
    validateBuckets(
      values: buckets((entry) {
        final scope = [sectionId(entry), breed(entry), varietyValue(entry)];
        return scope.any((value) => value.isEmpty) ? '' : scope.join('|');
      }).values,
      requiredAwards: const ['BOV', 'BOSV'],
      scopeLabel: 'variety',
      level: ResultsValidationIssueLevel.variety,
    );
  }

  void validateAgeWinners({
    required Iterable<List<Map<String, dynamic>>> values,
    required Map<String, String> awardsByAge,
    required String scopeLabel,
    required ResultsValidationIssueLevel level,
  }) {
    for (final bucket in values) {
      for (final age in awardsByAge.entries) {
        final ageEntries = bucket.where((entry) {
          final normalized = classValue(entry).trim().toLowerCase();
          return normalized.contains(age.key);
        }).toList();
        final eligible = ageEntries.where(isEligibleForSpecialAward).toList();
        final winners = ageEntries
            .where((entry) => awardCodes(entry).contains(age.value))
            .toList();
        if (winners.length > 1) {
          issues.add(
            ResultsEntryBlockingIssue(
              code: 'duplicate_${age.value.toLowerCase()}',
              title: 'Duplicate ${age.value} winner',
              message:
                  '${age.value} is assigned to more than one cavy in this $scopeLabel: ${entryLabel(winners[0])} and ${entryLabel(winners[1])}.',
              entry: winners[0],
              conflictsWith: winners[1],
              level: level,
              awardCode: age.value,
            ),
          );
        }
        if (!allBasicsComplete || eligible.isEmpty || winners.isNotEmpty) {
          continue;
        }
        issues.add(
          ResultsEntryBlockingIssue(
            code: 'missing_${age.value.toLowerCase()}',
            title: 'Missing ${age.value} winner',
            message:
                'Select one eligible ${age.value} winner for this cavy $scopeLabel.',
            entry: eligible.first,
            level: level,
            awardCode: age.value,
          ),
        );
      }
    }
  }

  if (requiresVarietyAwards) {
    validateAgeWinners(
      values: buckets((entry) {
        final scope = [sectionId(entry), breed(entry), varietyValue(entry)];
        return scope.any((value) => value.isEmpty) ? '' : scope.join('|');
      }).values,
      awardsByAge: const {
        'junior': 'BJV',
        'intermediate': 'BIV',
        'senior': 'BSV',
      },
      scopeLabel: 'variety',
      level: ResultsValidationIssueLevel.variety,
    );
  }
  if (requireBreedAwards) {
    validateAgeWinners(
      values: buckets((entry) {
        final scope = [sectionId(entry), breed(entry)];
        return scope.any((value) => value.isEmpty) ? '' : scope.join('|');
      }).values,
      awardsByAge: const {
        'junior': 'BJB',
        'intermediate': 'BIB',
        'senior': 'BSB',
      },
      scopeLabel: 'breed',
      level: ResultsValidationIssueLevel.breed,
    );
  }
  if (requireBreedAwards) {
    validateBuckets(
      values: buckets((entry) {
        final scope = [sectionId(entry), breed(entry)];
        return scope.any((value) => value.isEmpty) ? '' : scope.join('|');
      }).values,
      requiredAwards: const ['BOB', 'BOSB'],
      scopeLabel: 'breed',
      level: ResultsValidationIssueLevel.breed,
    );
  }
  return issues;
}
