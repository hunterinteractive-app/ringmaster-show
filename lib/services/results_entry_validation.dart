import 'results/results_rules.dart';
import 'results_group_resolution.dart';
import 'results/rabbit_results_structure.dart';

enum ResultsValidationIssueLevel { entry, variety, group, breed, section }

class ResultsEntryStatusSummary {
  final int completed;
  final int total;
  final int validationIssueCount;

  const ResultsEntryStatusSummary({
    required this.completed,
    required this.total,
    required this.validationIssueCount,
  });

  bool get dataEntryComplete => total > 0 && completed == total;
  bool get needsAttention => dataEntryComplete && validationIssueCount > 0;
  String get completionLabel => dataEntryComplete
      ? 'Results complete'
      : completed == 0
      ? 'Not started'
      : 'In progress';
}

ResultsEntryStatusSummary buildResultsEntryStatusSummary({
  required List<Map<String, dynamic>> entries,
  required bool Function(Map<String, dynamic>) hasBasicOutcome,
  required int validationIssueCount,
}) {
  return ResultsEntryStatusSummary(
    completed: entries.where(hasBasicOutcome).length,
    total: entries.length,
    validationIssueCount: validationIssueCount,
  );
}

String resultsEntryId(Map<String, dynamic> entry) {
  return (entry['entry_id'] ?? entry['id'] ?? '').toString().trim();
}

String resultsBreedScopeForEntry(Map<String, dynamic> entry) {
  final id = (entry['breed_id'] ?? entry['breed_catalog_id'] ?? '')
      .toString()
      .trim();
  if (id.isNotEmpty) return id.toLowerCase();
  return (entry['breed'] ?? entry['breed_name'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
}

String resultsGroupScopeForEntry(Map<String, dynamic> entry) {
  return switch (resultsSpeciesForEntry(entry)) {
    'cavy' => resolveCavyGroup(entry).normalizedKey,
    'rabbit' => resolveRabbitGroup(entry).stableKey,
    _ => '',
  };
}

class ResultsEntryBlockingIssue {
  final String code;
  final String title;
  final String message;
  final Map<String, dynamic> entry;
  final Map<String, dynamic>? conflictsWith;
  final ResultsValidationIssueLevel level;
  final String awardCode;
  final String sectionId;
  final String breedScope;
  final String groupScope;
  final Set<String> entryIds;

  ResultsEntryBlockingIssue({
    required this.code,
    required this.title,
    required this.message,
    required this.entry,
    this.conflictsWith,
    this.level = ResultsValidationIssueLevel.entry,
    this.awardCode = '',
    String? sectionId,
    String? breedScope,
    String? groupScope,
    Set<String>? entryIds,
  }) : sectionId = sectionId ?? resultsSectionScopeForEntry(entry),
       breedScope = breedScope ?? resultsBreedScopeForEntry(entry),
       groupScope = groupScope ?? resultsGroupScopeForEntry(entry),
       entryIds =
           entryIds ??
           {
             resultsEntryId(entry),
             if (conflictsWith != null) resultsEntryId(conflictsWith),
           }.where((id) => id.isNotEmpty).toSet();
}

bool resultsIssueAppliesToEntries(
  ResultsEntryBlockingIssue issue,
  List<Map<String, dynamic>> entries,
) {
  if (entries.isEmpty) return false;
  final ids = entries.map(resultsEntryId).where((id) => id.isNotEmpty).toSet();
  if (issue.entryIds.intersection(ids).isNotEmpty) return true;

  final breeds = entries.map(resultsBreedScopeForEntry).toSet();
  final sections = entries.map(resultsSectionScopeForEntry).toSet();
  return issue.level != ResultsValidationIssueLevel.section &&
      issue.breedScope.isNotEmpty &&
      breeds.contains(issue.breedScope) &&
      (issue.sectionId.isEmpty || sections.contains(issue.sectionId));
}

bool resultsIssueAppliesToGroup(
  ResultsEntryBlockingIssue issue,
  List<Map<String, dynamic>> entries,
) {
  if (issue.level == ResultsValidationIssueLevel.breed ||
      issue.level == ResultsValidationIssueLevel.section) {
    return false;
  }
  if (!resultsIssueAppliesToEntries(issue, entries)) return false;
  final groups = entries.map(resultsGroupScopeForEntry).toSet();
  return issue.groupScope.isEmpty || groups.contains(issue.groupScope);
}

String normalizeResultsSpecies(Object? value) {
  final species = (value ?? '').toString().trim().toLowerCase();
  if (species == 'rabbit' || species == 'rabbits') return 'rabbit';
  if (species == 'cavy' || species == 'cavies') return 'cavy';
  return species;
}

String resultsSpeciesForEntry(Map<String, dynamic> entry) {
  return normalizeResultsSpeciesStrict(entry['species']);
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

List<ResultsEntryBlockingIssue> buildOppositeSexAwardIssues({
  required List<Map<String, dynamic>> entries,
  required String winnerCode,
  required String oppositeCode,
  required String scopeLabel,
  required List<String> Function(Map<String, dynamic>) awardCodes,
  required String Function(Map<String, dynamic>) scopeKey,
  required String Function(Map<String, dynamic>) sex,
  required String Function(Map<String, dynamic>) entryLabel,
}) {
  final winners = <String, Map<String, dynamic>>{};
  final opposites = <String, Map<String, dynamic>>{};

  for (final entry in entries) {
    final scope = scopeKey(entry).trim().toLowerCase();
    if (scope.isEmpty) continue;
    final awards = awardCodes(
      entry,
    ).map((award) => award.trim().toUpperCase()).toSet();
    if (awards.contains(winnerCode.toUpperCase())) winners[scope] = entry;
    if (awards.contains(oppositeCode.toUpperCase())) opposites[scope] = entry;
  }

  final issues = <ResultsEntryBlockingIssue>[];
  for (final scope in {...winners.keys, ...opposites.keys}) {
    final winner = winners[scope];
    final opposite = opposites[scope];
    if (winner == null || opposite == null) continue;
    final winnerSex = sex(winner).trim().toLowerCase();
    final oppositeSex = sex(opposite).trim().toLowerCase();
    if (winnerSex.isEmpty || oppositeSex.isEmpty || winnerSex != oppositeSex) {
      continue;
    }
    issues.add(
      ResultsEntryBlockingIssue(
        code: 'opposite_sex',
        title: '$winnerCode / $oppositeCode sex conflict',
        message:
            '${entryLabel(winner)} and ${entryLabel(opposite)} are both marked for $winnerCode / $oppositeCode in the same $scopeLabel, but are not opposite sex.',
        entry: winner,
        conflictsWith: opposite,
        level: switch (scopeLabel) {
          'group' => ResultsValidationIssueLevel.group,
          'variety' => ResultsValidationIssueLevel.variety,
          'breed' => ResultsValidationIssueLevel.breed,
          _ => ResultsValidationIssueLevel.entry,
        },
        awardCode: '$winnerCode/$oppositeCode',
      ),
    );
  }
  return issues;
}
