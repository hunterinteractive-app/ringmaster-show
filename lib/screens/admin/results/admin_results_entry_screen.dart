//lib/screens/admin/results/admin_results_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';
import 'package:ringmaster_show/services/app_session.dart';

final supabase = Supabase.instance.client;

const String kDefaultFinalAwardMode = 'four_six_bis';

const List<String> kBestAgeAwardCodes = [
  'Best Junior',
  'Best Intermediate',
  'Best Senior',
];

const List<String> cavyAwardCodes = [
  'BJV',
  'BIV',
  'BSV',
  'BJB',
  'BIB',
  'BSB',
  'BOV',
  'BOSV',
  'BOB',
  'BOSB',
  'BIS',
  'RIS',
  '1RIS',
  '2RIS',
  'HM',
];

const Map<String, String> cavyAwardLabels = {
  'BJV': 'Best Junior Variety',
  'BIV': 'Best Intermediate Variety',
  'BSV': 'Best Senior Variety',

  'BJB': 'Best Junior of Breed',
  'BIB': 'Best Intermediate of Breed',
  'BSB': 'Best Senior of Breed',

  'BOV': 'Best of Variety',
  'BOSV': 'Best Opposite Sex of Variety',

  'BOB': 'Best of Breed',
  'BOSB': 'Best Opposite Sex of Breed',

  'BIS': 'Best in Show',
  'RIS': 'Reserve in Show',
  '1RIS': '1st Reserve in Show',
  '2RIS': '2nd Reserve in Show',
  'HM': 'Honorable Mention',
};

const Map<String, String> awardDisplayLabels = {
  'BOV': 'Best of Variety',
  'BOSV': 'Best Opposite Sex of Variety',
  'BOG': 'Best of Group',
  'BOSG': 'Best Opposite Sex of Group',
  'BOB': 'Best of Breed',
  'BOSB': 'Best Opposite Sex of Breed',
  'Best 4-Class': 'Best 4-Class',
  'Best 6-Class': 'Best 6-Class',
  'Best In Show': 'Best in Show',
  'Reserve In Show': 'Reserve in Show',
  'BIS': 'Best in Show',
  'RIS': 'Reserve in Show',
  '1RIS': '1st Reserve in Show',
  '2RIS': '2nd Reserve in Show',
  'HM': 'Honorable Mention',
};


bool _isFurEntry(Map<String, dynamic> row) {
  final value = row['is_fur'];
  if (value is bool) return value;

  final text = (value ?? '').toString().trim().toLowerCase();
  return text == 'true' || text == 't' || text == '1' || text == 'yes';
}

bool _isFurOrWoolEntry(Map<String, dynamic> row) {
  return _isFurEntry(row);
}

bool _isCavyEntry(Map<String, dynamic> row) {
  final species = (row['species'] ?? '').toString().trim().toLowerCase();

  // Species remains the primary source of truth. Some RPC/result rows do not
  // include species, so fall back to cavy-only sex terminology. Do not fall
  // back to breed name because names such as American overlap with rabbits.
  if (species == 'cavy') return true;
  if (species == 'rabbit') return false;

  final sex = (row['sex'] ?? '').toString().trim().toLowerCase();
  if (sex.contains('boar') || sex.contains('sow')) return true;
  if (sex.contains('buck') || sex.contains('doe')) return false;

  return false;
}

String _awardDisplayLabel(String award, Map<String, dynamic> entry) {
  final code = _canonicalAwardCode(award);

  if (_isCavyEntry(entry)) {
    return cavyAwardLabels[code] ?? code;
  }

  return awardDisplayLabels[code] ?? code;
}

String _canonicalAwardCode(String award) {
  final raw = award.trim();
  final value = raw.toLowerCase();

  if (value == 'best in show' || value == 'best in show rabbit') {
    return 'Best In Show';
  }
  if (value == 'bis') return 'BIS';

  if (value == 'reserve in show' ||
      value == 'reserve best in show' ||
      value == 'reserve in show rabbit') {
    return 'Reserve In Show';
  }
  if (value == 'ris') return 'RIS';

  if (value == '1ris' ||
      value == '1st ris' ||
      value == 'first ris' ||
      value == '1st reserve in show' ||
      value == 'first reserve in show') {
    return '1RIS';
  }

  if (value == '2ris' ||
      value == '2nd ris' ||
      value == 'second ris' ||
      value == '2nd reserve in show' ||
      value == 'second reserve in show') {
    return '2RIS';
  }

  if (value == 'bog' || value == 'best of group') return 'BOG';
  if (value == 'bosg' ||
      value == 'best opposite sex of group' ||
      value == 'best opposite of group') {
    return 'BOSG';
  }

  if (value == 'bov' || value == 'best of variety') return 'BOV';
  if (value == 'bosv' ||
      value == 'best opposite sex of variety' ||
      value == 'best opposite of variety') {
    return 'BOSV';
  }

  if (value == 'bob' || value == 'best of breed') return 'BOB';
  if (value == 'bosb' ||
      value == 'best opposite sex of breed' ||
      value == 'best opposite of breed') {
    return 'BOSB';
  }

  if (value == 'b4c' ||
      value == 'best 4 class' ||
      value == 'best 4-class' ||
      value == 'best four class' ||
      value == 'best four-class') {
    return 'Best 4-Class';
  }
  if (value == 'b6c' ||
      value == 'best 6 class' ||
      value == 'best 6-class' ||
      value == 'best six class' ||
      value == 'best six-class') {
    return 'Best 6-Class';
  }

  return raw;
}

bool _awardListContains(List<String> awards, String award) {
  final target = _canonicalAwardCode(award).toLowerCase();
  return awards.any((a) => _canonicalAwardCode(a).toLowerCase() == target);
}

bool _supportsBestAgeAwards({
  required String breedName,
  required bool isCavy,
}) {
  // Every cavy breed requires Best Junior, Best Intermediate,
  // and Best Senior awards.
  if (isCavy) return true;

  final b = breedName.trim().toLowerCase();
  return b == 'american sable' ||
      b == 'american sables' ||
      b == 'himalayan' ||
      b == 'checkered giant';
}

// Helper to check if a class name is a Pre-Junior class
bool _isPreJuniorClassName(String className) {
  final lower = className.trim().toLowerCase();
  return lower.contains('pre-junior') ||
      lower.contains('pre junior') ||
      lower.contains('prejunior') ||
      lower.startsWith('pre jr') ||
      lower.startsWith('pre-jr');
}

bool _bestAgeAwardMatchesClass({
  required String award,
  required String className,
  required String classSystem,
}) {
  final c = className.trim().toLowerCase();
  if (award == 'Best Junior') {
    return c.contains('junior') && !_isPreJuniorClassName(className);
  }

  if (award == 'Best Senior') {
    return c.contains('senior');
  }

  if (award == 'Best Intermediate') {
    return classSystem == 'six' && c.contains('intermediate');
  }

  return false;
}

const List<String> kResultStatuses = [
  'Shown',
  'No Show',
  'Disqualified - Wrong Sex',
  'Disqualified - Wrong Variety',
  'Disqualified - Wrong Class',
  'Disqualified - Overweight',
  'Disqualified - Wrong Tattoo',
  'Disqualified - Other',
  'Unworthy of Award',
];


bool _isDisqualifiedStatus(String status) {
  return status.trim().toLowerCase().startsWith('disqualified');
}

// --- Shared Smart Completion/Status Helpers for Results Entry Highlighting ---

enum _ResultScopeStatus {
  notStarted,
  inProgress,
  needsAttention,
  complete,
}

class _ResultScopeCompletion {
  final _ResultScopeStatus status;
  final int completedBasics;
  final int totalBasics;

  const _ResultScopeCompletion({
    required this.status,
    required this.completedBasics,
    required this.totalBasics,
  });
}

bool _entryHasBasicOutcome(Map<String, dynamic> entry) {
  final placement = (entry['placement'] ?? '').toString().trim();
  final status = (entry['result_status'] ?? '').toString().trim();
  final isShown = entry['is_shown'];
  final isDisqualified = entry['is_disqualified'];
  final dqReason = (entry['disqualified_reason'] ?? '').toString().trim();
  final scratchedAt = (entry['scratched_at'] ?? '').toString().trim();

  if (placement.isNotEmpty) return true;
  if (scratchedAt.isNotEmpty) return true;
  if (isShown == false) return true;
  if (isDisqualified == true) return true;
  if (dqReason.isNotEmpty) return true;

  return status == 'No Show' ||
      status == 'Scratched' ||
      status == 'Unworthy of Award' ||
      _isDisqualifiedStatus(status);
}

bool _entryHasAnyResultOrAwardData(Map<String, dynamic> entry) {
  final resultStatus = (entry['result_status'] ?? '').toString().trim();
  final enteredAt = (entry['result_entered_at'] ?? '').toString().trim();
  final awards = ((entry['_awards'] as List?) ?? const [])
      .map((x) => x.toString().trim())
      .where((x) => x.isNotEmpty)
      .toList();

  return _entryHasBasicOutcome(entry) ||
      resultStatus.isNotEmpty ||
      enteredAt.isNotEmpty ||
      awards.isNotEmpty;
}

String _entryScopeSectionId(Map<String, dynamic> entry) {
  return (entry['section_id'] ?? '').toString().trim().toLowerCase();
}

String _entryScopeBreed(Map<String, dynamic> entry) {
  final rawBreed = (entry['breed'] ?? '').toString().trim();
  if (rawBreed.isNotEmpty) return rawBreed.toLowerCase();
  return (entry['breed_name'] ?? '').toString().trim().toLowerCase();
}

String _entryScopeVariety(Map<String, dynamic> entry) {
  final rawVariety = (entry['variety'] ?? '').toString().trim();
  if (rawVariety.isNotEmpty) return rawVariety.toLowerCase();
  return (entry['variety_name'] ?? '').toString().trim().toLowerCase();
}

String _entryScopeGroup(Map<String, dynamic> entry) {
  return (
    entry['group_name'] ??
    entry['group_display_name'] ??
    entry['group_label'] ??
    entry['group'] ??
    entry['group_code'] ??
    ''
  ).toString().trim().toLowerCase();
}

bool _entryUsesVarietyAwards(Map<String, dynamic> entry) {
  final raw = entry['uses_variety_awards'];
  return raw == true ||
      raw.toString().trim().toLowerCase() == 'true' ||
      raw.toString().trim().toLowerCase() == 't' ||
      raw.toString().trim() == '1';
}

bool _entryUsesGroupAwards(Map<String, dynamic> entry) {
  final raw = entry['uses_group_awards'];
  return raw == true ||
      raw.toString().trim().toLowerCase() == 'true' ||
      raw.toString().trim().toLowerCase() == 't' ||
      raw.toString().trim() == '1';
}

List<String> _entryAwardCodes(Map<String, dynamic> entry) {
  return ((entry['_awards'] as List?) ?? const [])
      .map((x) => _canonicalAwardCode(x.toString()))
      .where((x) => x.trim().isNotEmpty)
      .toList();
}

int _awardCount(List<Map<String, dynamic>> entries, String awardCode) {
  final target = _canonicalAwardCode(awardCode).toLowerCase();
  return entries.where((entry) {
    return _entryAwardCodes(entry).any(
      (award) => _canonicalAwardCode(award).toLowerCase() == target,
    );
  }).length;
}

String _entryShortAnimalLabel(Map<String, dynamic> entry) {
  final coopNumber = (entry['coop_number'] ?? '').toString().trim();
  final animalName = (entry['animal_name'] ?? '').toString().trim();
  final tattoo = (entry['tattoo'] ?? '').toString().trim();

  String animalLabel;
  if (animalName.isNotEmpty && tattoo.isNotEmpty) {
    animalLabel = '$animalName / $tattoo';
  } else if (animalName.isNotEmpty) {
    animalLabel = animalName;
  } else if (tattoo.isNotEmpty) {
    animalLabel = tattoo;
  } else {
    final exhibitor = (entry['exhibitor_label'] ?? '').toString().trim();
    animalLabel = exhibitor.isNotEmpty ? exhibitor : 'Selected';
  }

  return coopNumber.isEmpty ? animalLabel : 'Coop $coopNumber • $animalLabel';
}

String _specialsSummaryForEntries(
  List<Map<String, dynamic>> entries,
  List<String> awardCodes,
) {
  final parts = <String>[];

  for (final awardCode in awardCodes) {
    final target = _canonicalAwardCode(awardCode).toLowerCase();
    final winners = entries.where((entry) {
      return _entryAwardCodes(entry).any(
        (award) => _canonicalAwardCode(award).toLowerCase() == target,
      );
    }).toList();

    if (winners.isEmpty) continue;

    final labels = winners.map(_entryShortAnimalLabel).toList();
    parts.add('${_awardDisplayLabel(awardCode, winners.first)}: ${labels.join(', ')}');
  }

  if (parts.isEmpty) return '';
  return 'Specials: ${parts.join(' • ')}';
}

Map<String, List<Map<String, dynamic>>> _bucketEntries(
  List<Map<String, dynamic>> entries,
  String Function(Map<String, dynamic>) keyBuilder,
) {
  final buckets = <String, List<Map<String, dynamic>>>{};
  for (final entry in entries) {
    final key = keyBuilder(entry);
    if (key.trim().isEmpty) continue;
    buckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
    buckets[key]!.add(entry);
  }
  return buckets;
}

String _entrySexKey(Map<String, dynamic> entry) {
  final sex = (entry['sex'] ?? '').toString().trim().toLowerCase();
  if (sex.contains('buck') || sex.contains('boar')) return 'male';
  if (sex.contains('doe') || sex.contains('sow')) return 'female';
  return '';
}

bool _entryIsEligibleForSpecialAward(Map<String, dynamic> entry) {
  final scratched = (entry['scratched_at'] ?? '').toString().trim().isNotEmpty;
  if (scratched) return false;

  final className = (entry['class_name'] ?? '').toString().trim();
  if (_isPreJuniorClassName(className)) return false;

  final placement = (entry['placement'] ?? '').toString().trim();
  final status = (entry['result_status'] ?? '').toString().trim();
  final isShown = entry['is_shown'];
  final isDisqualified = entry['is_disqualified'];

  if (isShown == false) return false;
  if (isDisqualified == true) return false;
  if (status == 'No Show' ||
      status == 'Unworthy of Award' ||
      _isDisqualifiedStatus(status)) {
    return false;
  }

  // In this workflow, specials can only be selected on first-place animals.
  return placement == '1';
}

Map<String, dynamic>? _singleAwardWinner(
  List<Map<String, dynamic>> entries,
  String awardCode,
) {
  final target = _canonicalAwardCode(awardCode).toLowerCase();
  for (final entry in entries) {
    final hasAward = _entryAwardCodes(entry).any(
      (award) => _canonicalAwardCode(award).toLowerCase() == target,
    );
    if (hasAward) return entry;
  }
  return null;
}

bool _hasEligibleOppositeSexCandidate(
  List<Map<String, dynamic>> entries,
  Map<String, dynamic> winner,
) {
  final winnerId = (winner['entry_id'] ?? winner['id'] ?? '').toString().trim();
  final winnerSex = _entrySexKey(winner);
  if (winnerSex.isEmpty) return false;

  for (final entry in entries) {
    final entryId = (entry['entry_id'] ?? entry['id'] ?? '').toString().trim();
    if (entryId.isNotEmpty && entryId == winnerId) continue;
    if (!_entryIsEligibleForSpecialAward(entry)) continue;

    final entrySex = _entrySexKey(entry);
    if (entrySex.isNotEmpty && entrySex != winnerSex) return true;
  }

  return false;
}

bool _requiredAwardCountsAreValid({
  required Iterable<List<Map<String, dynamic>>> buckets,
  required List<String> awardCodes,
  required bool enforceMissing,
}) {
  for (final bucket in buckets) {
    if (bucket.isEmpty) continue;

    for (final awardCode in awardCodes) {
      final count = _awardCount(bucket, awardCode);

      // Duplicate awards are always an error once they exist.
      if (count > 1) return false;
    }

    if (!enforceMissing) continue;

    final eligibleCandidates = bucket.where(_entryIsEligibleForSpecialAward).toList();

    // If every animal in the scope is DQ, No Show, Unworthy, scratched, or otherwise
    // has no first-place animal, there is no special award to require.
    if (eligibleCandidates.isEmpty) continue;

    if (awardCodes.length >= 2) {
      final primaryAward = awardCodes[0];
      final oppositeAward = awardCodes[1];

      final primaryCount = _awardCount(bucket, primaryAward);
      if (primaryCount != 1) return false;

      final primaryWinner = _singleAwardWinner(bucket, primaryAward);
      if (primaryWinner == null) return false;

      final oppositeCount = _awardCount(bucket, oppositeAward);
      final hasOppositeCandidate = _hasEligibleOppositeSexCandidate(
        eligibleCandidates,
        primaryWinner,
      );

      // BOS/BOSV/BOSG is only required when there is an eligible opposite-sex animal.
      if (hasOppositeCandidate && oppositeCount != 1) return false;

      // If an opposite award exists when no opposite-sex candidate exists, it is still
      // bad data and should flag red.
      if (!hasOppositeCandidate && oppositeCount > 0) return false;

      continue;
    }

    for (final awardCode in awardCodes) {
      if (_awardCount(bucket, awardCode) != 1) return false;
    }
  }

  return true;
}

_ResultScopeCompletion _resultCompletionForEntries(
  List<Map<String, dynamic>> entries, {
  required bool requireVarietyAwards,
  required bool requireGroupAwards,
  required bool requireBreedAwards,
}) {
  final totalBasics = entries.length;
  final completedBasics = entries.where(_entryHasBasicOutcome).length;
  final anyData = entries.any(_entryHasAnyResultOrAwardData);

  if (entries.isEmpty || !anyData) {
    return _ResultScopeCompletion(
      status: _ResultScopeStatus.notStarted,
      completedBasics: completedBasics,
      totalBasics: totalBasics,
    );
  }

  final allBasicsComplete = totalBasics > 0 && completedBasics >= totalBasics;
  // Only entries eligible for specials should be used when deciding whether
  // BOV/BOSV, BOG/BOSG, or BOB/BOSB are required. Pre-Junior entries still
  // count toward basic result completion, but they cannot force opposite-sex
  // specials like BOSB.
  final normalEntries = entries.where((entry) {
    if (_isFurEntry(entry)) return false;
    if (_isPreJuniorClassName((entry['class_name'] ?? '').toString())) {
      return false;
    }
    return true;
  }).toList();

  bool awardCountsValid = true;

  if (normalEntries.isNotEmpty && requireVarietyAwards) {
    final varietyBuckets = _bucketEntries(normalEntries, (entry) {
      final sectionId = _entryScopeSectionId(entry);
      final breed = _entryScopeBreed(entry);
      final variety = _entryScopeVariety(entry);
      if (sectionId.isEmpty || breed.isEmpty || variety.isEmpty) return '';
      return '$sectionId|$breed|$variety';
    });

    awardCountsValid = awardCountsValid &&
        _requiredAwardCountsAreValid(
          buckets: varietyBuckets.values,
          awardCodes: const ['BOV', 'BOSV'],
          enforceMissing: allBasicsComplete,
        );
  }

  if (normalEntries.isNotEmpty && requireGroupAwards) {
    final groupBuckets = _bucketEntries(normalEntries, (entry) {
      final sectionId = _entryScopeSectionId(entry);
      final breed = _entryScopeBreed(entry);
      final group = _entryScopeGroup(entry);
      if (sectionId.isEmpty || breed.isEmpty || group.isEmpty) return '';
      return '$sectionId|$breed|$group';
    });

    awardCountsValid = awardCountsValid &&
        _requiredAwardCountsAreValid(
          buckets: groupBuckets.values,
          awardCodes: const ['BOG', 'BOSG'],
          enforceMissing: allBasicsComplete,
        );
  }

  if (normalEntries.isNotEmpty && requireBreedAwards) {
    final breedBuckets = _bucketEntries(normalEntries, (entry) {
      final sectionId = _entryScopeSectionId(entry);
      final breed = _entryScopeBreed(entry);
      if (sectionId.isEmpty || breed.isEmpty) return '';
      return '$sectionId|$breed';
    });

    awardCountsValid = awardCountsValid &&
        _requiredAwardCountsAreValid(
          buckets: breedBuckets.values,
          awardCodes: const ['BOB', 'BOSB'],
          enforceMissing: allBasicsComplete,
        );
  }

  if (!awardCountsValid) {
    return _ResultScopeCompletion(
      status: _ResultScopeStatus.needsAttention,
      completedBasics: completedBasics,
      totalBasics: totalBasics,
    );
  }

  if (!allBasicsComplete) {
    return _ResultScopeCompletion(
      status: _ResultScopeStatus.inProgress,
      completedBasics: completedBasics,
      totalBasics: totalBasics,
    );
  }

  return _ResultScopeCompletion(
    status: _ResultScopeStatus.complete,
    completedBasics: completedBasics,
    totalBasics: totalBasics,
  );
}

String _resultScopeStatusLabel(_ResultScopeStatus status) {
  switch (status) {
    case _ResultScopeStatus.complete:
      return 'Complete';
    case _ResultScopeStatus.needsAttention:
      return 'Needs Attention';
    case _ResultScopeStatus.inProgress:
      return 'In Progress';
    case _ResultScopeStatus.notStarted:
      return 'Not Started';
  }
}

IconData _resultScopeStatusIcon(_ResultScopeStatus status) {
  switch (status) {
    case _ResultScopeStatus.complete:
      return Icons.check_circle;
    case _ResultScopeStatus.needsAttention:
      return Icons.error;
    case _ResultScopeStatus.inProgress:
      return Icons.pending;
    case _ResultScopeStatus.notStarted:
      return Icons.radio_button_unchecked;
  }
}

Color _resultScopeStatusColor(BuildContext context, _ResultScopeStatus status) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (status) {
    case _ResultScopeStatus.complete:
      return Colors.green;
    case _ResultScopeStatus.needsAttention:
      return Colors.red;
    case _ResultScopeStatus.inProgress:
      return Colors.orange;
    case _ResultScopeStatus.notStarted:
      return colorScheme.onSurfaceVariant;
  }
}

String _dqReasonFromStatus(String status) {
  final trimmed = status.trim();
  if (!_isDisqualifiedStatus(trimmed)) return '';

  final parts = trimmed.split('-');
  if (parts.length < 2) return 'Other';

  final reason = parts.sublist(1).join('-').trim();
  return reason.isEmpty ? 'Other' : reason;
}

int _resultSortValue(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 9999;
}

String _resultSortText(dynamic value) {
  return (value ?? '').toString().trim().toLowerCase();
}

String _entryId(Map<String, dynamic> row) {
  return (row['entry_id'] ?? row['id'] ?? '').toString().trim();
}

List<Map<String, dynamic>> _mergeRefreshedEntriesWithoutDroppingCurrentRows({
  required List<Map<String, dynamic>> currentEntries,
  required List<Map<String, dynamic>> refreshedEntries,
}) {
  final refreshedById = <String, Map<String, dynamic>>{};

  for (final e in refreshedEntries) {
    final id = _entryId(e);
    if (id.isNotEmpty) refreshedById[id] = e;
  }

  return currentEntries.map((current) {
    final id = _entryId(current);
    if (id.isEmpty) return current;

    final refreshed = refreshedById[id];
    if (refreshed == null) return current;

    return <String, dynamic>{
      ...current,
      ...refreshed,
    };
  }).toList();
}

/// App-side de-duplication of results entry rows.
List<Map<String, dynamic>> _dedupeResultsEntryRows(
  List<Map<String, dynamic>> rows,
) {
  final byKey = <String, Map<String, dynamic>>{};

  for (final row in rows) {
    final entryId = (row['entry_id'] ?? row['id'] ?? '').toString().trim();
    final isFurEntry = _isFurEntry(row);
    final isFur = isFurEntry ? 'fur' : 'normal';
    final furVariety = (row['fur_variety'] ?? '').toString().trim().toLowerCase();

    // Keep true fur/wool rows separate only when the actual row is marked as fur.
    // Normal entry duplicates should collapse by entry_id even if a bad SQL join
    // returned different breed/group metadata on one of the duplicate rows.
    final key = entryId.isNotEmpty
        ? (isFurEntry ? '$entryId|fur|$furVariety' : entryId)
        : [
            (row['section_id'] ?? '').toString().trim().toLowerCase(),
            (row['exhibitor_id'] ?? '').toString().trim().toLowerCase(),
            (row['breed'] ?? row['breed_name'] ?? '').toString().trim().toLowerCase(),
            (row['variety'] ?? row['variety_name'] ?? '').toString().trim().toLowerCase(),
            (row['class_name'] ?? '').toString().trim().toLowerCase(),
            (row['sex'] ?? '').toString().trim().toLowerCase(),
            isFur,
            furVariety,
          ].join('|');

    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = row;
      continue;
    }

    // Prefer the row that has the clearest breed award settings populated.
    final existingHasAwardSettings =
        existing['uses_group_awards'] == true || existing['uses_variety_awards'] == true;
    final rowHasAwardSettings =
        row['uses_group_awards'] == true || row['uses_variety_awards'] == true;

    if (!existingHasAwardSettings && rowHasAwardSettings) {
      byKey[key] = row;
    }
  }

  return byKey.values.toList();
}

Future<Map<String, List<String>>> _loadAwardsByEntryId({
  required String showId,
  required Iterable<String> entryIds,
}) async {
  final ids = entryIds
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toSet()
      .toList();

  final awardsByEntryId = <String, List<String>>{};

  for (var i = 0; i < ids.length; i += 100) {
    final chunk = ids.skip(i).take(100).toList();

    final awardRows = await supabase
        .from('entry_awards')
        .select('entry_id,award_code')
        .eq('show_id', showId)
        .inFilter('entry_id', chunk);

    for (final raw in awardRows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final entryId = (row['entry_id'] ?? '').toString().trim();
      final award = _canonicalAwardCode(
        (row['award_code'] ?? '').toString(),
      );

      if (entryId.isEmpty || award.isEmpty) continue;

      awardsByEntryId.putIfAbsent(entryId, () => <String>[]);
      awardsByEntryId[entryId]!.add(award);
    }
  }

  return awardsByEntryId;
}

class AdminResultsEntryScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String? initialEntryId;
  final bool isQrEntryMode;
  

  const AdminResultsEntryScreen({
    super.key,
    required this.showId,
    required this.showName,
    this.initialEntryId,
    this.isQrEntryMode = false,
  });

  @override
  State<AdminResultsEntryScreen> createState() => _AdminResultsEntryScreenState();
}

class _AdminResultsEntryScreenState extends State<AdminResultsEntryScreen> {
  bool _didAutoOpenInitialEntryFromRoot = false;
  bool _loading = true;
  String? _msg;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _judges = [];

  final Map<String, String> _breedClassSystems = {};
  final Map<String, bool> _breedUsesGroupAwards = {};
  final Map<String, bool> _breedUsesVarietyAwards = {};
  String _finalAwardMode = kDefaultFinalAwardMode;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

    Future<void> _loadAll() async {
      setState(() {
        _loading = true;
        _msg = null;
      });

      try {
        await _loadSections();
        await _loadJudges();
        await _loadBreedClassSystems();
        await _loadShowSettings();
        await _loadEntries();

        if (!mounted) return;

        setState(() => _loading = false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openInitialEntryFromRootIfNeeded();
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _msg = 'Load failed: $e';
        });
      }
    }

  Future<void> _loadSections() async {
    final rows = await supabase
        .from('show_sections')
        .select('id,letter,display_name,kind,is_enabled,sort_order')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true);

    _sections = (rows as List).cast<Map<String, dynamic>>();

    _sections.sort((a, b) {
      int kindRank(String k) {
        switch (k) {
          case 'open':
            return 0;
          case 'youth':
            return 1;
          default:
            return 99;
        }
      }

      final ak = (a['kind'] ?? '').toString().toLowerCase();
      final bk = (b['kind'] ?? '').toString().toLowerCase();

      final kr = kindRank(ak).compareTo(kindRank(bk));
      if (kr != 0) return kr;

      final aso = a['sort_order'];
      final bso = b['sort_order'];
      final asoI = (aso is int) ? aso : int.tryParse(aso?.toString() ?? '') ?? 9999;
      final bsoI = (bso is int) ? bso : int.tryParse(bso?.toString() ?? '') ?? 9999;
      final soCmp = asoI.compareTo(bsoI);
      if (soCmp != 0) return soCmp;

      final al = (a['letter'] ?? '').toString().toUpperCase();
      final bl = (b['letter'] ?? '').toString().toUpperCase();
      return al.compareTo(bl);
    });

    _selectedSectionId ??= _sections.isEmpty
        ? ''
        : (_sections.first['id'] ?? '').toString();
  }

  Future<void> _loadJudges() async {
    final rows = await supabase
        .from('judge_assignments')
        .select(
          'id,judge_id,assignment_label,'
          'judges(id,display_name,name,first_name,last_name,judge_type,is_active,arba_judge_number)',
        )
        .eq('show_id', widget.showId);

    final result = <Map<String, dynamic>>[];

    for (final raw in (rows as List)) {
      final map = Map<String, dynamic>.from(raw as Map);
      final judge = map['judges'];

      final assignmentId = (map['id'] ?? '').toString().trim();
      final masterJudgeId = (map['judge_id'] ?? '').toString().trim();

      // We need a real judge id to save into entries.judged_by_show_judge_id.
      if (masterJudgeId.isEmpty) continue;

      String label = '';

      if (judge is Map) {
        final judgeMap = Map<String, dynamic>.from(judge);
        final displayName = (judgeMap['display_name'] ?? '').toString().trim();
        final name = (judgeMap['name'] ?? '').toString().trim();
        final first = (judgeMap['first_name'] ?? '').toString().trim();
        final last = (judgeMap['last_name'] ?? '').toString().trim();
        final arbaNumber =
            (judgeMap['arba_judge_number'] ?? '').toString().trim();

        final baseName = displayName.isNotEmpty
            ? displayName
            : name.isNotEmpty
                ? name
                : [first, last].where((x) => x.isNotEmpty).join(' ').trim();

        label = baseName.isNotEmpty ? baseName : masterJudgeId;

        if (arbaNumber.isNotEmpty && !label.contains('#$arbaNumber')) {
          label = '$label (#$arbaNumber)';
        }
      } else {
        label = (map['assignment_label'] ?? '').toString().trim();
        if (label.isEmpty) label = masterJudgeId;
      }

      if (!result.any((j) =>
          (j['id'] ?? '').toString().trim() == masterJudgeId)) {
        result.add({
          'id': masterJudgeId,
          'judge_id': masterJudgeId,
          'assignment_id': assignmentId,
          'name': label,
        });
      }
    }

    result.sort((a, b) {
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });

    _judges = result;
  }

    Future<void> _jumpToIssue(_ValidationIssue issue) async {
      final allEntries = await _fetchHydratedEntries(sectionId: null);

      final targetEntryId =
          (issue.entry['entry_id'] ?? issue.entry['id'] ?? '').toString().trim();

      Map<String, dynamic> targetEntry;
      try {
        targetEntry = allEntries.firstWhere((e) {
          return (e['entry_id'] ?? e['id'] ?? '').toString().trim() == targetEntryId;
        });
      } catch (_) {
        targetEntry = Map<String, dynamic>.from(issue.entry);
      }

      final breedEntries = allEntries.where((e) {
        final rowBreed = (e['breed'] ?? '').toString().trim();
        final rowBreedName = (e['breed_name'] ?? '').toString().trim();
        final rowBreedLabel = rowBreed.isNotEmpty ? rowBreed : rowBreedName;
        return rowBreedLabel.toLowerCase() == issue.breed.toLowerCase() &&
            _speciesDisplayNameForEntry(e).toLowerCase() ==
                issue.species.toLowerCase();
      }).toList();

      if (breedEntries.isEmpty) return;

      final byGroup = _showsByGroup(breedEntries);
      final byVariety = _showsByVariety(breedEntries);

      List<Map<String, dynamic>> working = [...breedEntries];

      if (byGroup && (issue.groupName ?? '').trim().isNotEmpty) {
        working = working.where((e) {
          return (e['group_name'] ?? '').toString().trim().toLowerCase() ==
              issue.groupName!.toLowerCase();
        }).toList();
      }

      if (byVariety && (issue.variety ?? '').trim().isNotEmpty) {
        working = working.where((e) {
          return (e['variety'] ?? '').toString().trim().toLowerCase() ==
              issue.variety!.toLowerCase();
        }).toList();
      }

      final targetIsFur = _isFurEntry(targetEntry);

      working = working.where((e) {
        return _classSexLabelFromEntry(e).toLowerCase() ==
                issue.classSexLabel.toLowerCase() &&
            _isFurEntry(e) == targetIsFur;
      }).toList();

      if (working.isEmpty) {
        working = breedEntries.where((e) => _isFurEntry(e) == targetIsFur).toList();
      }

      final targetSectionId =
          (targetEntry['section_id'] ?? '').toString().trim();
      if (targetSectionId.isNotEmpty) {
        _selectedSectionId = targetSectionId;
      }

      final sectionName = _sectionNameForEntry(targetEntry);

      try {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultsAnimalsScreen(
              showId: widget.showId,
              showName: widget.showName,
              sectionLabel: sectionName,
              breed: issue.breed,
              variety: issue.variety ?? '',
              classSexLabel: issue.classSexLabel,
              isFurOrWoolClass: working.any(_isFurEntry),
              entries: working,
              judges: _judges,
              onBulkJudgeApply: (entries, judgeId) async {

                final ids = entries
                    .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
                    .where((x) => x.isNotEmpty)
                    .toList();

                if (ids.isEmpty) return;

                if (!widget.isQrEntryMode) {
                  await ShowLockService.assertShowUnlocked(widget.showId);
                }

                await supabase
                    .from('entries')
                    .update({
                      'judged_by_show_judge_id':
                          (judgeId == null || judgeId.isEmpty) ? null : judgeId,
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    })
                    .inFilter('id', ids);
              },
              initialJudgeId: _singleJudgeIdFromEntries(working),
              breedClassSystems: _breedClassSystems,
              finalAwardMode: _finalAwardMode,
              showsByGroup: byGroup,
              showsByVariety: byVariety,
              isQrEntryMode: widget.isQrEntryMode,
              initialEntryIdToOpen:
                  (targetEntry['entry_id'] ?? targetEntry['id'] ?? '')
                      .toString(),
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _msg = 'Error: $e';
        });
      }

      await _loadEntries();
      if (mounted) setState(() {});
    }

  Future<void> _loadBreedClassSystems() async {
    final rows = await supabase
        .from('breeds')
        .select('name,class_system,uses_group_awards,uses_variety_awards')
        .eq('is_active', true);

    _breedClassSystems.clear();
    _breedUsesGroupAwards.clear();
    _breedUsesVarietyAwards.clear();

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final name = (row['name'] ?? '').toString().trim().toLowerCase();
      final classSystem =
          (row['class_system'] ?? 'four').toString().trim().toLowerCase();

      if (name.isNotEmpty) {
        _breedClassSystems[name] = classSystem;
        _breedUsesGroupAwards[name] = row['uses_group_awards'] == true;
        _breedUsesVarietyAwards[name] = row['uses_variety_awards'] == true;
      }
    }
  }

  Future<void> _loadShowSettings() async {
    final row = await supabase
        .from('shows')
        .select('final_award_mode')
        .eq('id', widget.showId)
        .maybeSingle();

    final mode = (row?['final_award_mode'] ?? kDefaultFinalAwardMode)
        .toString()
        .trim()
        .toLowerCase();

    _finalAwardMode = switch (mode) {
      'bis_ris' => 'bis_ris',
      'bis_1ris_2ris' => 'bis_1ris_2ris',
      _ => kDefaultFinalAwardMode,
    };
  }

    Future<List<Map<String, dynamic>>> _fetchHydratedEntries({
      String? sectionId,
    }) async {
      final params = <String, dynamic>{
        'p_show_id': widget.showId,
        'p_section_id': (sectionId == null || sectionId.isEmpty) ? null : sectionId,
        'p_show_letter': null,
      };

      final rows = await supabase.rpc(
        'report_results_entry_rows',
        params: params,
      );

      final entries = _dedupeResultsEntryRows(
        (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

      final entryIds = entries
          .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet()
          .toList();

      final showModeRow = await supabase
          .from('shows')
          .select('coop_numbering_mode')
          .eq('id', widget.showId)
          .maybeSingle();

      final coopNumberingMode =
          (showModeRow?['coop_numbering_mode'] ?? 'separate')
              .toString()
              .trim()
              .toLowerCase();

      final animalIdByEntryId = <String, String>{};
      for (var i = 0; i < entryIds.length; i += 100) {
        final chunk = entryIds.skip(i).take(100).toList();
        if (chunk.isEmpty) continue;

        final sourceRows = await supabase
            .from('entries')
            .select('id,animal_id')
            .inFilter('id', chunk);

        for (final raw in sourceRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final entryId = (row['id'] ?? '').toString().trim();
          final animalId = (row['animal_id'] ?? '').toString().trim();
          if (entryId.isNotEmpty && animalId.isNotEmpty) {
            animalIdByEntryId[entryId] = animalId;
          }
        }
      }

      final animalIds = animalIdByEntryId.values.toSet().toList();
      final coopNumberByAnimalAndScope = <String, String>{};

      for (var i = 0; i < animalIds.length; i += 100) {
        final chunk = animalIds.skip(i).take(100).toList();
        if (chunk.isEmpty) continue;

        final coopRows = await supabase
            .from('show_animal_coop_numbers')
            .select('animal_id,scope,coop_number')
            .eq('show_id', widget.showId)
            .inFilter('animal_id', chunk);

        for (final raw in coopRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final animalId = (row['animal_id'] ?? '').toString().trim();
          final scope = (row['scope'] ?? '').toString().trim().toLowerCase();
          final coopNumber = (row['coop_number'] ?? '').toString().trim();
          if (animalId.isEmpty || scope.isEmpty) continue;
          coopNumberByAnimalAndScope['$animalId|$scope'] = coopNumber;
        }
      }

      for (final entry in entries) {
        final entryId =
            (entry['entry_id'] ?? entry['id'] ?? '').toString().trim();
        final animalId = animalIdByEntryId[entryId] ?? '';
        entry['animal_id'] = animalId;

        final sectionId = (entry['section_id'] ?? '').toString().trim();
        final section = _sections.firstWhere(
          (row) => (row['id'] ?? '').toString().trim() == sectionId,
          orElse: () => <String, dynamic>{},
        );
        final sectionKind =
            (section['kind'] ?? '').toString().trim().toLowerCase();
        final scope = coopNumberingMode == 'combined' ? 'all' : sectionKind;

        entry['coop_number'] = animalId.isEmpty || scope.isEmpty
            ? ''
            : (coopNumberByAnimalAndScope['$animalId|$scope'] ?? '');
      }

      final awardsByEntryId = <String, List<String>>{};

      if (entryIds.isNotEmpty) {
        final allAwardRows = <Map<String, dynamic>>[];

        for (var i = 0; i < entryIds.length; i += 100) {
          final chunk = entryIds.skip(i).take(100).toList();

          final rows = await supabase
              .from('entry_awards')
              .select('entry_id,award_code')
              .eq('show_id', widget.showId)
              .inFilter('entry_id', chunk);

          allAwardRows.addAll(
            (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }

        for (final row in allAwardRows) {
          final entryId = (row['entry_id'] ?? '').toString().trim();
          final award = _canonicalAwardCode(
            (row['award_code'] ?? '').toString(),
          );
          if (entryId.isEmpty || award.isEmpty) continue;
          awardsByEntryId.putIfAbsent(entryId, () => <String>[]);
          awardsByEntryId[entryId]!.add(award);
        }
      }

      for (final e in entries) {
        final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
        e['_awards'] = awardsByEntryId[id] ?? <String>[];

        e['id'] ??= e['entry_id'];

        final rawBreed = (e['breed'] ?? '').toString().trim();
        final rawBreedName = (e['breed_name'] ?? '').toString().trim();
        e['breed'] = rawBreed.isNotEmpty ? rawBreed : rawBreedName;

        final rawVariety = (e['variety'] ?? '').toString().trim();
        final rawVarietyName = (e['variety_name'] ?? '').toString().trim();
        e['variety'] = rawVariety.isNotEmpty ? rawVariety : rawVarietyName;

        e['animal_name'] ??= '';

              final breedKey = (e['breed'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

              // Species is the source of truth for award flow. Some breed names overlap
              // between rabbits and cavies, such as American. Do not let cavy breed
              // settings force rabbit entries into group awards.
              if (breedKey.isNotEmpty) {
                if (_isCavyEntry(e)) {
                  e['uses_group_awards'] = _breedUsesGroupAwards.containsKey(breedKey)
                      ? _breedUsesGroupAwards[breedKey]
                      : e['uses_group_awards'] == true;

                  e['uses_variety_awards'] = _breedUsesVarietyAwards.containsKey(breedKey)
                      ? _breedUsesVarietyAwards[breedKey]
                      : e['uses_variety_awards'] == true;
                } else {
                  // For rabbits, trust the hydrated row/RPC value. Do not use the
                  // global breed-name map because names like American overlap with
                  // cavies, but do keep rabbit breed group settings such as
                  // Harlequin and Jersey Wooly.
                  e['uses_group_awards'] = _entryUsesGroupAwards(e);
                  e['uses_variety_awards'] = _entryUsesVarietyAwards(e);
                }
              }

        final normalizedGroup = (
          e['group_name'] ??
          e['group_display_name'] ??
          e['group_label'] ??
          e['group'] ??
          e['group_code']
        )?.toString().trim();

        e['group_name'] =
            (normalizedGroup == null || normalizedGroup.isEmpty)
                ? null
                : normalizedGroup;
      }

      return entries;
    }

    String? _singleJudgeIdFromEntries(List<Map<String, dynamic>> entries) {
      final ids = entries
          .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet();

      if (ids.length == 1) return ids.first;
      return null;
    }

    Future<void> _openInitialEntryFromRootIfNeeded() async {
      if (_didAutoOpenInitialEntryFromRoot) return;
      if (widget.initialEntryId == null || widget.initialEntryId!.trim().isEmpty) {
        return;
      }

      final targetId = widget.initialEntryId!.trim();

      List<Map<String, dynamic>> allEntries = _entries;
      Map<String, dynamic> target = allEntries.cast<Map<String, dynamic>>().firstWhere(
        (e) => ((e['entry_id'] ?? e['id'] ?? '').toString().trim() == targetId),
        orElse: () => <String, dynamic>{},
      );

      if (target.isEmpty) {
        allEntries = await _fetchHydratedEntries(sectionId: null);
        target = allEntries.firstWhere(
          (e) => ((e['entry_id'] ?? e['id'] ?? '').toString().trim() == targetId),
          orElse: () => <String, dynamic>{},
        );
      }

      if (target.isEmpty || !mounted) return;

      _didAutoOpenInitialEntryFromRoot = true;

      final targetBreed = (target['breed'] ?? '').toString().trim();
      final targetBreedName = (target['breed_name'] ?? '').toString().trim();
      final breed = targetBreed.isNotEmpty ? targetBreed : targetBreedName;
      final breedEntries = allEntries.where((e) {
        final rowBreed = (e['breed'] ?? '').toString().trim();
        final rowBreedName = (e['breed_name'] ?? '').toString().trim();
        final rowBreedLabel = rowBreed.isNotEmpty ? rowBreed : rowBreedName;
        return rowBreedLabel.toLowerCase() == breed.toLowerCase();
      }).toList();

      if (breedEntries.isEmpty) return;

      final byGroup = _showsByGroup(breedEntries);
      final byVariety = _showsByVariety(breedEntries);

      List<Map<String, dynamic>> working = [...breedEntries];

      final issueGroup = (target['group_name'] ?? '').toString().trim();
      final issueVariety = (target['variety'] ?? '').toString().trim();
      final classSexLabel = _classSexLabelFromEntry(target);

      if (byGroup && issueGroup.isNotEmpty) {
        working = working.where((e) {
          return (e['group_name'] ?? '').toString().trim().toLowerCase() ==
              issueGroup.toLowerCase();
        }).toList();
      }

      if (byVariety && issueVariety.isNotEmpty) {
        working = working.where((e) {
          return (e['variety'] ?? '').toString().trim().toLowerCase() ==
              issueVariety.toLowerCase();
        }).toList();
      }

      final targetIsFur = _isFurEntry(target);

      working = working.where((e) {
        return _classSexLabelFromEntry(e).toLowerCase() ==
                classSexLabel.toLowerCase() &&
            _isFurEntry(e) == targetIsFur;
      }).toList();

      if (working.isEmpty) {
        working = breedEntries.where((e) => _isFurEntry(e) == targetIsFur).toList();
      }

      final targetSectionId = (target['section_id'] ?? '').toString().trim();
      if (targetSectionId.isNotEmpty) {
        _selectedSectionId = targetSectionId;
      }

      final sectionName = _sectionNameForEntry(target);

      try {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultsAnimalsScreen(
              showId: widget.showId,
              showName: widget.showName,
              sectionLabel: sectionName,
              breed: breed,
              variety: issueVariety,
              classSexLabel: classSexLabel,
              isFurOrWoolClass: working.any(_isFurEntry),
              entries: working,
              judges: _judges,
              onBulkJudgeApply: (entries, judgeId) async {
                final ids = entries
                    .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
                    .where((x) => x.isNotEmpty)
                    .toList();
                if (ids.isEmpty) return;

                if (!widget.isQrEntryMode) {
                  await ShowLockService.assertShowUnlocked(widget.showId);
                }

                await supabase
                    .from('entries')
                    .update({
                      'judged_by_show_judge_id':
                          (judgeId == null || judgeId.isEmpty) ? null : judgeId,
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    })
                    .inFilter('id', ids);
              },
              initialJudgeId: _singleJudgeIdFromEntries(working),
              breedClassSystems: _breedClassSystems,
              finalAwardMode: _finalAwardMode,
              showsByGroup: byGroup,
              showsByVariety: byVariety,
              isQrEntryMode: widget.isQrEntryMode,
              initialEntryIdToOpen: targetId,
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _msg = 'Error: $e';
        });
      }

      await _loadEntries();
      if (mounted) setState(() {});
    }

    Future<void> _loadEntries() async {
      _entries = await _fetchHydratedEntries(
        sectionId: (_selectedSectionId == null || _selectedSectionId!.isEmpty)
            ? null
            : _selectedSectionId,
      );
    }


  String _classSexLabelFromEntry(Map<String, dynamic> e) {
    final rawClass = (e['class_name'] ?? '').toString().trim();
    final sex = (e['sex'] ?? '').toString().trim();

    String ageClassOnly(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return '';
      final lower = s.toLowerCase();
      if (lower.contains('pre-junior') ||
          lower.contains('pre junior') ||
          lower.contains('prejunior') ||
          lower.startsWith('pre jr') ||
          lower.startsWith('pre-jr')) {
        return 'Pre-Junior';
      }

      if (lower.contains('senior') || lower.startsWith('sr')) return 'Senior';
      if (lower.contains('intermediate') || lower.startsWith('int')) return 'Intermediate';
      if (lower.contains('junior') || lower.startsWith('jr')) return 'Junior';
      if (lower.contains('open')) return 'Open';
      return s;
    }

    final cls = ageClassOnly(rawClass);

    return [
      if (cls.isNotEmpty) cls,
      if (sex.isNotEmpty) sex,
    ].join(' ');
  }

  String _sectionNameForEntry(Map<String, dynamic> e) {
    final sid = (e['section_id'] ?? '').toString();
    final match = _sections.where((s) => s['id']?.toString() == sid);
    if (match.isNotEmpty) return _sectionLabel(match.first);

    final label = (e['section_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;

    return 'Section';
  }

  String _issueSubtitle(_ValidationIssue issue) {
    final parts = <String>[
      issue.breed,
      if ((issue.groupName ?? '').trim().isNotEmpty) issue.groupName!,
      if ((issue.variety ?? '').trim().isNotEmpty) issue.variety!,
      issue.classSexLabel,
      _entryLabel(issue.entry),
    ];

    if (issue.conflictsWith != null) {
      parts.add('Conflicts with: ${_entryLabel(issue.conflictsWith!)}');
    }

    return parts.where((x) => x.trim().isNotEmpty).join(' • ');
  }

  String _sectionLabel(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    final letter = (s['letter'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    if (letter.isNotEmpty) return 'Show $letter';
    return 'Section';
  }

  Future<void> _onChangeSection(String? value) async {
    setState(() {
      _selectedSectionId = value ?? '';
      _loading = true;
      _msg = null;
    });

    await _loadEntries();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Map<String, List<Map<String, dynamic>>> _groupByBreed(List<Map<String, dynamic>> items) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in items) {
      final breed = _breedDisplayNameForEntry(e);
      final species = _speciesDisplayNameForEntry(e);
      final key = '${species.toLowerCase()}|${breed.toLowerCase()}';
      out.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      out[key]!.add(e);
    }
    return out;
  }

  String _breedDisplayNameForEntry(Map<String, dynamic> entry) {
    final rawBreed = (entry['breed'] ?? '').toString().trim();
    if (rawBreed.isNotEmpty) return rawBreed;

    final rawBreedName = (entry['breed_name'] ?? '').toString().trim();
    return rawBreedName.isEmpty ? '(Unknown Breed)' : rawBreedName;
  }

  String _breedDisplayNameForEntries(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return '(Unknown Breed)';
    return _breedDisplayNameForEntry(entries.first);
  }

  String _speciesDisplayNameForEntry(Map<String, dynamic> entry) {
    final species = (entry['species'] ?? '').toString().trim().toLowerCase();
    if (species == 'cavy') return 'Cavy';
    if (species == 'rabbit') return 'Rabbit';
    return _isCavyEntry(entry) ? 'Cavy' : 'Rabbit';
  }

  String _speciesDisplayNameForEntries(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return 'Unknown Species';
    return _speciesDisplayNameForEntry(entries.first);
  }

  bool _showsByGroup(List<Map<String, dynamic>> entries) {
    final normalEntries = entries.where((e) => !_isFurEntry(e)).toList();
    if (normalEntries.isEmpty) return false;

    final anyRabbitEntry = normalEntries.any((e) => !_isCavyEntry(e));

    // For rabbits, trust the hydrated row/RPC value. Do not use the global
    // breed-name map because names like American overlap with cavies, but do
    // allow true rabbit group-award breeds like Harlequin and Jersey Wooly.
    if (anyRabbitEntry) {
      return normalEntries.any((e) => !_isCavyEntry(e) && _entryUsesGroupAwards(e));
    }

    final firstBreed = (normalEntries.first['breed'] ?? '').toString().trim();
    final firstBreedName =
        (normalEntries.first['breed_name'] ?? '').toString().trim();

    final breedName =
        (firstBreed.isNotEmpty ? firstBreed : firstBreedName).toLowerCase();

    final breedSettingUsesGroups = breedName.isNotEmpty &&
        (_breedUsesGroupAwards[breedName] == true);

    final rowUsesGroups = normalEntries.any(_entryUsesGroupAwards);

    return breedSettingUsesGroups || rowUsesGroups;
  }

bool _showsByVariety(List<Map<String, dynamic>> entries) {
  final normalEntries = entries.where((e) => !_isFurEntry(e)).toList();
  if (normalEntries.isEmpty) return false;

  final anyRabbitEntry = normalEntries.any((e) => !_isCavyEntry(e));

  // For rabbits, trust the hydrated row/RPC value. Do not use the global
  // breed-name map because names like American overlap with cavies.
  if (anyRabbitEntry) {
    return normalEntries.any((e) => !_isCavyEntry(e) && _entryUsesVarietyAwards(e));
  }

  final firstBreed = (normalEntries.first['breed'] ?? '').toString().trim();
  final firstBreedName = (normalEntries.first['breed_name'] ?? '').toString().trim();
  final breedName = (firstBreed.isNotEmpty ? firstBreed : firstBreedName)
      .toLowerCase();

  if (breedName.isNotEmpty && _breedUsesVarietyAwards.containsKey(breedName)) {
    return _breedUsesVarietyAwards[breedName] == true;
  }

  return normalEntries.any(_entryUsesVarietyAwards);
}

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';

    for (final j in _judges) {
      final savedJudgeId = (j['id'] ?? '').toString().trim();
      final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
      final assignmentId = (j['assignment_id'] ?? '').toString().trim();

      if (savedJudgeId == judgeId ||
          masterJudgeId == judgeId ||
          assignmentId == judgeId) {
        return (j['name'] ?? '').toString().trim();
      }
    }

    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return name.isEmpty ? 'Judge: Not set' : 'Judge: $name';
  }

  // --- Completion/Status Highlighting Helpers ---
  _ResultScopeCompletion _completionFor(List<Map<String, dynamic>> entries) {
    return _resultCompletionForEntries(
      entries,
      requireVarietyAwards: _showsByVariety(entries),
      requireGroupAwards: _showsByGroup(entries),
      requireBreedAwards: true,
    );
  }

  bool _hasResult(Map<String, dynamic> entry) {
    return _entryHasBasicOutcome(entry);
  }

  int _completedCount(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).completedBasics;
  }

  bool _isComplete(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.complete;
  }

  bool _isInProgress(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.inProgress;
  }

  String _statusLabel(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusLabel(_completionFor(entries).status);
  }

  IconData _statusIcon(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusIcon(_completionFor(entries).status);
  }

  Color _statusColor(BuildContext context, List<Map<String, dynamic>> entries) {
    return _resultScopeStatusColor(context, _completionFor(entries).status);
  }

  List<_ValidationIssue> _buildValidationIssues() {
    final issues = <_ValidationIssue>[];

    _ValidationIssue makeIssue({
      required String code,
      required String title,
      required String message,
      required Map<String, dynamic> entry,
      Map<String, dynamic>? conflictsWith,
    }) {
      return _ValidationIssue(
        code: code,
        title: title,
        message: message,
        entry: entry,
        conflictsWith: conflictsWith,
        breed: (() {
          final rawBreed = (entry['breed'] ?? '').toString().trim();
          if (rawBreed.isNotEmpty) return rawBreed;
          return (entry['breed_name'] ?? '').toString().trim();
        })(),
        species: _speciesDisplayNameForEntry(entry),
        groupName: (entry['group_name'] ?? '').toString().trim().isEmpty
            ? null
            : (entry['group_name'] ?? '').toString().trim(),
        variety: (() {
          final rawVariety = (entry['variety'] ?? '').toString().trim();
          if (rawVariety.isNotEmpty) return rawVariety;
          final rawVarietyName = (entry['variety_name'] ?? '').toString().trim();
          return rawVarietyName.isEmpty ? null : rawVarietyName;
        })(),
        classSexLabel: _classSexLabelFromEntry(entry),
      );
    }

  bool isEligibleForAwards(Map<String, dynamic> e) {
    final scratched = (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
    if (scratched) return false;

    final className = (e['class_name'] ?? '').toString().trim();
    if (_isPreJuniorClassName(className)) return false;

    final status = (e['result_status'] ?? '').toString().trim();
    final isShown = e['is_shown'] != false;
    final isDisqualified = e['is_disqualified'] == true;

    if (!isShown) return false;
    if (isDisqualified) return false;

    if (status == 'No Show' ||
        _isDisqualifiedStatus(status) ||
        status == 'Unworthy of Award') {
      return false;
    }

    return true;
  }

    bool showsByGroup(Map<String, dynamic> e) {
      if (!_isCavyEntry(e)) {
        return _entryUsesGroupAwards(e);
      }

      final thisBreedRaw = (e['breed'] ?? '').toString().trim();
      final thisBreedName = (e['breed_name'] ?? '').toString().trim();
      final thisBreed =
          (thisBreedRaw.isNotEmpty ? thisBreedRaw : thisBreedName).toLowerCase();

      if (thisBreed.isEmpty) return false;
      if (_entryUsesGroupAwards(e)) return true;
      if (_breedUsesGroupAwards[thisBreed] == true) return true;

      return false;
    }

    bool showsByVariety(Map<String, dynamic> e) {
      if (!_isCavyEntry(e)) {
        return _entryUsesVarietyAwards(e);
      }

      final thisBreedRaw = (e['breed'] ?? '').toString().trim();
      final thisBreedName = (e['breed_name'] ?? '').toString().trim();
      final thisBreed =
          (thisBreedRaw.isNotEmpty ? thisBreedRaw : thisBreedName).toLowerCase();

      if (thisBreed.isNotEmpty &&
          _breedUsesVarietyAwards.containsKey(thisBreed)) {
        return _breedUsesVarietyAwards[thisBreed] == true;
      }

      return _entryUsesVarietyAwards(e);
    }

    String sex(Map<String, dynamic> e) => (e['sex'] ?? '').toString().trim().toLowerCase();
    String breed(Map<String, dynamic> e) {
      final rawBreed = (e['breed'] ?? '').toString().trim();
      if (rawBreed.isNotEmpty) return rawBreed;
      return (e['breed_name'] ?? '').toString().trim();
    }
    String variety(Map<String, dynamic> e) {
      final rawVariety = (e['variety'] ?? '').toString().trim();
      if (rawVariety.isNotEmpty) return rawVariety;
      return (e['variety_name'] ?? '').toString().trim();
    }
    String sectionId(Map<String, dynamic> e) => (e['section_id'] ?? '').toString().trim();
    String species(Map<String, dynamic> e) =>
        _speciesDisplayNameForEntry(e).toLowerCase();
    
    String groupName(Map<String, dynamic> e) {
      final explicitGroup = (
        e['group_name'] ??
        e['group_display_name'] ??
        e['group_label'] ??
        e['group'] ??
        e['group_code'] ??
        ''
      ).toString().trim();

      if (explicitGroup.isNotEmpty) return explicitGroup;

      final breedKey = breed(e).toLowerCase();
      final usesGroups = _isCavyEntry(e)
          ? (_entryUsesGroupAwards(e) || _breedUsesGroupAwards[breedKey] == true)
          : _entryUsesGroupAwards(e);
      final usesVarieties = _isCavyEntry(e)
          ? (_entryUsesVarietyAwards(e) || _breedUsesVarietyAwards[breedKey] == true)
          : _entryUsesVarietyAwards(e);

      if (usesGroups && !usesVarieties) {
        return variety(e);
      }

      return '';
    }

    List<String> awards(Map<String, dynamic> e) =>
        ((e['_awards'] as List?) ?? const []).map((x) => x.toString()).toList();

  final awardBuckets = <String, List<Map<String, dynamic>>>{};

  for (final e in _entries) {
    if (_isFurEntry(e)) continue;

    final entryAwards = awards(e);

    final placement = (e['placement'] ?? '').toString().trim();
    if (entryAwards.isNotEmpty && placement != '1') {
      issues.add(
        makeIssue(
          code: 'award_requires_first',
          title: 'Awards require first place',
          message: '${_entryLabel(e)} has awards assigned but is not placed 1st.',
          entry: e,
        ),
      );
    }

    if (!isEligibleForAwards(e) && entryAwards.isNotEmpty) {
      final className = (e['class_name'] ?? '').toString().trim();
      final isPreJunior = _isPreJuniorClassName(className);

      issues.add(
        makeIssue(
          code: 'ineligible_award',
          title: isPreJunior
              ? 'Pre-Junior cannot receive specials'
              : 'Ineligible animal has awards',
          message: isPreJunior
              ? '${_entryLabel(e)} is Pre-Junior and cannot receive specials like BOV, BOSV, BOG, BOSG, BOB, or BOSB.'
              : '${_entryLabel(e)} has awards assigned but is scratched, disqualified, or not shown.',
          entry: e,
        ),
      );
    }
    

    for (final rawAward in entryAwards) {
      final award = _canonicalAwardCode(rawAward);
      switch (award) {
        case 'BOV':
        case 'BOSV':
          final key = '${sectionId(e)}|$award|${species(e)}|${breed(e).toLowerCase()}|${variety(e).toLowerCase()}';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
        case 'BOG':
        case 'BOSG':
          final groupScope = groupName(e).toLowerCase();
          if (groupScope.isEmpty) {
            issues.add(
              makeIssue(
                code: 'missing_group_for_group_award',
                title: 'Group award missing group',
                message:
                    '${_entryLabel(e)} has $award assigned but no group could be determined.',
                entry: e,
              ),
            );
            break;
          }

          final key = '${sectionId(e)}|$award|${species(e)}|${breed(e).toLowerCase()}|$groupScope';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
        case 'BOB':
        case 'BOSB':
          final key = '${sectionId(e)}|$award|${species(e)}|${breed(e).toLowerCase()}';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
        case 'Best Junior':
        case 'Best Senior':
        case 'Best Intermediate':
          final useVarietyScope = showsByVariety(e);
          final key = useVarietyScope
              ? '${sectionId(e)}|$award|${species(e)}|${breed(e).toLowerCase()}|${variety(e).toLowerCase()}'
              : '${sectionId(e)}|$award|${species(e)}|${breed(e).toLowerCase()}';

          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
        case 'Best 4-Class':
        case 'Best 6-Class':
        case 'BIS':
        case 'Reserve In Show':
        case '1RIS':
        case '2RIS':
          final key = '${sectionId(e)}|$award';
          awardBuckets.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          awardBuckets[key]!.add(e);
          break;
      }
    }
  }

  for (final bucket in awardBuckets.entries) {
    if (bucket.value.length > 1) {
      final first = bucket.value.first;
      final second = bucket.value.length > 1 ? bucket.value[1] : null;
      final awardCode = bucket.key.split('|')[1];

      issues.add(
        makeIssue(
          code: 'duplicate_award',
          title: 'Duplicate award winner',
          message:
              '$awardCode is assigned to more than one animal: '
              '${_entryLabel(first)}'
              '${second != null ? ' and ${_entryLabel(second)}' : ''}.',
          entry: first,
          conflictsWith: second,
        ),
      );
    }
  }

  void checkOpposite({
    required String winCode,
    required String oppCode,
    required String scopeLabel,
    required String Function(Map<String, dynamic>) scopeKey,
  }) {
    final winByScope = <String, Map<String, dynamic>>{};
    final oppByScope = <String, Map<String, dynamic>>{};

    for (final e in _entries) {
      if (_isFurEntry(e)) continue;

      final a = awards(e);
      final scope = scopeKey(e).trim();
      if (scope.isEmpty) continue;
      if (a.contains(winCode)) winByScope[scope] = e;
      if (a.contains(oppCode)) oppByScope[scope] = e;
    }

    for (final scope in {...winByScope.keys, ...oppByScope.keys}) {
      final w = winByScope[scope];
      final o = oppByScope[scope];
      if (w == null || o == null) continue;

      if (sex(w).isNotEmpty && sex(w) == sex(o)) {
        issues.add(
          makeIssue(
            code: 'opposite_sex',
            title: '$winCode / $oppCode sex conflict',
            message:
                '${_entryLabel(w)} and ${_entryLabel(o)} are both marked for $winCode / $oppCode in the same $scopeLabel, but are not opposite sex.',
            entry: w,
            conflictsWith: o,
          ),
        );
      }
    }
  }

  checkOpposite(
    winCode: 'BOV',
    oppCode: 'BOSV',
    scopeLabel: 'variety',
    scopeKey: (e) {
      final entryBreed = breed(e).toLowerCase();
      final entryVariety = variety(e).toLowerCase();
      if (entryBreed.isEmpty || entryVariety.isEmpty) return '';

      // Cavies always validate BOV/BOSV within breed + variety. Some cavy rows
      // may not have uses_variety_awards hydrated correctly, but BOV/BOSV should
      // never be compared across different cavy breeds.
      if (_isCavyEntry(e)) {
        return '${sectionId(e)}|$entryBreed|$entryVariety';
      }

      if (!showsByVariety(e)) return '';
      return '${sectionId(e)}|$entryBreed|$entryVariety';
    },
  );

  checkOpposite(
    winCode: 'BOG',
    oppCode: 'BOSG',
    scopeLabel: 'group',
    scopeKey: (e) {
      if (!showsByGroup(e)) return '';
      return '${sectionId(e)}|${breed(e).toLowerCase()}|${groupName(e).toLowerCase()}';
    },
  );

  checkOpposite(
    winCode: 'BOB',
    oppCode: 'BOSB',
    scopeLabel: 'breed',
    scopeKey: (e) => '${sectionId(e)}|${breed(e).toLowerCase()}',
  );

  for (final e in _entries) {
    if (_isFurEntry(e)) continue;

    final a = awards(e);
    final breedLower = breed(e).toLowerCase();
    final byGroup = showsByGroup(e);
    final byVariety = showsByVariety(e);
    final supportsBestAgeAwards = _supportsBestAgeAwards(
      breedName: breed(e),
      isCavy: _isCavyEntry(e),
    );
    if (supportsBestAgeAwards) {
      final classSystem = _breedClassSystems[breedLower] ?? 'four';
      final className = (e['class_name'] ?? '').toString().trim();

      for (final award in kBestAgeAwardCodes) {
        if (!a.contains(award)) continue;

        if (!_bestAgeAwardMatchesClass(
          award: award,
          className: className,
          classSystem: classSystem,
        )) {
          issues.add(
            makeIssue(
              code: 'best_age_wrong_class',
              title: '$award assigned to wrong class',
              message:
                  '${_entryLabel(e)} has $award but is not in the matching age class.',
              entry: e,
            ),
          );
        }
      }
    }

    if (a.contains('BOB') || a.contains('BOSB')) {
      final isCavy = _isCavyEntry(e);

      // Cavies do not use the rabbit BOG/BOSG step. Even when a cavy row has a
      // group/display bucket such as Marked, BOB/BOSB should validate from
      // BOV/BOSV. Rabbits that truly use group awards still validate from
      // BOG/BOSG.
      final eligible = isCavy
          ? (a.contains('BOV') || a.contains('BOSV'))
          : byGroup
              ? (a.contains('BOG') || a.contains('BOSG'))
              : byVariety
                  ? (a.contains('BOV') || a.contains('BOSV'))
                  : true;

      if (!eligible) {
        final requiredSource = isCavy
            ? 'BOV/BOSV'
            : byGroup
                ? 'BOG/BOSG'
                : byVariety
                    ? 'BOV/BOSV'
                    : 'as eligible for direct breed awards';

        issues.add(
          makeIssue(
            code: 'bob_source',
            title: 'Invalid breed award source',
            message:
                '${_entryLabel(e)} has BOB/BOSB but is not marked $requiredSource.',
            entry: e,
          ),
        );
      }
    }

    // final classSystem is now declared above if needed.
    final classSystem = _breedClassSystems[breedLower] ?? 'four';

    if (a.contains('Best 4-Class')) {
      if (!a.contains('BOB')) {
        issues.add(
          makeIssue(
            code: 'best4_requires_bob',
            title: 'Best 4-Class requires BOB',
            message: '${_entryLabel(e)} has Best 4-Class but is not marked BOB.',
            entry: e,
          ),
        );
      }
      if (classSystem != 'four') {
        issues.add(
          makeIssue(
            code: 'best4_wrong_breed',
            title: 'Best 4-Class on wrong breed type',
            message: '${_entryLabel(e)} has Best 4-Class but breed is not 4-class.',
            entry: e,
          ),
        );
      }
    }

    if (a.contains('Best 6-Class')) {
      if (!a.contains('BOB')) {
        issues.add(
          makeIssue(
            code: 'best6_requires_bob',
            title: 'Best 6-Class requires BOB',
            message: '${_entryLabel(e)} has Best 6-Class but is not marked BOB.',
            entry: e,
          ),
        );
      }
      if (classSystem != 'six') {
        issues.add(
          makeIssue(
            code: 'best6_wrong_breed',
            title: 'Best 6-Class on wrong breed type',
            message: '${_entryLabel(e)} has Best 6-Class but breed is not 6-class.',
            entry: e,
          ),
        );
      }
    }

    if (_finalAwardMode == 'four_six_bis' && _awardListContains(a, 'Best In Show')) {
      if (!(_awardListContains(a, 'Best 4-Class') || _awardListContains(a, 'Best 6-Class'))) {
        issues.add(
          makeIssue(
            code: 'bis_requires_best_class',
            title: 'Best In Show requires Best 4-Class or Best 6-Class',
            message: '${_entryLabel(e)} has Best In Show but is not Best 4-Class or Best 6-Class.',
            entry: e,
          ),
        );
      }
    }

    if (_finalAwardMode == 'bis_ris' &&
        _awardListContains(a, 'Reserve In Show') &&
        _awardListContains(a, 'Best In Show')) {
      issues.add(
        makeIssue(
          code: 'bis_ris_same_entry',
          title: 'Rabbit cannot be BIS and RIS',
          message: '${_entryLabel(e)} cannot be both Best In Show and Reserve In Show.',
          entry: e,
        ),
      );
    }

    if (_finalAwardMode == 'bis_1ris_2ris') {
      final hasBis = _awardListContains(a, 'Best In Show');
      final hasFirstRis = _awardListContains(a, '1RIS');
      final hasSecondRis = _awardListContains(a, '2RIS');
      final finalAwardCount = [hasBis, hasFirstRis, hasSecondRis]
          .where((selected) => selected)
          .length;

      if (finalAwardCount > 1) {
        issues.add(
          makeIssue(
            code: 'bis_1ris_2ris_same_entry',
            title: 'Animal has multiple final awards',
            message:
                '${_entryLabel(e)} cannot receive more than one of Best In Show, 1st Reserve in Show, or 2nd Reserve in Show.',
            entry: e,
          ),
        );
      }
    }
  }

  return issues;
  }

  String _entryLabel(Map<String, dynamic> e) {
    final animalName = (e['animal_name'] ?? '').toString().trim();
    final tattoo = (e['tattoo'] ?? '').toString().trim();
    final rawBreed = (e['breed'] ?? '').toString().trim();
    final rawBreedName = (e['breed_name'] ?? '').toString().trim();
    final breed = rawBreed.isNotEmpty ? rawBreed : rawBreedName;

    final rawVariety = (e['variety'] ?? '').toString().trim();
    final rawVarietyName = (e['variety_name'] ?? '').toString().trim();
    final variety = rawVariety.isNotEmpty ? rawVariety : rawVarietyName;

    final groupName = (e['group_name'] ?? '').toString().trim();

    final animalLabel = animalName.isNotEmpty && tattoo.isNotEmpty
        ? '$animalName • $tattoo'
        : animalName.isNotEmpty
            ? animalName
            : tattoo.isNotEmpty
                ? tattoo
                : '(No ear #)';

    final coopNumber = (e['coop_number'] ?? '').toString().trim();

    return [
      if (coopNumber.isNotEmpty) 'Coop $coopNumber',
      animalLabel,
      breed,
      if (groupName.isNotEmpty) groupName,
      if (variety.isNotEmpty) variety,
    ].join(' • ');
  }

    void _openValidationSheet() {
      final issues = _buildValidationIssues();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Results Validation',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        issues.isEmpty
                            ? 'No validation issues found.'
                            : '${issues.length} validation issue${issues.length == 1 ? '' : 's'} found.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: issues.isEmpty
                          ? const Align(
                              alignment: Alignment.topLeft,
                              child: Text('Everything looks good so far.'),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: issues.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final issue = issues[i];
                                return ListTile(
                                  leading: const Icon(Icons.warning_amber_rounded),
                                  title: Text(issue.title),
                                  subtitle: Text(
                                    '${issue.message}\n${_issueSubtitle(issue)}',
                                  ),
                                  isThreeLine: true,
                                  trailing: TextButton(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      await _jumpToIssue(issue);
                                    },
                                    child: const Text('Fix'),
                                  ),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    await _jumpToIssue(issue);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByBreed(_entries);
    final breeds = grouped.keys.toList()
      ..sort((a, b) {
        int sortFor(String key) {
          final rows = grouped[key] ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return 9999;
          final raw = rows.first['breed_sort_order'];
          if (raw is int) return raw;
          return int.tryParse(raw?.toString() ?? '') ?? 9999;
        }

        final bySort = sortFor(a).compareTo(sortFor(b));
        if (bySort != 0) return bySort;

        final aRows = grouped[a] ?? const <Map<String, dynamic>>[];
        final bRows = grouped[b] ?? const <Map<String, dynamic>>[];
        final byBreed = _breedDisplayNameForEntries(
          aRows,
        ).toLowerCase().compareTo(
          _breedDisplayNameForEntries(bRows).toLowerCase(),
        );
        if (byBreed != 0) return byBreed;

        return _speciesDisplayNameForEntries(aRows).toLowerCase().compareTo(
          _speciesDisplayNameForEntries(bRows).toLowerCase(),
        );
      });

    final issues = _buildValidationIssues();

    return RingMasterPageShell(
      title: 'RingMaster Show',
      subtitle: 'Results Entry — ${widget.showName}',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Validation',
          onPressed: _loading ? null : _openValidationSheet,
          icon: const Icon(Icons.rule_folder_outlined),
        ),
        IconButton(
          tooltip: 'Reload',
          onPressed: _loading ? null : _loadAll,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF11285A),
                          Color(0xFF0B1C43),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Results Workflow',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.showName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _finalAwardMode == 'bis_ris'
                                ? 'Final awards: Best in Show / Reserve in Show'
                                : _finalAwardMode == 'bis_1ris_2ris'
                                    ? 'Final awards: Best in Show / 1st Reserve in Show / 2nd Reserve in Show'
                                    : 'Final awards: Best 4-Class / Best 6-Class / Best in Show',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (AppSession.isSupportMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Text(
                        'Support Mode — You are entering results as an admin while viewing another user.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withValues(alpha: .20)),
                      ),
                      child: Text(
                        _msg!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _selectedSectionId ?? '',
                            decoration: const InputDecoration(
                              labelText: 'Show Letter / Section',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('All Sections'),
                              ),
                              ..._sections.map(
                                (s) => DropdownMenuItem<String>(
                                  value: s['id']?.toString(),
                                  child: Text(_sectionLabel(s)),
                                ),
                              ),
                            ],
                            onChanged: _onChangeSection,
                          ),
                          const SizedBox(height: 14),
                          Container(
                            decoration: BoxDecoration(
                              color: issues.isEmpty
                                  ? Colors.green.withValues(alpha: .08)
                                  : Colors.orange.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: issues.isEmpty
                                    ? Colors.green.withValues(alpha: .20)
                                    : Colors.orange.withValues(alpha: .22),
                              ),
                            ),
                            child: ListTile(
                              leading: Icon(
                                issues.isEmpty
                                    ? Icons.check_circle_outline
                                    : Icons.warning_amber_rounded,
                                color:
                                    issues.isEmpty ? Colors.green : Colors.orange,
                              ),
                              title: Text(
                                issues.isEmpty
                                    ? 'Validation looks good'
                                    : 'Validation issues found',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                issues.isEmpty
                                    ? 'No current award/result conflicts found.'
                                    : '${issues.length} issue${issues.length == 1 ? '' : 's'} to review.',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _openValidationSheet,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: breeds.isEmpty
                      ? const Center(
                          child: Text('No entries found for this section.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: breeds.length,
                          itemBuilder: (context, i) {
                            final breedKey = breeds[i];
                            final breedEntries = grouped[breedKey]!;
                            final breed = _breedDisplayNameForEntries(breedEntries);
                            final species = _speciesDisplayNameForEntries(breedEntries);
                            final count = breedEntries.length;
                            final completed = _completedCount(breedEntries);
                            final statusColor = _statusColor(context, breedEntries);
                            final breedSpecials = _specialsSummaryForEntries(
                              breedEntries,
                              const [
                                'BOV',
                                'BOSV',
                                'BOG',
                                'BOSG',
                                'BOB',
                                'BOSB',
                                'Best Junior',
                                'Best Intermediate',
                                'Best Senior',
                                'Best 4-Class',
                                'Best 6-Class',
                                'Best In Show',
                                'Reserve In Show',
                                'BIS',
                                'RIS',
                                '1RIS',
                                '2RIS',
                                'HM',
                              ],
                            );
                            final byGroup = _showsByGroup(breedEntries);
                            final byVariety = _showsByVariety(breedEntries);

                            final sectionName =
                                (_selectedSectionId == null ||
                                        _selectedSectionId!.isEmpty)
                                    ? 'All Sections'
                                    : (() {
                                        final section = _sections.firstWhere(
                                          (s) =>
                                              s['id']?.toString() ==
                                              _selectedSectionId,
                                          orElse: () => <String, dynamic>{},
                                        );
                                        return section.isEmpty
                                            ? 'Section'
                                            : _sectionLabel(section);
                                      })();

                            String flowLabel;
                            if (byGroup && byVariety) {
                              flowLabel = 'Group → Variety';
                            } else if (byGroup) {
                              flowLabel = 'Group';
                            } else if (byVariety) {
                              flowLabel = 'Variety';
                            } else {
                              flowLabel = 'Class';
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 0,
                              color: statusColor.withValues(alpha: 0.06),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  18,
                                  14,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: statusColor.withValues(alpha: 0.12),
                                  child: Icon(
                                    _statusIcon(breedEntries),
                                    color: statusColor,
                                  ),
                                ),
                                title: Text(
                                  breed,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '$completed/$count entered • ${_statusLabel(breedEntries)}\n$species • $flowLabel • ${_judgeSummary(breedEntries)}${breedSpecials.isEmpty ? '' : '\n$breedSpecials'}',
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  if (byGroup) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _ResultsGroupScreen(
                                          showId: widget.showId,
                                          showName: widget.showName,
                                          sectionLabel: sectionName,
                                          breed: breed,
                                          entries: breedEntries,
                                          judges: _judges,
                                          breedClassSystems: _breedClassSystems,
                                          finalAwardMode: _finalAwardMode,
                                          showsByVariety: byVariety,
                                          isQrEntryMode: widget.isQrEntryMode,
                                        ),
                                      ),
                                    );
                                  } else if (byVariety) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _ResultsVarietyScreen(
                                          showId: widget.showId,
                                          showName: widget.showName,
                                          sectionLabel: sectionName,
                                          breed: breed,
                                          entries: breedEntries,
                                          judges: _judges,
                                          breedClassSystems: _breedClassSystems,
                                          finalAwardMode: _finalAwardMode,
                                          parentGroupLabel: null,
                                          isQrEntryMode: widget.isQrEntryMode,
                                        ),
                                      ),
                                    );
                                  } else {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _ResultsClassSexScreen(
                                          showId: widget.showId,
                                          showName: widget.showName,
                                          sectionLabel: sectionName,
                                          breed: breed,
                                          variety: '',
                                          contextLabel: breed,
                                          entries: breedEntries,
                                          judges: _judges,
                                          breedClassSystems: _breedClassSystems,
                                          finalAwardMode: _finalAwardMode,
                                          showsByGroup: false,
                                          showsByVariety: false,
                                          isQrEntryMode: widget.isQrEntryMode,
                                        ),
                                      ),
                                    );
                                  }

                                  await _loadEntries();
                                  if (mounted) setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _ResultsGroupScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByVariety;
  final bool isQrEntryMode;

  const _ResultsGroupScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.entries,
    required this.judges,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByVariety,
    required this.isQrEntryMode,
  });

  @override
  State<_ResultsGroupScreen> createState() => _ResultsGroupScreenState();
}

class _ResultsGroupScreenState extends State<_ResultsGroupScreen> {
  late List<Map<String, dynamic>> _entries;
  late final List<String> _entryNavigationOrder;
  String? _msg;
  bool _savingJudge = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
  }

  Map<String, List<Map<String, dynamic>>> _groupByGroupName() {
    final out = <String, List<Map<String, dynamic>>>{};

    for (final e in _entries) {
      final isFur = _isFurEntry(e);
      String groupName;

      if (isFur) {
        groupName = 'Fur / Wool';
      } else {
        groupName = (
          e['group_name'] ??
          e['group_display_name'] ??
          e['group_label'] ??
          e['group'] ??
          e['group_code'] ??
          ''
        ).toString().trim();

        if (groupName.isEmpty && widget.showsByVariety == false) {
          groupName = (e['variety'] ?? e['variety_name'] ?? '').toString().trim();
        }

        if (groupName.isEmpty) {
          groupName = '(No Group Assigned)';
        }
      }

      out.putIfAbsent(groupName, () => <Map<String, dynamic>>[]);
      out[groupName]!.add(e);
    }

    return out;
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';

    for (final j in widget.judges) {
      final savedJudgeId = (j['id'] ?? '').toString().trim();
      final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
      final assignmentId = (j['assignment_id'] ?? '').toString().trim();

      if (savedJudgeId == judgeId ||
          masterJudgeId == judgeId ||
          assignmentId == judgeId) {
        return (j['name'] ?? '').toString().trim();
      }
    }

    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return name.isEmpty ? 'Judge: Not set' : 'Judge: $name';
  }

  // --- Completion/Status Highlighting Helpers ---
  _ResultScopeCompletion _completionFor(List<Map<String, dynamic>> entries) {
    return _resultCompletionForEntries(
      entries,
      requireVarietyAwards: widget.showsByVariety,
      requireGroupAwards: true,
      requireBreedAwards: false,
    );
  }

  bool _hasResult(Map<String, dynamic> entry) {
    return _entryHasBasicOutcome(entry);
  }

  int _completedCount(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).completedBasics;
  }

  bool _isComplete(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.complete;
  }

  bool _isInProgress(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.inProgress;
  }

  String _statusLabel(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusLabel(_completionFor(entries).status);
  }

  IconData _statusIcon(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusIcon(_completionFor(entries).status);
  }

  Color _statusColor(BuildContext context, List<Map<String, dynamic>> entries) {
    return _resultScopeStatusColor(context, _completionFor(entries).status);
  }


  String? _singleJudgeId(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.length == 1) return ids.first;
    return null;
  }

  Future<void> _reloadEntries() async {
    final ids = _entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return;

    final rows = await supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': null,
        'p_show_letter': null,
      },
    );

    final refreshed = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) {
          final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
          return ids.contains(id);
        })
        .toList();

    final refreshedIds = refreshed
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();

    final awardsByEntryId = await _loadAwardsByEntryId(
      showId: widget.showId,
      entryIds: refreshedIds,
    );

    for (final e in refreshed) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();

      e['id'] ??= e['entry_id'];

      final rawBreed = (e['breed'] ?? '').toString().trim();
      final rawBreedName = (e['breed_name'] ?? '').toString().trim();
      e['breed'] = rawBreed.isNotEmpty ? rawBreed : rawBreedName;

      final rawVariety = (e['variety'] ?? '').toString().trim();
      final rawVarietyName = (e['variety_name'] ?? '').toString().trim();
      e['variety'] = rawVariety.isNotEmpty ? rawVariety : rawVarietyName;

      e['animal_name'] ??= '';

      final normalizedGroup = (
        e['group_name'] ??
        e['group_display_name'] ??
        e['group_label'] ??
        e['group'] ??
        e['group_code']
      )?.toString().trim();

      e['group_name'] =
          (normalizedGroup == null || normalizedGroup.isEmpty)
              ? null
              : normalizedGroup;

      e['_awards'] = awardsByEntryId[id] ?? <String>[];
    }

    if (!mounted) return;

    if (refreshed.isEmpty) {
      setState(() {});
      return;
    }

    setState(() {
      _entries = _mergeRefreshedEntriesWithoutDroppingCurrentRows(
        currentEntries: _entries,
        refreshedEntries: refreshed,
      );
    });
  }

  Future<void> _applyJudgeToEntries(
    List<Map<String, dynamic>> entries,
    String? judgeId,
  ) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      final ids = entries
          .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet()
          .toList();

      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _savingJudge = false;
          _msg = 'No entries found to update.';
        });
        return;
      }

      if (!widget.isQrEntryMode) {
        await ShowLockService.assertShowUnlocked(widget.showId);
      }

      final normalizedJudgeId =
          (judgeId == null || judgeId.trim().isEmpty) ? null : judgeId.trim();

      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.skip(i).take(100).toList();

        await supabase
            .from('entries')
            .update({
              'judged_by_show_judge_id': normalizedJudgeId,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .inFilter('id', chunk);
      }

      await _reloadEntries();

      if (!mounted) return;

      setState(() {
        _savingJudge = false;
        _msg = 'Judge updated.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _savingJudge = false;
        _msg = 'Judge update failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByGroupName();
    final groups = (grouped.keys.toList()
      ..sort((a, b) {
        int sortFor(String key) {
          final rows = grouped[key] ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return 9999;
          final raw = rows.first['group_sort_order'];
          if (raw is int) return raw;
          return int.tryParse(raw?.toString() ?? '') ?? 9999;
        }

        final bySort = sortFor(a).compareTo(sortFor(b));
        if (bySort != 0) return bySort;
        return a.toLowerCase().compareTo(b.toLowerCase());
      }));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        title: Text(widget.breed),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${widget.showName} • ${widget.sectionLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _singleJudgeId(_entries),
                      decoration: const InputDecoration(
                        labelText: 'Judge for this breed',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('(Not set)'),
                        ),
                        ...widget.judges.map(
                          (j) => DropdownMenuItem<String>(
                            value: (j['id'] ?? '').toString(),
                            child: Text((j['name'] ?? '').toString()),
                          ),
                        ),
                      ],
                      onChanged: _savingJudge
                          ? null
                          : (v) {
                              _applyJudgeToEntries(
                                _entries,
                                (v == null || v.isEmpty) ? null : v,
                              );
                            },
                    ),
                    if (AppSession.isSupportMode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.support_agent, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Support Mode — You are entering results as an admin while viewing another user.',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_msg != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _msg!,
                          style: TextStyle(
                            color: _msg == 'Judge updated.'
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final groupName = groups[i];
                final groupEntries = grouped[groupName]!;
                final count = groupEntries.length;
                final completed = _completedCount(groupEntries);
                final statusColor = _statusColor(context, groupEntries);
                final groupSpecials = _specialsSummaryForEntries(
                  groupEntries,
                  widget.showsByVariety
                      ? const ['BOG', 'BOSG', 'BOV', 'BOSV']
                      : const ['BOG', 'BOSG'],
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  color: statusColor.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      child: Icon(
                        _statusIcon(groupEntries),
                        color: statusColor,
                      ),
                    ),
                    title: Text(
                      groupName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$completed/$count entered • ${_statusLabel(groupEntries)}\n${_judgeSummary(groupEntries)}${groupSpecials.isEmpty ? '' : '\n$groupSpecials'}',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      if (widget.showsByVariety &&
                          groupName != 'Fur / Wool' &&
                          groupName != '(No Group Assigned)') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ResultsVarietyScreen(
                              showId: widget.showId,
                              showName: widget.showName,
                              sectionLabel: widget.sectionLabel,
                              breed: widget.breed,
                              entries: groupEntries,
                              judges: widget.judges,
                              breedClassSystems: widget.breedClassSystems,
                              finalAwardMode: widget.finalAwardMode,
                              parentGroupLabel: groupName,
                              isQrEntryMode: widget.isQrEntryMode,
                            ),
                          ),
                        );
                      } else {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ResultsClassSexScreen(
                              showId: widget.showId,
                              showName: widget.showName,
                              sectionLabel: widget.sectionLabel,
                              breed: widget.breed,
                              variety: '',
                              contextLabel: groupName,
                              entries: groupEntries,
                              judges: widget.judges,
                              breedClassSystems: widget.breedClassSystems,
                              finalAwardMode: widget.finalAwardMode,
                              showsByGroup: true,
                              showsByVariety: false,
                              isQrEntryMode: widget.isQrEntryMode,
                            ),
                          ),
                        );
                      }

                      await _reloadEntries();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsVarietyScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final String? parentGroupLabel;
  final bool isQrEntryMode;

  const _ResultsVarietyScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.entries,
    required this.judges,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.parentGroupLabel,
    required this.isQrEntryMode,
  });

  @override
  State<_ResultsVarietyScreen> createState() => _ResultsVarietyScreenState();
}

class _ResultsVarietyScreenState extends State<_ResultsVarietyScreen> {
  late List<Map<String, dynamic>> _entries;
  String? _msg;
  bool _savingJudge = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
  }

    Map<String, List<Map<String, dynamic>>> _groupByVariety() {
      final out = <String, List<Map<String, dynamic>>>{};

      for (final e in _entries) {
        String key;

        if (_isFurEntry(e)) {
          key = 'Fur / Wool';
        } else {
          key = (e['variety'] ?? '').toString().trim();
        }

        if (key.isEmpty) key = '(No Variety)';

        out.putIfAbsent(key, () => <Map<String, dynamic>>[]);
        out[key]!.add(e);
      }

      return out;
    }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';

    for (final j in widget.judges) {
      final savedJudgeId = (j['id'] ?? '').toString().trim();
      final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
      final assignmentId = (j['assignment_id'] ?? '').toString().trim();

      if (savedJudgeId == judgeId ||
          masterJudgeId == judgeId ||
          assignmentId == judgeId) {
        return (j['name'] ?? '').toString().trim();
      }
    }

    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return name.isEmpty ? 'Judge: Not set' : 'Judge: $name';
  }

  // --- Completion/Status Highlighting Helpers ---
  _ResultScopeCompletion _completionFor(List<Map<String, dynamic>> entries) {
    return _resultCompletionForEntries(
      entries,
      requireVarietyAwards: entries.any((entry) => !_isFurEntry(entry)),
      requireGroupAwards: false,
      requireBreedAwards: false,
    );
  }

  bool _hasResult(Map<String, dynamic> entry) {
    return _entryHasBasicOutcome(entry);
  }

  int _completedCount(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).completedBasics;
  }

  bool _isComplete(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.complete;
  }

  bool _isInProgress(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.inProgress;
  }

  String _statusLabel(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusLabel(_completionFor(entries).status);
  }

  IconData _statusIcon(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusIcon(_completionFor(entries).status);
  }

  Color _statusColor(BuildContext context, List<Map<String, dynamic>> entries) {
    return _resultScopeStatusColor(context, _completionFor(entries).status);
  }

  String? _singleJudgeId(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.length == 1) return ids.first;
    return null;
  }

  Future<void> _reloadEntries() async {
    final ids = _entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return;

    final rows = await supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': null,
        'p_show_letter': null,
      },
    );

    final refreshed = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) {
          final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
          return ids.contains(id);
        })
        .toList();

    final refreshedIds = refreshed
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();

    final awardsByEntryId = await _loadAwardsByEntryId(
      showId: widget.showId,
      entryIds: refreshedIds,
    );

    for (final e in refreshed) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();

      e['id'] ??= e['entry_id'];
      e['breed'] ??= e['breed_name'];
      e['variety'] ??= e['variety_name'];
      e['animal_name'] ??= '';

      final normalizedGroup = (
        e['group_name'] ??
        e['group_display_name'] ??
        e['group_label'] ??
        e['group'] ??
        e['group_code']
      )?.toString().trim();

      e['group_name'] =
          (normalizedGroup == null || normalizedGroup.isEmpty)
              ? null
              : normalizedGroup;

      e['_awards'] = awardsByEntryId[id] ?? <String>[];
    }

    if (!mounted) return;

    if (refreshed.isEmpty) {
      setState(() {});
      return;
    }

    setState(() {
      _entries = _mergeRefreshedEntriesWithoutDroppingCurrentRows(
        currentEntries: _entries,
        refreshedEntries: refreshed,
      );
    });
  }

  Future<void> _applyJudgeToEntries(
    List<Map<String, dynamic>> entries,
    String? judgeId,
  ) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      final ids = entries
          .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet()
          .toList();

      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _savingJudge = false;
          _msg = 'No entries found to update.';
        });
        return;
      }

      if (!widget.isQrEntryMode) {
        await ShowLockService.assertShowUnlocked(widget.showId);
      }

      final normalizedJudgeId =
          (judgeId == null || judgeId.trim().isEmpty) ? null : judgeId.trim();

      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.skip(i).take(100).toList();

        await supabase
            .from('entries')
            .update({
              'judged_by_show_judge_id': normalizedJudgeId,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .inFilter('id', chunk);
      }

      for (final e in _entries) {
        final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
        if (ids.contains(id)) {
          e['judged_by_show_judge_id'] = normalizedJudgeId;
        }
      }

      await _reloadEntries();

      if (!mounted) return;

      setState(() {
        _savingJudge = false;
        _msg = 'Judge updated.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _savingJudge = false;
        _msg = 'Judge update failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByVariety();
    final varieties = grouped.keys.toList()
      ..sort((a, b) {
        int sortFor(String key) {
          final rows = grouped[key] ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return 9999;
          final raw = rows.first['variety_sort_order'];
          if (raw is int) return raw;
          return int.tryParse(raw?.toString() ?? '') ?? 9999;
        }

        // Force White, then Colored at top
        if (a == 'White') return -1;
        if (b == 'White') return 1;
        if (a == 'Colored') return -1;
        if (b == 'Colored') return 1;

        final aIsFur = a.trim().toLowerCase() == 'fur / wool';
        final bIsFur = b.trim().toLowerCase() == 'fur / wool';

        if (aIsFur != bIsFur) return aIsFur ? 1 : -1;

        final bySort = sortFor(a).compareTo(sortFor(b));
        if (bySort != 0) return bySort;

        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        title: Text(widget.parentGroupLabel ?? widget.breed),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.parentGroupLabel == null
                            ? '${widget.showName} • ${widget.sectionLabel} • ${widget.breed}'
                            : '${widget.showName} • ${widget.sectionLabel} • ${widget.breed} • ${widget.parentGroupLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _msg!,
                          style: TextStyle(
                            color: _msg == 'Judge updated.'
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: varieties.length,
              itemBuilder: (context, i) {
                final variety = varieties[i];
                final varietyEntries = grouped[variety]!;
                final count = varietyEntries.length;
                final completed = _completedCount(varietyEntries);
                final statusColor = _statusColor(context, varietyEntries);
                final varietySpecials = _specialsSummaryForEntries(
                  varietyEntries,
                  const ['BOV', 'BOSV'],
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  color: statusColor.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withValues(alpha: 0.12),
                            child: Icon(
                              _statusIcon(varietyEntries),
                              color: statusColor,
                            ),
                          ),
                          title: Text(
                            variety,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '$completed/$count entered • ${_statusLabel(varietyEntries)}\n${_judgeSummary(varietyEntries)}${varietySpecials.isEmpty ? '' : '\n$varietySpecials'}',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _ResultsClassSexScreen(
                                  showId: widget.showId,
                                  showName: widget.showName,
                                  sectionLabel: widget.sectionLabel,
                                  breed: widget.breed,
                                  variety: variety,
                                  contextLabel: _isFurEntry(varietyEntries.first)
                                      ? 'Fur / Wool'
                                      : (widget.parentGroupLabel ?? variety),
                                  entries: varietyEntries,
                                  judges: widget.judges,
                                  breedClassSystems: widget.breedClassSystems,
                                  finalAwardMode: widget.finalAwardMode,
                                  showsByGroup: !_isFurEntry(varietyEntries.first) &&
                                      ((widget.parentGroupLabel ?? '').trim().isNotEmpty ||
                                          varietyEntries.any((e) {
                                            final usesGroupsRaw = e['uses_group_awards'];
                                            final usesGroups = usesGroupsRaw == true ||
                                                usesGroupsRaw.toString().trim().toLowerCase() == 'true' ||
                                                usesGroupsRaw.toString().trim().toLowerCase() == 't' ||
                                                usesGroupsRaw.toString().trim() == '1';
                                            final groupName = (
                                              e['group_name'] ??
                                              e['group_display_name'] ??
                                              e['group_label'] ??
                                              e['group'] ??
                                              e['group_code'] ??
                                              ''
                                            ).toString().trim();

                                            return usesGroups && groupName.isNotEmpty;
                                          })),
                                  showsByVariety: !_isFurEntry(varietyEntries.first),
                                  isQrEntryMode: widget.isQrEntryMode,
                                ),
                              ),
                            );

                            await _reloadEntries();
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey('variety-judge-$variety-${_singleJudgeId(varietyEntries) ?? 'mixed'}'),
                          initialValue: _singleJudgeId(varietyEntries),
                          decoration: const InputDecoration(
                            labelText: 'Judge for this variety',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('(Not set)'),
                            ),
                            ...widget.judges.map(
                              (j) => DropdownMenuItem<String>(
                                value: (j['id'] ?? '').toString(),
                                child: Text((j['name'] ?? '').toString()),
                              ),
                            ),
                          ],
                          onChanged: _savingJudge
                              ? null
                              : (v) {
                                  _applyJudgeToEntries(
                                    varietyEntries,
                                    (v == null || v.isEmpty) ? null : v,
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsClassSexScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final String variety;
  final String contextLabel;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByGroup;
  final bool showsByVariety;
  final bool isQrEntryMode;

  const _ResultsClassSexScreen({
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.variety,
    required this.contextLabel,
    required this.entries,
    required this.judges,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByGroup,
    required this.showsByVariety,
    required this.isQrEntryMode,
  });

  @override
  State<_ResultsClassSexScreen> createState() => _ResultsClassSexScreenState();
}

class _ResultsClassSexScreenState extends State<_ResultsClassSexScreen> {
  late List<Map<String, dynamic>> _entries;
  String? _msg;
  bool _savingJudge = false;

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
  }


    String _furWoolBucketLabel(Map<String, dynamic> e) {
      final rawClass = (e['class_name'] ?? '').toString().trim();
      final lowerClass = rawClass.toLowerCase();

      if (lowerClass.startsWith('fur - ') ||
          lowerClass.startsWith('commercial fur - ') ||
          lowerClass.startsWith('wool - ')) {
        return rawClass;
      }

      final rawVariety = (e['fur_variety'] ?? e['variety'] ?? '').toString().trim();

      if (lowerClass.contains('wool')) {
        return rawVariety.isNotEmpty ? 'Wool - $rawVariety' : 'Wool';
      }

      if (lowerClass.contains('fur')) {
        return rawVariety.isNotEmpty ? 'Fur - $rawVariety' : 'Fur';
      }

      return rawVariety.isNotEmpty ? 'Fur/Wool - $rawVariety' : 'Fur/Wool';
    }
  
  bool _isFurOrWoolEntry(Map<String, dynamic> row) {
    final value = row['is_fur'];
    if (value is bool) return value;

    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1' || text == 'yes';
  }

  String _ageClassOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();

      if (lower.contains('pre-junior') ||
          lower.contains('pre junior') ||
          lower.contains('prejunior') ||
          lower.startsWith('pre jr') ||
          lower.startsWith('pre-jr')) {
        return 'Pre-Junior';
      }

    if (lower.contains('senior') || lower.startsWith('sr')) return 'Senior';
    if (lower.contains('intermediate') || lower.startsWith('int')) return 'Intermediate';
    if (lower.contains('junior') || lower.startsWith('jr')) return 'Junior';
    if (lower.contains('open')) return 'Open';
    return s;
  }

  int _classRank(String v) {
    final x = v.toLowerCase().trim();

    if (x.contains('senior') || x.startsWith('sr')) return 0;
    if (x.contains('intermediate') || x.startsWith('int')) return 1;
    if ((x.contains('junior') || x.startsWith('jr')) && !x.contains('pre')) {
      return 2;
    }
    if (x.contains('pre-junior') ||
        x.contains('pre junior') ||
        x.contains('prejunior') ||
        x.startsWith('pre jr') ||
        x.startsWith('pre-jr')) {
      return 3;
    }

    return 99;
  }

  int _sexRank(String v) {
    final x = v.toLowerCase();
    if (x.contains('buck') || x.contains('boar')) return 0;
    if (x.contains('doe') || x.contains('sow')) return 1;
    return 99;
  }

  int _labelSortKey(String label) {
    final lower = label.trim().toLowerCase();

    if (lower == 'white') return 1000;
    if (lower == 'colored' || lower == 'colour') return 1001;

    if (lower.startsWith('fur - ')) return 1000;
    if (lower.startsWith('commercial fur - ')) return 1001;
    if (lower.startsWith('wool - ')) return 1002;
    if (lower == 'fur') return 1000;
    if (lower == 'wool') return 1001;
    if (lower == 'fur/wool') return 1002;
    if (lower == 'fur / wool') return 1002;

    final cls = _ageClassOnly(label);
    final sexPart = lower.contains('buck') || lower.contains('boar')
        ? 'buck'
        : lower.contains('doe') || lower.contains('sow')
            ? 'doe'
            : '';

    final classRank = _classRank(cls);
    final sexRank = _sexRank(sexPart);

    return (classRank * 10) + sexRank;
  }

  Future<void> _openClassSexByIndex(int index) async {
    final grouped = _groupByClassSex();
    final labels = _sortedLabels(grouped);

    if (index < 0 || index >= labels.length) return;

    final label = labels[index];
    final classEntries = grouped[label] ?? const <Map<String, dynamic>>[];
    if (classEntries.isEmpty) return;

    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsAnimalsScreen(
          showId: widget.showId,
          showName: widget.showName,
          sectionLabel: widget.sectionLabel,
          breed: widget.breed,
          variety: widget.variety,
          classSexLabel: label,
          isFurOrWoolClass: classEntries.any(_isFurEntry),
          entries: classEntries,
          judges: widget.judges,
          onBulkJudgeApply: _applyJudgeToEntries,
          initialJudgeId: _singleJudgeId(classEntries),
          breedClassSystems: widget.breedClassSystems,
          finalAwardMode: widget.finalAwardMode,
          showsByGroup: widget.showsByGroup,
          showsByVariety: widget.showsByVariety,
          isQrEntryMode: widget.isQrEntryMode,
        ),
      ),
    );

    if (!mounted) return;

    if (completed == true) {
      await _openClassSexByIndex(index + 1);
      await _reloadEntries();
      if (mounted) setState(() {});
      return;
    }

    await _reloadEntries();
    if (mounted) setState(() {});
  }

  List<String> _sortedLabels(Map<String, List<Map<String, dynamic>>> grouped) {
    final labels = grouped.keys.toList()
      ..sort((a, b) {
        final aRows = grouped[a] ?? const <Map<String, dynamic>>[];
        final bRows = grouped[b] ?? const <Map<String, dynamic>>[];

        final aFirst = aRows.isEmpty ? <String, dynamic>{} : aRows.first;
        final bFirst = bRows.isEmpty ? <String, dynamic>{} : bRows.first;

        final aIsFur = aRows.any(_isFurEntry);
        final bIsFur = bRows.any(_isFurEntry);
        if (aIsFur != bIsFur) return aIsFur ? 1 : -1;

        if (aIsFur && bIsFur) {
          final furCmp = _labelSortKey(a).compareTo(_labelSortKey(b));
          if (furCmp != 0) return furCmp;
        }

        final classCmp = _resultSortValue(aFirst, 'class_sort_order')
            .compareTo(_resultSortValue(bFirst, 'class_sort_order'));
        if (classCmp != 0) return classCmp;

        final sexCmp = _resultSortValue(aFirst, 'sex_sort_order')
            .compareTo(_resultSortValue(bFirst, 'sex_sort_order'));
        if (sexCmp != 0) return sexCmp;

        return _resultSortText(a).compareTo(_resultSortText(b));
      });

    return labels;
  }
    Map<String, List<Map<String, dynamic>>> _groupByClassSex() {
      final out = <String, List<Map<String, dynamic>>>{};

      for (final e in _entries) {
        String key;

        if (_isFurOrWoolEntry(e)) {
          final furVariety = (e['fur_variety'] ?? e['variety'] ?? '')
              .toString()
              .trim()
              .toLowerCase();

          if (furVariety == 'white' ||
              furVariety.contains('white') ||
              furVariety == 'rew' ||
              furVariety == 'bew') {
            key = 'White';
          } else {
            key = 'Colored';
          }
        } else {
          final cls = _ageClassOnly((e['class_name'] ?? '').toString());
          final sex = (e['sex'] ?? '').toString().trim();
          final label = [
            if (cls.isNotEmpty) cls,
            if (sex.isNotEmpty) sex,
          ].join(' ');
          key = label.isEmpty ? '(Unknown Class)' : label;
        }

        out.putIfAbsent(key, () => <Map<String, dynamic>>[]);
        out[key]!.add(e);
      }

      return out;
    }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';

    for (final j in widget.judges) {
      final savedJudgeId = (j['id'] ?? '').toString().trim();
      final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
      final assignmentId = (j['assignment_id'] ?? '').toString().trim();

      if (savedJudgeId == judgeId ||
          masterJudgeId == judgeId ||
          assignmentId == judgeId) {
        return (j['name'] ?? '').toString().trim();
      }
    }

    return '';
  }

  String _judgeSummary(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return 'Judge: Not set';
    if (ids.length > 1) return 'Judge: Mixed';

    final id = ids.first;
    final name = _judgeNameById(id);
    return name.isEmpty ? 'Judge: Not set' : 'Judge: $name';
  }

  // --- Completion/Status Highlighting Helpers ---
  _ResultScopeCompletion _completionFor(List<Map<String, dynamic>> entries) {
    return _resultCompletionForEntries(
      entries,
      requireVarietyAwards: false,
      requireGroupAwards: false,
      requireBreedAwards: false,
    );
  }

  bool _hasResult(Map<String, dynamic> entry) {
    return _entryHasBasicOutcome(entry);
  }

  int _completedCount(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).completedBasics;
  }

  bool _isComplete(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.complete;
  }

  bool _isInProgress(List<Map<String, dynamic>> entries) {
    return _completionFor(entries).status == _ResultScopeStatus.inProgress;
  }

  String _statusLabel(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusLabel(_completionFor(entries).status);
  }

  IconData _statusIcon(List<Map<String, dynamic>> entries) {
    return _resultScopeStatusIcon(_completionFor(entries).status);
  }

  Color _statusColor(BuildContext context, List<Map<String, dynamic>> entries) {
    return _resultScopeStatusColor(context, _completionFor(entries).status);
  }

  String? _singleJudgeId(List<Map<String, dynamic>> entries) {
    final ids = entries
        .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.length == 1) return ids.first;
    return null;
  }

  Future<void> _reloadEntries() async {
    final ids = _entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (ids.isEmpty) return;

    final rows = await supabase.rpc(
      'report_results_entry_rows',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': null,
        'p_show_letter': null,
      },
    );

    final refreshed = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) {
          final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
          return ids.contains(id);
        })
        .toList();

    final refreshedIds = refreshed
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();

    final awardsByEntryId = await _loadAwardsByEntryId(
      showId: widget.showId,
      entryIds: refreshedIds,
    );

    for (final e in refreshed) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();

      e['id'] ??= e['entry_id'];
      e['breed'] ??= e['breed_name'];
      e['variety'] ??= e['variety_name'];
      e['animal_name'] ??= '';

      final normalizedGroup = (
        e['group_name'] ??
        e['group_display_name'] ??
        e['group_label'] ??
        e['group'] ??
        e['group_code']
      )?.toString().trim();

      e['group_name'] =
          (normalizedGroup == null || normalizedGroup.isEmpty)
              ? null
              : normalizedGroup;

      e['_awards'] = awardsByEntryId[id] ?? <String>[];
    }

    if (!mounted) return;

    if (refreshed.isEmpty) {
      setState(() {});
      return;
    }

    setState(() {
      _entries = _mergeRefreshedEntriesWithoutDroppingCurrentRows(
        currentEntries: _entries,
        refreshedEntries: refreshed,
      );
    });
  }

  Future<void> _applyJudgeToEntries(
    List<Map<String, dynamic>> entries,
    String? judgeId,
  ) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      final ids = entries
          .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet()
          .toList();

      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _savingJudge = false;
          _msg = 'No entries found to update.';
        });
        return;
      }

      if (!widget.isQrEntryMode) {
        await ShowLockService.assertShowUnlocked(widget.showId);
      }

      final normalizedJudgeId =
          (judgeId == null || judgeId.trim().isEmpty) ? null : judgeId.trim();

      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.skip(i).take(100).toList();

        await supabase
            .from('entries')
            .update({
              'judged_by_show_judge_id': normalizedJudgeId,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .inFilter('id', chunk);
      }

      // Immediate local update so child screens/modals inherit it right away.
      for (final e in _entries) {
        final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
        if (ids.contains(id)) {
          e['judged_by_show_judge_id'] = normalizedJudgeId;
        }
      }

      await _reloadEntries();

      if (!mounted) return;

      setState(() {
        _savingJudge = false;
        _msg = 'Judge updated.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _savingJudge = false;
        _msg = 'Judge update failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByClassSex();
    final labels = _sortedLabels(grouped);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        title: Text(widget.contextLabel),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        [
                          widget.showName,
                          widget.sectionLabel,
                          widget.breed,
                          if (widget.contextLabel != widget.breed &&
                              widget.contextLabel.trim().isNotEmpty)
                            widget.contextLabel,
                        ].join(' • '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),

                    const SizedBox(height: 14),

                    DropdownButtonFormField<String>(
                      initialValue: _singleJudgeId(_entries),
                      decoration: const InputDecoration(
                        labelText: 'Judge for this class',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('(Not set)'),
                        ),
                        ...widget.judges.map(
                          (j) => DropdownMenuItem<String>(
                            value: (j['id'] ?? '').toString(),
                            child: Text((j['name'] ?? '').toString()),
                          ),
                        ),
                      ],
                      onChanged: _savingJudge
                          ? null
                          : (v) {
                              _applyJudgeToEntries(
                                _entries,
                                (v == null || v.isEmpty) ? null : v,
                              );
                            },
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _msg!,
                          style: TextStyle(
                            color: _msg == 'Judge updated.'
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: labels.length,
              itemBuilder: (context, i) {
                final label = labels[i];
                final classEntries = grouped[label]!;
                final count = classEntries.length;
                final completed = _completedCount(classEntries);
                final statusColor = _statusColor(context, classEntries);
                final classSpecials = _specialsSummaryForEntries(
                  classEntries,
                  const [
                    'BOV',
                    'BOSV',
                    'BOG',
                    'BOSG',
                    'BOB',
                    'BOSB',
                    'Best Junior',
                    'Best Intermediate',
                    'Best Senior',
                    'Best 4-Class',
                    'Best 6-Class',
                    'Best In Show',
                    'Reserve In Show',
                    'BIS',
                    'RIS',
                    '1RIS',
                    '2RIS',
                    'HM',
                  ],
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  color: statusColor.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      child: Icon(
                        _statusIcon(classEntries),
                        color: statusColor,
                      ),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$completed/$count entered • ${_statusLabel(classEntries)}\n${_judgeSummary(classEntries)}${classSpecials.isEmpty ? '' : '\n$classSpecials'}',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await _openClassSexByIndex(i);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ResultsAnimalsScreen extends StatefulWidget {
  final String showId;
  final String showName;
  final String sectionLabel;
  final String breed;
  final String variety;
  final String classSexLabel;
  final bool isFurOrWoolClass;
  final String? initialJudgeId;
  final String? initialEntryIdToOpen;
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> judges;
  final Future<void> Function(List<Map<String, dynamic>> entries, String? judgeId) onBulkJudgeApply;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByGroup;
  final bool showsByVariety;
  final String? writerName;
  final String? writerPhone;
  final bool isQrEntryMode;
  final Future<void> Function({
    required String entryId,
    required String fieldName,
    required String newValue,
    required String reason,
    required String pinCode,
  })? onQrCorrectionApply;


  const ResultsAnimalsScreen({
    super.key,
    required this.showId,
    required this.showName,
    required this.sectionLabel,
    required this.breed,
    required this.variety,
    required this.classSexLabel,
    required this.isFurOrWoolClass,
    this.initialJudgeId,
    required this.entries,
    required this.judges,
    required this.onBulkJudgeApply,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByGroup,
    required this.showsByVariety,
    this.writerName,
    this.writerPhone,
    this.isQrEntryMode = false,
    this.onQrCorrectionApply,
    this.initialEntryIdToOpen,
  });

  @override
  State<ResultsAnimalsScreen> createState() => ResultsAnimalsScreenState();
}

class ResultsAnimalsScreenState extends State<ResultsAnimalsScreen> {
  late List<Map<String, dynamic>> _entries;
  late final List<String> _entryNavigationOrder;
  String? _msg;
  bool _savingJudge = false;
  String? _currentJudgeId;
  bool _didAutoOpenInitialEntry = false;

  bool _allEntriesComplete() {
    if (_entries.isEmpty) return false;
    return _entries.every(_isEntryComplete);
  }

  bool _isScratched(Map<String, dynamic> e) {
    return (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
  }

  bool _entryIsPlacementEligible(Map<String, dynamic> e) {
    final scratched = _isScratched(e);
    final isShown = e['is_shown'] != false;
    final isDisqualified = e['is_disqualified'] == true;
    final status = (e['result_status'] ?? '').toString().trim();

    if (scratched) return false;
    if (!isShown) return false;
    if (isDisqualified) return false;
    if (status == 'No Show' ||
        _isDisqualifiedStatus(status) ||
        status == 'Unworthy of Award') {
      return false;
    }

    return true;
  }

  bool _entryIsAwardEligible(Map<String, dynamic> e) {
    final scratched = _isScratched(e);
    final isShown = e['is_shown'] != false;
    final isDisqualified = e['is_disqualified'] == true;
    final status = (e['result_status'] ?? '').toString().trim();

    if (scratched) return false;
    if (!isShown) return false;
    if (isDisqualified) return false;
    if (status == 'No Show' ||
        _isDisqualifiedStatus(status) ||
        status == 'Unworthy of Award') {
      return false;
    }

    return true;
  }

  List<String> _awardsForEntry(Map<String, dynamic> e) {
    return ((e['_awards'] as List?) ?? const [])
        .map((x) => _canonicalAwardCode(x.toString()))
        .where((x) => x.isNotEmpty)
        .toList();
  }

  String _entryId(Map<String, dynamic> e) =>
      (e['entry_id'] ?? e['id'] ?? '').toString().trim();

  String _entryBreed(Map<String, dynamic> e) =>
      (e['breed'] ?? '').toString().trim();

  String _entryVariety(Map<String, dynamic> e) =>
      (e['variety'] ?? '').toString().trim();

  String _entryGroupName(Map<String, dynamic> e) {
    return (
      e['group_name'] ??
      e['group_display_name'] ??
      e['group_label'] ??
      e['group'] ??
      e['group_code'] ??
      ''
    ).toString().trim();
  }

  String _entrySectionId(Map<String, dynamic> e) =>
      (e['section_id'] ?? '').toString().trim();

  String _entrySex(Map<String, dynamic> e) =>
      (e['sex'] ?? '').toString().trim().toLowerCase();

  bool _placedFirst(Map<String, dynamic> e) {
    return (e['placement'] ?? '').toString().trim() == '1';
  }

  bool _sameRabbitHasPairedConflict(Map<String, dynamic> e) {
    final awards = _awardsForEntry(e).toSet();

    bool hasBoth(String a, String b) => awards.contains(a) && awards.contains(b);

    final finalAwardCount = const [
      'Best In Show',
      'Reserve In Show',
      'BIS',
      'RIS',
      '1RIS',
      '2RIS',
      'HM',
    ].where(awards.contains).length;

    return hasBoth('BOV', 'BOSV') ||
        hasBoth('BOG', 'BOSG') ||
        hasBoth('BOB', 'BOSB') ||
        hasBoth('Best 4-Class', 'Best 6-Class') ||
        finalAwardCount > 1;
  }

  Map<String, dynamic>? _otherWinnerInScope({
    required Map<String, dynamic> entry,
    required String award,
    required bool Function(Map<String, dynamic>) sameScope,
  }) {
    for (final row in _entries) {
      if (_entryId(row) == _entryId(entry)) continue;
      if (!sameScope(row)) continue;
      if (_awardsForEntry(row).contains(award)) return row;
    }
    return null;
  }

  bool _oppositeSex(Map<String, dynamic> a, Map<String, dynamic>? b) {
    if (b == null) return true;
    final sa = _entrySex(a);
    final sb = _entrySex(b);
    if (sa.isEmpty || sb.isEmpty) return true;
    return sa != sb;
  }

  bool _entryHasValidationProblem(Map<String, dynamic> e) {
    final awards = _awardsForEntry(e);
    if (awards.isEmpty) return false;

    if (!_entryIsAwardEligible(e)) return true;
    if (!_placedFirst(e)) return true;
    if (_sameRabbitHasPairedConflict(e)) return true;

    final breedLower = _entryBreed(e).toLowerCase();
    final classSystem = widget.breedClassSystems[breedLower] ?? 'four';

    bool sameVariety(Map<String, dynamic> row) =>
        _entrySectionId(row) == _entrySectionId(e) &&
        _entryBreed(row).toLowerCase() == _entryBreed(e).toLowerCase() &&
        _entryVariety(row).toLowerCase() == _entryVariety(e).toLowerCase();

    bool sameGroup(Map<String, dynamic> row) =>
        _entrySectionId(row) == _entrySectionId(e) &&
        _entryBreed(row).toLowerCase() == _entryBreed(e).toLowerCase() &&
        _entryGroupName(row).toLowerCase() == _entryGroupName(e).toLowerCase();

    bool sameBreed(Map<String, dynamic> row) =>
        _entrySectionId(row) == _entrySectionId(e) &&
        _entryBreed(row).toLowerCase() == _entryBreed(e).toLowerCase();

    bool sameSection(Map<String, dynamic> row) =>
        _entrySectionId(row) == _entrySectionId(e);

    if (awards.contains('BOV')) {
      if (_otherWinnerInScope(entry: e, award: 'BOV', sameScope: sameVariety) != null) {
        return true;
      }
      final bosv =
          _otherWinnerInScope(entry: e, award: 'BOSV', sameScope: sameVariety);
      if (!_oppositeSex(e, bosv)) return true;
    }

    if (awards.contains('BOSV')) {
      if (_otherWinnerInScope(entry: e, award: 'BOSV', sameScope: sameVariety) != null) {
        return true;
      }
      final bov =
          _otherWinnerInScope(entry: e, award: 'BOV', sameScope: sameVariety);
      if (!_oppositeSex(e, bov)) return true;
    }

    if (awards.contains('BOG')) {
      if (_otherWinnerInScope(entry: e, award: 'BOG', sameScope: sameGroup) != null) {
        return true;
      }
      final bosg =
          _otherWinnerInScope(entry: e, award: 'BOSG', sameScope: sameGroup);
      if (!_oppositeSex(e, bosg)) return true;
    }

    if (awards.contains('BOSG')) {
      if (_otherWinnerInScope(entry: e, award: 'BOSG', sameScope: sameGroup) != null) {
        return true;
      }
      final bog =
          _otherWinnerInScope(entry: e, award: 'BOG', sameScope: sameGroup);
      if (!_oppositeSex(e, bog)) return true;
    }

    if (awards.contains('BOB')) {
      if (_otherWinnerInScope(entry: e, award: 'BOB', sameScope: sameBreed) != null) {
        return true;
      }
      final bosb =
          _otherWinnerInScope(entry: e, award: 'BOSB', sameScope: sameBreed);
      if (!_oppositeSex(e, bosb)) return true;

      if (widget.showsByGroup) {
        if (!(awards.contains('BOG') || awards.contains('BOSG'))) return true;
      } else if (widget.showsByVariety) {
        if (!(awards.contains('BOV') || awards.contains('BOSV'))) return true;
      }
    }

    if (awards.contains('BOSB')) {
      if (_otherWinnerInScope(entry: e, award: 'BOSB', sameScope: sameBreed) != null) {
        return true;
      }
      final bob =
          _otherWinnerInScope(entry: e, award: 'BOB', sameScope: sameBreed);
      if (!_oppositeSex(e, bob)) return true;

      if (widget.showsByGroup) {
        if (!(awards.contains('BOG') || awards.contains('BOSG'))) return true;
      } else if (widget.showsByVariety) {
        if (!(awards.contains('BOV') || awards.contains('BOSV'))) return true;
      }
    }

    for (final award in kBestAgeAwardCodes) {
      if (!awards.contains(award)) continue;

      final sameScope = widget.showsByVariety ? sameVariety : sameBreed;

      if (_otherWinnerInScope(
            entry: e,
            award: award,
            sameScope: sameScope,
          ) !=
          null) {
        return true;
      }

      if (!_supportsBestAgeAwards(
        breedName: _entryBreed(e),
        isCavy: _isCavyEntry(e),
      )) {
        return true;
      }

      if (!_bestAgeAwardMatchesClass(
        award: award,
        className: (e['class_name'] ?? '').toString(),
        classSystem: classSystem,
      )) {
        return true;
      }
    }

    if (awards.contains('Best 4-Class')) {
      if (_otherWinnerInScope(
            entry: e,
            award: 'Best 4-Class',
            sameScope: sameSection,
          ) !=
          null) {
        return true;
      }
      if (!awards.contains('BOB')) return true;
      if (classSystem != 'four') return true;
    }

    if (awards.contains('Best 6-Class')) {
      if (_otherWinnerInScope(
            entry: e,
            award: 'Best 6-Class',
            sameScope: sameSection,
          ) !=
          null) {
        return true;
      }
      if (!awards.contains('BOB')) return true;
      if (classSystem != 'six') return true;
    }

    if (awards.contains('Best In Show')) {
      if (_otherWinnerInScope(
            entry: e,
            award: 'Best In Show',
            sameScope: sameSection,
          ) !=
          null) {
        return true;
      }

      if (widget.finalAwardMode == 'four_six_bis') {
        if (!(awards.contains('Best 4-Class') || awards.contains('Best 6-Class'))) {
          return true;
        }
      } else {
        if (!awards.contains('BOB')) return true;
      }
    }

    if (awards.contains('Reserve In Show')) {
      if (_otherWinnerInScope(
            entry: e,
            award: 'Reserve In Show',
            sameScope: sameSection,
          ) !=
          null) {
        return true;
      }

      if (widget.finalAwardMode != 'bis_ris') return true;
      if (!awards.contains('BOB')) return true;
      if (awards.contains('Best In Show')) return true;
    }

    if (awards.contains('1RIS')) {
      if (_otherWinnerInScope(
            entry: e,
            award: '1RIS',
            sameScope: sameSection,
          ) !=
          null) {
        return true;
      }

      if (widget.finalAwardMode != 'bis_1ris_2ris') return true;
      if (!awards.contains('BOB')) return true;
      if (awards.contains('Best In Show') || awards.contains('BIS')) return true;
    }

    if (awards.contains('2RIS')) {
      if (_otherWinnerInScope(
            entry: e,
            award: '2RIS',
            sameScope: sameSection,
          ) !=
          null) {
        return true;
      }

      if (widget.finalAwardMode != 'bis_1ris_2ris') return true;
      if (!awards.contains('BOB')) return true;
      if (awards.contains('Best In Show') || awards.contains('BIS')) return true;
    }

    return false;
  }

    bool _awardDecisionComplete(Map<String, dynamic> e) {
      final awards = _awardsForEntry(e);

      // No award selected is not automatically an error.
      // The higher-level cards handle required BOV/BOSV, BOG/BOSG, BOB/BOSB.
      if (awards.isEmpty) return true;

      return !_entryHasValidationProblem(e);
    }

    bool _isEntryComplete(Map<String, dynamic> e) {
      if (_isScratched(e)) return true;

      final judgeId = (e['judged_by_show_judge_id'] ?? '').toString().trim();
      if (judgeId.isEmpty) return false;

      // Basic animal outcome is required:
      // placement, DQ, No Show, or Unworthy.
      if (!_entryHasBasicOutcome(e)) return false;

      if (!_awardDecisionComplete(e)) return false;

      if (_entryHasValidationProblem(e)) return false;

      return true;
    }

  Color _rowTint(Map<String, dynamic> e) {
    if (_isEntryComplete(e)) {
      return Colors.green.withValues(alpha: .10);
    }
    return Colors.red.withValues(alpha: .08);
  }

  Color _rowBorder(Map<String, dynamic> e) {
    if (_isEntryComplete(e)) {
      return Colors.green.withValues(alpha: .22);
    }
    return Colors.red.withValues(alpha: .18);
  }

  bool get _canRequestQrCorrection =>
      widget.isQrEntryMode == true && widget.onQrCorrectionApply != null;

  String _entryCorrectionLabel(Map<String, dynamic> entry) {
    final tattoo = (entry['tattoo'] ?? entry['ear_number'] ?? '').toString().trim();
    final animalName = (entry['animal_name'] ?? '').toString().trim();
    final variety = (entry['variety'] ?? entry['variety_name'] ?? '').toString().trim();
    final className = (entry['class_name'] ?? '').toString().trim();
    final sex = (entry['sex'] ?? '').toString().trim();
    final classSex = [className, sex].where((x) => x.isNotEmpty).join(' ');

    final parts = <String>[
      if (animalName.isNotEmpty) animalName,
      if (tattoo.isNotEmpty) 'Ear # $tattoo',
      if (variety.isNotEmpty) variety,
      if (classSex.isNotEmpty) classSex,
    ];

    return parts.isEmpty ? 'Selected animal' : parts.join(' • ');
  }

  String? _validateCorrectionValue(String fieldName, String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Enter the corrected value.';

    switch (fieldName) {
      case 'tattoo':
        if (text.length > 30) return 'Ear number is too long.';
        return null;
      case 'class_name':
        const allowed = {
          'pre-junior',
          'pre junior',
          'prejunior',
          'junior',
          'intermediate',
          'senior',
          'open',
        };
        if (!allowed.contains(text.toLowerCase())) {
          return 'Class must be Pre-Junior, Junior, Intermediate, Senior, or Open.';
        }
        return null;
      case 'sex':
        const allowed = {'buck', 'doe', 'boar', 'sow'};
        if (!allowed.contains(text.toLowerCase())) {
          return 'Sex must be Buck, Doe, Boar, or Sow.';
        }
        return null;
      case 'variety':
        if (text.length > 80) return 'Variety is too long.';
        return null;
      default:
        return null;
    }
  }

  Future<void> _showQrCorrectionDialog(Map<String, dynamic> entry) async {
    if (!_canRequestQrCorrection) return;

    final entryId = (entry['entry_id'] ?? entry['id'] ?? '').toString().trim();
    if (entryId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to request correction: missing entry id.')),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final newValueController = TextEditingController();
    final reasonController = TextEditingController();
    final pinController = TextEditingController();
    String fieldName = 'tattoo';
    bool saving = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                if (!formKey.currentState!.validate()) return;

                final digitsOnlyPin =
                    pinController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');

                setDialogState(() => saving = true);

                try {
                  await widget.onQrCorrectionApply!(
                    entryId: entryId,
                    fieldName: fieldName,
                    newValue: newValueController.text.trim(),
                    reason: reasonController.text.trim(),
                    pinCode: digitsOnlyPin,
                  );

                  if (!mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _reloadAll();
                  if (!mounted) return;
                  setState(() {
                    _msg = 'Correction saved and logged.';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Correction saved and logged.')),
                  );
                } catch (e) {
                  setDialogState(() => saving = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Correction failed: $e')),
                  );
                }
              }

              return AlertDialog(
                title: const Text('Request Correction'),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _entryCorrectionLabel(entry),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: fieldName,
                          decoration: const InputDecoration(
                            labelText: 'Correction needed',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'tattoo', child: Text('Ear number')),
                            DropdownMenuItem(value: 'class_name', child: Text('Class')),
                            DropdownMenuItem(value: 'sex', child: Text('Sex')),
                            DropdownMenuItem(value: 'variety', child: Text('Variety')),
                          ],
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    fieldName = value;
                                    newValueController.clear();
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: newValueController,
                          enabled: !saving,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Corrected value',
                          ),
                          validator: (value) =>
                              _validateCorrectionValue(fieldName, value ?? ''),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: reasonController,
                          enabled: !saving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Reason / staff note',
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.length < 4) return 'Enter a brief reason.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: pinController,
                          enabled: !saving,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Staff approval PIN',
                          ),
                          validator: (value) {
                            final digits =
                                (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                            if (digits.length < 4 || digits.length > 6) {
                              return 'Enter a 4–6 digit approval PIN.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: saving ? null : submit,
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(saving ? 'Saving...' : 'Save Correction'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      newValueController.dispose();
      reasonController.dispose();
      pinController.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _entries = [...widget.entries];
    _currentJudgeId = _normalizeJudgeId(widget.initialJudgeId);
    _sortEntries();

    _entryNavigationOrder = _entries
        .map(_entryId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialEntryIfNeeded();
    });
  }

  void _sortEntries() {
    int intVal(Map<String, dynamic> e, String key, [int fallback = 9999]) {
      final raw = e[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? fallback;
    }

    String strVal(Map<String, dynamic> e, String key) {
      return (e[key] ?? '').toString().trim().toLowerCase();
    }

    int classSexRank(Map<String, dynamic> e) {
      final cls = strVal(e, 'class_name');
      final sex = strVal(e, 'sex');

      int classRank;
      if (cls.contains('senior') || cls.startsWith('sr')) {
        classRank = 0;
      } else if (cls.contains('intermediate') || cls.startsWith('int')) {
        classRank = 1;
      } else if (cls.contains('junior') || cls.startsWith('jr')) {
        classRank = 2;
      } else if (cls.contains('pre') || cls.contains('pre-jr') || cls.contains('pre jr')) {
        classRank = 3;
      } else {
        classRank = 99;
      }

      int sexRank;
      if (sex.contains('buck') || sex.contains('boar')) {
        sexRank = 0;
      } else if (sex.contains('doe') || sex.contains('sow')) {
        sexRank = 1;
      } else {
        sexRank = 99;
      }

      return (classRank * 10) + sexRank;
    }

    _entries.sort((a, b) {
      final byBreedSort =
          intVal(a, 'breed_sort_order').compareTo(intVal(b, 'breed_sort_order'));
      if (byBreedSort != 0) return byBreedSort;

      final byGroupSort =
          intVal(a, 'group_sort_order').compareTo(intVal(b, 'group_sort_order'));
      if (byGroupSort != 0) return byGroupSort;

      final byVarietySort =
          intVal(a, 'variety_sort_order').compareTo(intVal(b, 'variety_sort_order'));
      if (byVarietySort != 0) return byVarietySort;

      final byClassSex = classSexRank(a).compareTo(classSexRank(b));
      if (byClassSex != 0) return byClassSex;

      final byClassSort =
          intVal(a, 'class_sort_order').compareTo(intVal(b, 'class_sort_order'));
      if (byClassSort != 0) return byClassSort;

      final byTattoo = strVal(a, 'tattoo').compareTo(strVal(b, 'tattoo'));
      if (byTattoo != 0) return byTattoo;

      return strVal(a, 'entry_id').compareTo(strVal(b, 'entry_id'));
    });
  }

  void _openInitialEntryIfNeeded() {
    if (_didAutoOpenInitialEntry) return;
    if (widget.initialEntryIdToOpen == null || widget.initialEntryIdToOpen!.trim().isEmpty) return;

    final index = _entries.indexWhere((e) {
      final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
      return id == widget.initialEntryIdToOpen;
    });

    if (index >= 0 && mounted) {
      _didAutoOpenInitialEntry = true;
      _openResultEntryAt(index);
    }
  }

  String? _normalizeJudgeId(String? storedJudgeId) {
    if (storedJudgeId == null || storedJudgeId.trim().isEmpty) return null;

    final raw = storedJudgeId.trim();

    for (final j in widget.judges) {
      final savedJudgeId = (j['id'] ?? '').toString().trim();
      final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
      final assignmentId = (j['assignment_id'] ?? '').toString().trim();

      if (raw == savedJudgeId ||
          raw == masterJudgeId ||
          raw == assignmentId) {
        return savedJudgeId;
      }
    }

    return raw;
  }

  String _exhibitorName(Map<String, dynamic> e) {
    final label = (e['exhibitor_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    return '(Unknown Exhibitor)';
  }

  String _judgeNameById(String? judgeId) {
    if (judgeId == null || judgeId.isEmpty) return '';

    for (final j in widget.judges) {
      final savedJudgeId = (j['id'] ?? '').toString().trim();
      final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
      final assignmentId = (j['assignment_id'] ?? '').toString().trim();

      if (savedJudgeId == judgeId ||
          masterJudgeId == judgeId ||
          assignmentId == judgeId) {
        return (j['name'] ?? '').toString().trim();
      }
    }

    return '';
  }

  Future<void> _reloadAll() async {
    final currentIds = _entries
        .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();

    if (currentIds.isEmpty) return;

    try {
      final rows = await supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': null,
          'p_show_letter': null,
        },
      );

      final allRows = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final refreshed = allRows.where((row) {
        final id = (row['entry_id'] ?? row['id'] ?? '').toString().trim();
        return currentIds.contains(id);
      }).map((e) {
        final copy = Map<String, dynamic>.from(e);
        copy['id'] ??= copy['entry_id'];
        copy['breed'] ??= copy['breed_name'];
        copy['variety'] ??= copy['variety_name'];
        copy['animal_name'] ??= '';

        final normalizedGroup = (
          copy['group_name'] ??
          copy['group_display_name'] ??
          copy['group_label'] ??
          copy['group'] ??
          copy['group_code']
        )?.toString().trim();

        copy['group_name'] =
            (normalizedGroup == null || normalizedGroup.isEmpty)
                ? null
                : normalizedGroup;

        return copy;
      }).toList();

      if (refreshed.isEmpty) {

        if (mounted) setState(() {});
        return;
      }

      final refreshedIds = refreshed
          .map((e) => (e['entry_id'] ?? e['id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toList();

      final awardsByEntryId = <String, List<String>>{};

      for (var i = 0; i < refreshedIds.length; i += 100) {
        final chunk = refreshedIds.skip(i).take(100).toList();

        final awardRows = await supabase
            .from('entry_awards')
            .select('entry_id,award_code')
            .eq('show_id', widget.showId)
            .inFilter('entry_id', chunk);

        for (final row in (awardRows as List)) {
          final map = Map<String, dynamic>.from(row as Map);
          final entryId = (map['entry_id'] ?? '').toString().trim();
          final award = _canonicalAwardCode(
            (map['award_code'] ?? '').toString(),
          );

          if (entryId.isEmpty || award.isEmpty) continue;

          awardsByEntryId.putIfAbsent(entryId, () => <String>[]);
          awardsByEntryId[entryId]!.add(award);
        }
      }

      for (final e in refreshed) {
        final id = (e['entry_id'] ?? e['id'] ?? '').toString().trim();
        e['_awards'] = awardsByEntryId[id] ?? <String>[];
      }

      _entries = _mergeRefreshedEntriesWithoutDroppingCurrentRows(
        currentEntries: _entries,
        refreshedEntries: refreshed,
      );
      _sortEntries();

      final judgeIds = _entries
          .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .map(_normalizeJudgeId)
          .whereType<String>()
          .toSet();

      _currentJudgeId = judgeIds.length == 1 ? judgeIds.first : null;

      if (mounted) setState(() {});

    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = 'Results updated. Reload warning: $e';
        });
      }
    }
  }

    int _shownCount() {
      return _entries.where((e) {
        final scratched = (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
        final isShown = e['is_shown'] != false;
        final isDisqualified = e['is_disqualified'] == true;
        final status = (e['result_status'] ?? '').toString().trim();

        if (scratched) return false;
        if (!isShown) return false;
        if (isDisqualified) return false;

        if (status == 'No Show' ||
            _isDisqualifiedStatus(status) ||
            status == 'Unworthy of Award') {
          return false;
        }

        return true;
      }).length;
    }

  List<String> _availablePlacements({String? excludingEntryId}) {
    final shownCount = _shownCount();
    final count = shownCount <= 0 ? _entries.length : shownCount;
    final all = List<String>.generate(count, (i) => '${i + 1}');

    final used = <String>{};
    for (final e in _entries) {
      if (excludingEntryId != null &&
          (e['entry_id'] ?? e['id'] ?? '').toString().trim() == excludingEntryId) {
        continue;
      }

      if (!_entryIsPlacementEligible(e)) continue;

      final placement = (e['placement'] ?? '').toString().trim();
      if (placement.isNotEmpty) used.add(placement);
    }

    return all.where((p) => !used.contains(p)).toList();
  }

  Future<void> _applyJudgeToClass(String? judgeId) async {
    setState(() {
      _savingJudge = true;
      _msg = null;
    });

    try {
      await widget.onBulkJudgeApply(_entries, judgeId);

      final normalizedJudgeId = _normalizeJudgeId(judgeId);

      for (final e in _entries) {
        e['judged_by_show_judge_id'] = normalizedJudgeId;
      }

      _currentJudgeId = normalizedJudgeId;

      await _reloadAll();
      if (!mounted) return;
      setState(() {
        _savingJudge = false;
        _msg = 'Judge updated.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingJudge = false;
        _msg = 'Judge update failed: $e';
      });
    }
  }

  Future<void> _openResultEntryAt(int index) async {
    if (index < 0 || index >= _entries.length) return;

    final entry = _entries[index];
    final openedEntryId = (entry['entry_id'] ?? entry['id'] ?? '').toString().trim();

    final result = await showModalBottomSheet<ResultsEntryOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ResultsEntrySheet(
        showId: widget.showId,
        entry: entry,
        classEntries: _entries,
        judges: widget.judges,
        availablePlacements: _availablePlacements(
          excludingEntryId:
              (entry['entry_id'] ?? entry['id'] ?? '').toString().trim(),
        ),
        shownCount: _shownCount(),
        currentIndex: index,
        totalCount: _entries.length,
        breedClassSystems: widget.breedClassSystems,
        finalAwardMode: widget.finalAwardMode,
        showsByGroup: widget.showsByGroup,
        showsByVariety: widget.showsByVariety,
        writerName: widget.writerName,
        writerPhone: widget.writerPhone,
        isQrEntryMode: widget.isQrEntryMode,
        isFurOrWoolClass: widget.isFurOrWoolClass,
        initialJudgeId: _currentJudgeId,
      ),
    );

    if (result == null) return;

    await _reloadAll();

    if (!mounted) return;

    setState(() {
      _msg = 'Results updated.';
    });

    if (!result.goNext) return;

    final openedNavIndex = _entryNavigationOrder.indexOf(openedEntryId);

    final nextEntryId =
        openedNavIndex >= 0 && openedNavIndex + 1 < _entryNavigationOrder.length
            ? _entryNavigationOrder[openedNavIndex + 1]
            : '';

    if (nextEntryId.isNotEmpty) {
      final nextIndex = _entries.indexWhere((e) => _entryId(e) == nextEntryId);

      if (nextIndex >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openResultEntryAt(nextIndex);
          }
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final entryCount = _entries.length;
    final exhibitorCount = _entries
        .map((e) => (e['exhibitor_id'] ?? '').toString())
        .where((x) => x.isNotEmpty)
        .toSet()
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF11285A),
        foregroundColor: Colors.white,
        title: Text(widget.classSexLabel),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        [
                          widget.showName,
                          widget.sectionLabel,
                          widget.breed,
                          if (widget.variety.trim().isNotEmpty) widget.variety,
                        ].join(' • '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _currentJudgeId,
                      decoration: const InputDecoration(
                        labelText: 'Judge for this class',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('(Not set)'),
                        ),
                        ...widget.judges.map(
                          (j) => DropdownMenuItem<String>(
                            value: (j['id'] ?? '').toString(),
                            child: Text((j['name'] ?? '').toString()),
                          ),
                        ),
                      ],
                      onChanged: _savingJudge
                          ? null
                          : (v) {
                              _applyJudgeToClass(
                                (v == null || v.isEmpty) ? null : v,
                              );
                            },
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _infoPill('$entryCount entries'),
                          _infoPill('$exhibitorCount exhibitors'),
                          _infoPill('${_shownCount()} shown/eligible'),
                        ],
                      ),
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _msg!,
                          style: TextStyle(
                            color: _msg == 'Judge updated.' || _msg == 'Results updated.'
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final e = _entries[i];
                final coopNumber = (e['coop_number'] ?? '').toString().trim();
                final animalName = (e['animal_name'] ?? '').toString().trim();
                final tattoo = (e['tattoo'] ?? '').toString().trim();
                final exhibitor = _exhibitorName(e);
                final placement = (e['placement'] ?? '').toString().trim();
                final awards = ((e['_awards'] as List?) ?? const [])
                    .map((x) => _awardDisplayLabel(x.toString(), e))
                    .toList();
                final awardsText = awards.join(', ');
                final isShown = e['is_shown'] != false;
                final isDisqualified = e['is_disqualified'] == true;
                final scratched = (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
                final resultStatus = (e['result_status'] ?? '').toString().trim();
                final judgeId = (e['judged_by_show_judge_id'] ?? '').toString().trim();
                final judgeName = _judgeNameById(judgeId);

                final subtitleParts = <String>[
                  if (exhibitor.isNotEmpty) exhibitor,
                  if (resultStatus.isNotEmpty) 'Status: $resultStatus',
                  if (placement.isNotEmpty) 'Place: $placement',
                  if (awardsText.isNotEmpty) 'Awards: $awardsText',
                  if (judgeId.isNotEmpty) 'Judge: ${judgeName.isEmpty ? judgeId : judgeName}',
                  if (!isShown && resultStatus.isEmpty) 'Not shown',
                  if (isDisqualified && resultStatus.isEmpty) 'Disqualified',
                  if (scratched) 'Scratched',
                ];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  color: _rowTint(e),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: _rowBorder(e)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openResultEntryAt(i),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (coopNumber.isNotEmpty)
                                      Text(
                                        'Coop #: $coopNumber',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    Text(
                                      animalName.isNotEmpty && tattoo.isNotEmpty
                                          ? '$animalName • Ear #: $tattoo'
                                          : animalName.isNotEmpty
                                              ? animalName
                                              : 'Ear #: ${tattoo.isEmpty ? '(No ear #)' : tattoo}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(subtitleParts.join(' • ')),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          if (_canRequestQrCorrection) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _showQrCorrectionDialog(e),
                                icon: const Icon(Icons.edit_note_outlined),
                                label: const Text('Request Correction'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ResultsEntryOutcome {
  final bool goNext;
  final bool classComplete;

  const ResultsEntryOutcome({
    required this.goNext,
    required this.classComplete,
  });
}

class ResultsEntrySheet extends StatefulWidget {
  final String showId;
  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> classEntries;
  final List<Map<String, dynamic>> judges;
  final List<String> availablePlacements;
  final int shownCount;
  final int currentIndex;
  final int totalCount;
  final Map<String, String> breedClassSystems;
  final String finalAwardMode;
  final bool showsByGroup;
  final bool showsByVariety;
  final String? writerName;
  final String? writerPhone;
  final bool isQrEntryMode;
  final bool isFurOrWoolClass;
  final String? initialJudgeId;

  const ResultsEntrySheet({
    super.key,
    required this.showId,
    required this.entry,
    required this.classEntries,
    required this.judges,
    required this.availablePlacements,
    required this.shownCount,
    required this.currentIndex,
    required this.totalCount,
    required this.breedClassSystems,
    required this.finalAwardMode,
    required this.showsByGroup,
    required this.showsByVariety,
    this.writerName,
    this.writerPhone,
    this.isQrEntryMode = false,
    required this.isFurOrWoolClass,
    this.initialJudgeId,
  });

  @override
  State<ResultsEntrySheet> createState() => ResultsEntrySheetState();
}

class ResultsEntrySheetState extends State<ResultsEntrySheet> {
  bool _saving = false;
  String? _msg;

  String? _resultStatus;

  String? _placement;
  String? _judgeId;
  late Set<String> _selectedAwards;

  String get _entryUuid {
    final raw = widget.entry['entry_id'] ?? widget.entry['id'] ?? '';
    return raw.toString().trim();
  }

  @override
  void initState() {
    super.initState();

    final storedStatus = (widget.entry['result_status'] ?? '').toString().trim();

    if (storedStatus.isNotEmpty && kResultStatuses.contains(storedStatus)) {
      _resultStatus = storedStatus;
    } else {
      final hasStoredResult =
          widget.entry['result_status'] != null ||
          widget.entry['placement'] != null ||
          widget.entry['is_disqualified'] == true ||
          widget.entry['disqualified_reason'] != null;

      final isShown = hasStoredResult ? widget.entry['is_shown'] != false : true;

      final isDisqualified = widget.entry['is_disqualified'] == true;
      final dqReason =
          (widget.entry['disqualified_reason'] ?? '').toString().trim();

      if (!isShown) {
        _resultStatus = 'No Show';
      } else if (isDisqualified) {
        if (dqReason == 'Wrong Sex') {
          _resultStatus = 'Disqualified - Wrong Sex';
        } else if (dqReason == 'Wrong Variety') {
          _resultStatus = 'Disqualified - Wrong Variety';
        } else if (dqReason == 'Wrong Class') {
          _resultStatus = 'Disqualified - Wrong Class';
        } else if (dqReason == 'Overweight') {
          _resultStatus = 'Disqualified - Overweight';
        } else {
          _resultStatus = 'Disqualified - Other';
        }
      } else {
        _resultStatus = 'Shown';
      }
    }

String storedJudgeId =
    (widget.entry['judged_by_show_judge_id'] ?? '').toString().trim();

if (storedJudgeId.isEmpty) {
  storedJudgeId = (widget.initialJudgeId ?? '').toString().trim();

  if (storedJudgeId.isNotEmpty) {
    widget.entry['judged_by_show_judge_id'] = storedJudgeId;
  }
}

if (storedJudgeId.isEmpty) {
  final classJudgeIds = widget.classEntries
      .map((e) => (e['judged_by_show_judge_id'] ?? '').toString().trim())
      .where((x) => x.isNotEmpty)
      .toSet();

  if (classJudgeIds.length == 1) {
    storedJudgeId = classJudgeIds.first;
    widget.entry['judged_by_show_judge_id'] = storedJudgeId;
  }
}

if (storedJudgeId.isEmpty) {
  _judgeId = null;
} else {
  String? matched;

  for (final j in widget.judges) {
    final savedJudgeId = (j['id'] ?? '').toString().trim();
    final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
    final assignmentId = (j['assignment_id'] ?? '').toString().trim();

    if (storedJudgeId == savedJudgeId ||
        storedJudgeId == masterJudgeId ||
        storedJudgeId == assignmentId) {
      matched = savedJudgeId;
      break;
    }
  }

  _judgeId = matched ?? storedJudgeId;
}

    final currentPlacement = (widget.entry['placement'] ?? '').toString().trim();
    _placement = currentPlacement.isEmpty ? null : currentPlacement;

    _selectedAwards = (((widget.entry['_awards'] as List?) ?? const [])
            .map((x) => _canonicalAwardCode(x.toString()))
            .where((x) => x.isNotEmpty))
        .toSet();

  }

  @override
  void dispose() {
    super.dispose();
  }

  bool _isScratched(Map<String, dynamic> e) {
    return (e['scratched_at'] ?? '').toString().trim().isNotEmpty;
  }

  String _sex(Map<String, dynamic> e) => (e['sex'] ?? '').toString().trim().toLowerCase();

  String _breed(Map<String, dynamic> e) => (e['breed'] ?? '').toString().trim();

  String _variety(Map<String, dynamic> e) => (e['variety'] ?? '').toString().trim();

  String _groupName(Map<String, dynamic> e) {
    return (
      e['group_name'] ??
      e['group_display_name'] ??
      e['group_label'] ??
      e['group'] ??
      e['group_code'] ??
      ''
    ).toString().trim();
  }

  String _entryId(Map<String, dynamic> e) =>
    (e['entry_id'] ?? e['id'] ?? '').toString().trim();

  String _sectionId(Map<String, dynamic> e) => (e['section_id'] ?? '').toString().trim();

  List<String> _entryAwards(Map<String, dynamic> e) =>
      (((e['_awards'] as List?) ?? const [])
              .map((x) => _canonicalAwardCode(x.toString()))
              .where((x) => x.isNotEmpty))
          .toList();

  String _effectiveStatusFor(Map<String, dynamic> e) {
    if (_entryId(e) == _entryUuid) {
      return (_resultStatus ?? 'Shown').trim();
    }
    return (e['result_status'] ?? '').toString().trim();
  }

  String _effectivePlacementFor(Map<String, dynamic> e) {
    if (_entryId(e) == _entryUuid) {
      return (_placement ?? '').trim();
    }
    return (e['placement'] ?? '').toString().trim();
  }

  bool _placedFirst(Map<String, dynamic> e) {
    return _effectivePlacementFor(e) == '1';
  }

  bool _isFurOrWoolResultRow() {
    if (widget.isFurOrWoolClass) return true;

    final className =
        (widget.entry['class_name'] ?? '').toString().trim().toLowerCase();

    return className.startsWith('fur') ||
        className.startsWith('commercial fur') ||
        className.startsWith('wool');
  }

  List<String> _pairedAwardsFor(String award) {
    switch (award) {
      case 'BOV':
      case 'BOSV':
        return const ['BOV', 'BOSV'];

      case 'BOG':
      case 'BOSG':
        return const ['BOG', 'BOSG'];

      case 'BOB':
      case 'BOSB':
        return const ['BOB', 'BOSB'];

      case 'Best 4-Class':
      case 'Best 6-Class':
        return const ['Best 4-Class', 'Best 6-Class'];

      case 'Best In Show':
      case 'Reserve In Show':
      case 'BIS':
      case 'RIS':
      case '1RIS':
      case '2RIS':
      case 'HM':
        return const [
          'Best In Show',
          'Reserve In Show',
          'BIS',
          'RIS',
          '1RIS',
          '2RIS',
          'HM',
        ];

      default:
        return const [];
    }
  }

  bool _sameRabbitAlreadyHasConflictingStageAward(String award) {
    final pair = _pairedAwardsFor(award);
    if (pair.isEmpty) return false;

    final others = pair.where((a) => a != award);
    return others.any(_selectedAwards.contains);
  }

  bool _isEligibleForAwards(Map<String, dynamic> e) {
    final scratched = _isScratched(e);
    if (scratched) return false;

    final status = _effectiveStatusFor(e);

    if (status == 'No Show' ||
        _isDisqualifiedStatus(status) ||
        status == 'Unworthy of Award') {
      return false;
    }

    return true;
  }

  String _classSystemForEntry(Map<String, dynamic> e) {
    final breedLower = _breed(e).toLowerCase();
    return widget.breedClassSystems[breedLower] ?? 'four';
  }

  bool _breedUsesGroups() {
    if (_isFurOrWoolResultRow()) return false;

    if (widget.showsByGroup) return true;

    final groupName = _groupName(widget.entry);
    if (groupName.isNotEmpty && groupName != 'Fur / Wool') return true;

    return widget.classEntries.any((e) {
      if (_isFurOrWoolEntry(e)) return false;

      final usesGroupsRaw = e['uses_group_awards'];
      final usesGroups = usesGroupsRaw == true ||
          usesGroupsRaw.toString().trim().toLowerCase() == 'true' ||
          usesGroupsRaw.toString().trim().toLowerCase() == 't' ||
          usesGroupsRaw.toString().trim() == '1';

      return usesGroups;
    });
  }
  bool get _showsByVariety => widget.showsByVariety;

  List<String> get _visibleAwardCodes {
    if (_isFurOrWoolResultRow()) {
      return const <String>[];
    }

    if (_isCavyEntry(widget.entry)) {
      final awards = <String>[
        'BJV',
        'BIV',
        'BSV',
        'BJB',
        'BIB',
        'BSB',
        'BOV',
        'BOSV',
        'BOB',
        'BOSB',
      ];

      if (widget.finalAwardMode == 'bis_1ris_2ris') {
        awards.addAll(const ['BIS', '1RIS', '2RIS']);
      } else {
        awards.addAll(const ['BIS', 'RIS', 'HM']);
      }

      return awards;
    }

    final awards = <String>[];

    if (_breedUsesGroups()) {
      awards.addAll(const ['BOG', 'BOSG']);
    }

    if (_showsByVariety) {
      awards.addAll(const ['BOV', 'BOSV']);
    }

    awards.addAll(const ['BOB', 'BOSB']);

    if (_supportsBestAgeAwards(
      breedName: _breed(widget.entry),
      isCavy: _isCavyEntry(widget.entry),
    )) {
      awards.addAll(kBestAgeAwardCodes.where((award) {
        return _bestAgeAwardMatchesClass(
          award: award,
          className: (widget.entry['class_name'] ?? '').toString(),
          classSystem: _classSystemForEntry(widget.entry),
        );
      }));
    }

    if (widget.finalAwardMode == 'bis_ris') {
      awards.addAll(const ['Best In Show', 'Reserve In Show']);
    } else if (widget.finalAwardMode == 'bis_1ris_2ris') {
      awards.addAll(const ['Best In Show', '1RIS', '2RIS']);
    } else {
      awards.addAll(const ['Best 4-Class', 'Best 6-Class', 'Best In Show']);
    }

    return awards;
  }

  List<String> _placementOptions() {
    final current = (_placement ?? '').trim();
    final options = [...widget.availablePlacements];
    if (current.isNotEmpty && !options.contains(current)) {
      options.add(current);
    }
    options.sort((a, b) {
      final ai = int.tryParse(a) ?? 999;
      final bi = int.tryParse(b) ?? 999;
      return ai.compareTo(bi);
    });
    return options;
  }

  bool _hasAward(String award) => _selectedAwards.contains(_canonicalAwardCode(award));

  Map<String, dynamic>? _winnerForAwardInScope({
    required String award,
    required bool Function(Map<String, dynamic>) sameScope,
  }) {
    for (final e in widget.classEntries) {
      if (_entryId(e) == _entryId(widget.entry)) continue;
      if (!sameScope(e)) continue;
      final awards = _entryAwards(e);
      if (awards.contains(award)) return e;
    }
    return null;
  }

  bool _isOppositeSexOf(Map<String, dynamic>? other) {
    if (other == null) return true;
    final mySex = _sex(widget.entry);
    final otherSex = _sex(other);
    if (mySex.isEmpty || otherSex.isEmpty) return true;
    return mySex != otherSex;
  }

  bool _canUseAward(String award) {
    if (!_isEligibleForAwards(widget.entry)) return false;
    if (!_placedFirst(widget.entry)) return false;
    if (_sameRabbitAlreadyHasConflictingStageAward(award)) return false;

    final currentAwards = _selectedAwards;

    if (_isCavyEntry(widget.entry)) {
      switch (award) {
        case 'BJV':
          return (widget.entry['class_name'] ?? '')
              .toString()
              .toLowerCase()
              .contains('junior');

        case 'BIV':
          return (widget.entry['class_name'] ?? '')
              .toString()
              .toLowerCase()
              .contains('intermediate');

        case 'BSV':
          return (widget.entry['class_name'] ?? '')
              .toString()
              .toLowerCase()
              .contains('senior');

        case 'BJB':
          return currentAwards.contains('BJV');

        case 'BIB':
          return currentAwards.contains('BIV');

        case 'BSB':
          return currentAwards.contains('BSV');

        case 'BOV':
        case 'BOSV':
          return true;

        case 'BOB':
        case 'BOSB':
          return currentAwards.contains('BOV') ||
              currentAwards.contains('BOSV') ||
              currentAwards.contains('BJB') ||
              currentAwards.contains('BIB') ||
              currentAwards.contains('BSB');

        case 'BIS':
          return currentAwards.contains('BOB');

        case 'RIS':
          return widget.finalAwardMode != 'bis_1ris_2ris' &&
              currentAwards.contains('BOB') &&
              !currentAwards.contains('BIS');

        case '1RIS':
          return widget.finalAwardMode == 'bis_1ris_2ris' &&
              currentAwards.contains('BOB') &&
              !currentAwards.contains('BIS') &&
              !currentAwards.contains('2RIS');

        case '2RIS':
          return widget.finalAwardMode == 'bis_1ris_2ris' &&
              currentAwards.contains('BOB') &&
              !currentAwards.contains('BIS') &&
              !currentAwards.contains('1RIS');

        case 'HM':
          return widget.finalAwardMode != 'bis_1ris_2ris' &&
              currentAwards.contains('BOB') &&
              !currentAwards.contains('BIS') &&
              !currentAwards.contains('RIS');
      }

      return false;
    }

    switch (award) {
      case 'BOV':
      case 'BOSV':
        return _showsByVariety;

      case 'BOG':
      case 'BOSG':
        if (!_breedUsesGroups()) return false;

        // If this breed also uses variety awards, group awards should only
        // become available after the rabbit has already won at variety level.
        if (_showsByVariety) {
          return currentAwards.contains('BOV') || currentAwards.contains('BOSV');
        }
        return true;

      case 'BOB':
      case 'BOSB':
        if (_breedUsesGroups()) {
          return currentAwards.contains('BOG') || currentAwards.contains('BOSG');
        }
        if (_showsByVariety) {
          return currentAwards.contains('BOV') || currentAwards.contains('BOSV');
        }
        return true;

      case 'Best Junior':
      case 'Best Senior':
      case 'Best Intermediate':
        return _supportsBestAgeAwards(
              breedName: _breed(widget.entry),
              isCavy: _isCavyEntry(widget.entry),
            ) &&
            _bestAgeAwardMatchesClass(
              award: award,
              className: (widget.entry['class_name'] ?? '').toString(),
              classSystem: _classSystemForEntry(widget.entry),
            );

      case 'Best 4-Class':
        return _classSystemForEntry(widget.entry) == 'four' &&
            currentAwards.contains('BOB');

      case 'Best 6-Class':
        return _classSystemForEntry(widget.entry) == 'six' &&
            currentAwards.contains('BOB');

      case 'Best In Show':
        if (widget.finalAwardMode == 'four_six_bis') {
          return currentAwards.contains('Best 4-Class') ||
              currentAwards.contains('Best 6-Class');
        }
        return currentAwards.contains('BOB');

      case 'Reserve In Show':
        if (widget.finalAwardMode == 'bis_ris') {
          return currentAwards.contains('BOB') &&
              !currentAwards.contains('Best In Show');
        }
        return false;

      case '1RIS':
        if (widget.finalAwardMode == 'bis_1ris_2ris') {
          return currentAwards.contains('BOB') &&
              !currentAwards.contains('Best In Show') &&
              !currentAwards.contains('2RIS');
        }
        return false;

      case '2RIS':
        if (widget.finalAwardMode == 'bis_1ris_2ris') {
          return currentAwards.contains('BOB') &&
              !currentAwards.contains('Best In Show') &&
              !currentAwards.contains('1RIS');
        }
        return false;
    }

    return false;
  }

  String? _validateAwards() {
    if (!_isEligibleForAwards(widget.entry) && _selectedAwards.isNotEmpty) {
      return 'This rabbit cannot receive awards because it is scratched, disqualified, not shown, or unworthy of award.';
    }

    if (_selectedAwards.isNotEmpty && !_placedFirst(widget.entry)) {
      return _isCavyEntry(widget.entry)
          ? 'Only first-place cavies can receive awards.'
          : 'Only first-place rabbits can receive awards.';
    }

    bool sameVariety(Map<String, dynamic> e) =>
        _sectionId(e) == _sectionId(widget.entry) &&
        _breed(e).toLowerCase() == _breed(widget.entry).toLowerCase() &&
        _variety(e).toLowerCase() == _variety(widget.entry).toLowerCase();

    bool sameGroup(Map<String, dynamic> e) =>
        _sectionId(e) == _sectionId(widget.entry) &&
        _breed(e).toLowerCase() == _breed(widget.entry).toLowerCase() &&
        _groupName(e).toLowerCase() == _groupName(widget.entry).toLowerCase();

    bool sameBreed(Map<String, dynamic> e) =>
        _sectionId(e) == _sectionId(widget.entry) &&
        _breed(e).toLowerCase() == _breed(widget.entry).toLowerCase();

    bool sameSection(Map<String, dynamic> e) =>
        _sectionId(e) == _sectionId(widget.entry);

    if (_isCavyEntry(widget.entry)) {
      bool sameClassAge(Map<String, dynamic> e) =>
          sameVariety(e) &&
          (e['class_name'] ?? '').toString().trim().toLowerCase() ==
              (widget.entry['class_name'] ?? '').toString().trim().toLowerCase();

      for (final award in _selectedAwards) {
        final sameScope = switch (award) {
          'BJV' || 'BIV' || 'BSV' => sameClassAge,
          'BJB' || 'BIB' || 'BSB' => sameBreed,
          'BOV' || 'BOSV' => sameVariety,
          'BOB' || 'BOSB' => sameBreed,
          'BIS' || 'RIS' || 'HM' => sameSection,
          _ => sameSection,
        };

        final existing = _winnerForAwardInScope(
          award: award,
          sameScope: sameScope,
        );

        if (existing != null) {
          return '${cavyAwardLabels[award] ?? award} is already assigned.';
        }

        if (!_canUseAward(award)) {
          return '${cavyAwardLabels[award] ?? award} is not eligible for this cavy.';
        }
      }

      if (_hasAward('BOV')) {
        final bosv = _winnerForAwardInScope(
          award: 'BOSV',
          sameScope: sameVariety,
        );
        if (!_isOppositeSexOf(bosv)) {
          return 'BOV and BOSV must be opposite sex.';
        }
      }

      if (_hasAward('BOSV')) {
        final bov = _winnerForAwardInScope(
          award: 'BOV',
          sameScope: sameVariety,
        );
        if (!_isOppositeSexOf(bov)) {
          return 'BOV and BOSV must be opposite sex.';
        }
      }

      if (_hasAward('BOB')) {
        final bosb = _winnerForAwardInScope(
          award: 'BOSB',
          sameScope: sameBreed,
        );
        if (!_isOppositeSexOf(bosb)) {
          return 'BOB and BOSB must be opposite sex.';
        }
      }

      if (_hasAward('BOSB')) {
        final bob = _winnerForAwardInScope(
          award: 'BOB',
          sameScope: sameBreed,
        );
        if (!_isOppositeSexOf(bob)) {
          return 'BOB and BOSB must be opposite sex.';
        }
      }

      if (_hasAward('BIS') && (_hasAward('RIS') || _hasAward('HM'))) {
        return 'The same cavy cannot be BIS, RIS, or Honorable Mention.';
      }

      if (_hasAward('RIS') && _hasAward('HM')) {
        return 'The same cavy cannot be both RIS and Honorable Mention.';
      }

      return null;
    }

    // Same rabbit cannot hold both sides of a paired award stage.
    for (final award in _selectedAwards) {
      if (_sameRabbitAlreadyHasConflictingStageAward(award)) {
        return 'A rabbit can only hold one award in the same award stage.';
      }
    }

    if (_hasAward('BOV')) {
      final existing = _winnerForAwardInScope(
        award: 'BOV',
        sameScope: sameVariety,
      );
      if (existing != null) return 'BOV is already assigned for this variety.';
      final bosv = _winnerForAwardInScope(
        award: 'BOSV',
        sameScope: sameVariety,
      );
      if (!_isOppositeSexOf(bosv)) return 'BOV and BOSV must be opposite sex.';
    }

    if (_hasAward('BOSV')) {
      final existing = _winnerForAwardInScope(
        award: 'BOSV',
        sameScope: sameVariety,
      );
      if (existing != null) return 'BOSV is already assigned for this variety.';
      final bov = _winnerForAwardInScope(
        award: 'BOV',
        sameScope: sameVariety,
      );
      if (!_isOppositeSexOf(bov)) return 'BOV and BOSV must be opposite sex.';
    }

    if (_hasAward('BOG')) {
      final existing = _winnerForAwardInScope(
        award: 'BOG',
        sameScope: sameGroup,
      );
      if (existing != null) return 'BOG is already assigned for this group.';
      final bosg = _winnerForAwardInScope(
        award: 'BOSG',
        sameScope: sameGroup,
      );
      if (!_isOppositeSexOf(bosg)) return 'BOG and BOSG must be opposite sex.';
    }

    if (_hasAward('BOSG')) {
      final existing = _winnerForAwardInScope(
        award: 'BOSG',
        sameScope: sameGroup,
      );
      if (existing != null) return 'BOSG is already assigned for this group.';
      final bog = _winnerForAwardInScope(
        award: 'BOG',
        sameScope: sameGroup,
      );
      if (!_isOppositeSexOf(bog)) return 'BOG and BOSG must be opposite sex.';
    }

    if (_hasAward('BOB')) {
      final existing = _winnerForAwardInScope(
        award: 'BOB',
        sameScope: sameBreed,
      );
      if (existing != null) return 'BOB is already assigned for this breed.';
      final bosb = _winnerForAwardInScope(
        award: 'BOSB',
        sameScope: sameBreed,
      );
      if (!_isOppositeSexOf(bosb)) return 'BOB and BOSB must be opposite sex.';

      if (_breedUsesGroups()) {
        if (!(_hasAward('BOG') || _hasAward('BOSG'))) {
          return 'BOB can only be selected from BOG/BOSG winners for group breeds.';
        }
      } else if (_showsByVariety) {
        if (!(_hasAward('BOV') || _hasAward('BOSV'))) {
          return 'BOB can only be selected from BOV/BOSV winners for breeds with variety awards.';
        }
      }
    }

    if (_hasAward('BOSB')) {
      final existing = _winnerForAwardInScope(
        award: 'BOSB',
        sameScope: sameBreed,
      );
      if (existing != null) return 'BOSB is already assigned for this breed.';
      final bob = _winnerForAwardInScope(
        award: 'BOB',
        sameScope: sameBreed,
      );
      if (!_isOppositeSexOf(bob)) return 'BOB and BOSB must be opposite sex.';

      if (_breedUsesGroups()) {
        if (!(_hasAward('BOG') || _hasAward('BOSG'))) {
          return 'BOSB can only be selected from BOG/BOSG winners for group breeds.';
        }
      } else if (_showsByVariety) {
        if (!(_hasAward('BOV') || _hasAward('BOSV'))) {
          return 'BOSB can only be selected from BOV/BOSV winners for breeds with variety awards.';
        }
      }
    }

    for (final award in kBestAgeAwardCodes) {
      if (!_hasAward(award)) continue;

      final sameScope = _showsByVariety ? sameVariety : sameBreed;

      final existing = _winnerForAwardInScope(
        award: award,
        sameScope: sameScope,
      );

      if (existing != null) {
        return '$award is already assigned for this ${_showsByVariety ? 'variety' : 'breed'}.';
      }

      if (!_canUseAward(award)) {
        return '$award is only available to the correct first-place age class in eligible breeds.';
      }
    }

    if (_hasAward('Best 4-Class')) {
      final existing = _winnerForAwardInScope(
        award: 'Best 4-Class',
        sameScope: sameSection,
      );
      if (existing != null) {
        return 'Best 4-Class is already assigned in this section.';
      }
      if (!_canUseAward('Best 4-Class')) {
        return 'Best 4-Class requires a first-place BOB from a 4-class breed.';
      }
    }

    if (_hasAward('Best 6-Class')) {
      final existing = _winnerForAwardInScope(
        award: 'Best 6-Class',
        sameScope: sameSection,
      );
      if (existing != null) {
        return 'Best 6-Class is already assigned in this section.';
      }
      if (!_canUseAward('Best 6-Class')) {
        return 'Best 6-Class requires a first-place BOB from a 6-class breed.';
      }
    }

    if (_hasAward('Best In Show')) {
      final existing = _winnerForAwardInScope(
        award: 'Best In Show',
        sameScope: sameSection,
      );
      if (existing != null) return 'Best In Show is already assigned in this section.';
      if (!_canUseAward('Best In Show')) {
        return widget.finalAwardMode == 'four_six_bis'
            ? 'Best In Show must come from Best 4-Class or Best 6-Class.'
            : 'Best In Show must come from a first-place breed winner.';
      }
    }

    if (_hasAward('Reserve In Show')) {
      final existing = _winnerForAwardInScope(
        award: 'Reserve In Show',
        sameScope: sameSection,
      );
      if (existing != null) {
        return 'Reserve In Show is already assigned in this section.';
      }
      if (!_canUseAward('Reserve In Show')) {
        return 'Reserve In Show must come from a first-place breed winner and cannot also be BIS.';
      }
      if (_hasAward('Best In Show')) {
        return 'This rabbit cannot be both Best In Show and Reserve In Show.';
      }
    }

    return null;
  }

  String _awardDisabledReason(String award) {
    if (!_placedFirst(widget.entry)) {
      return _isCavyEntry(widget.entry)
          ? 'Only first-place cavies can receive awards.'
          : 'Only first-place rabbits can receive awards.';
    }

    if (_isCavyEntry(widget.entry)) {
      return '${cavyAwardLabels[award] ?? award} is not eligible right now.';
    }

    if (_sameRabbitAlreadyHasConflictingStageAward(award)) {
      return 'This rabbit already has the opposite award at this stage.';
    }

    switch (award) {
      case 'BOG':
      case 'BOSG':
        return _showsByVariety
            ? 'Requires a prior variety win, and only for breeds judged by group.'
            : 'Only for breeds judged by group.';
      case 'BOV':
      case 'BOSV':
        return 'Only for breeds with variety awards.';
      case 'BOB':
      case 'BOSB':
        return 'Requires BOV/BOSV or BOG/BOSG first.';
      case 'Best Junior':
        return 'Only first-place junior rabbits in eligible breeds can receive Best Junior.';
      case 'Best Senior':
        return 'Only first-place senior rabbits in eligible breeds can receive Best Senior.';
      case 'Best Intermediate':
        return 'Only first-place intermediate rabbits in eligible 6-class breeds can receive Best Intermediate.';
      case 'Best 4-Class':
        return 'Requires first-place BOB from a 4-class breed.';
      case 'Best 6-Class':
        return 'Requires first-place BOB from a 6-class breed.';
      case 'Best In Show':
        return widget.finalAwardMode == 'four_six_bis'
            ? 'Requires Best 4-Class or Best 6-Class.'
            : 'Requires first-place breed winner.';
      case 'Reserve In Show':
        return 'Only used in BIS/RIS mode and cannot be on the BIS rabbit.';
      default:
        return 'Not eligible right now.';
    }
  }

  String _writerNameFromUser(User user) {
    final meta = user.userMetadata ?? {};

    final displayName = (meta['display_name'] ?? '').toString().trim();
    final fullName = (meta['full_name'] ?? '').toString().trim();
    final name = (meta['name'] ?? '').toString().trim();
    final email = (user.email ?? '').trim();

    if (displayName.isNotEmpty) return displayName;
    if (fullName.isNotEmpty) return fullName;
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;

    return 'Signed-in Writer';
  }

  Future<void> _recordJudgingSessionEntry({
    required String entryId,
    required String? judgeId,
  }) async {
    if (!widget.isQrEntryMode) return;

    final normalizedJudgeId = (judgeId ?? '').trim();
    if (normalizedJudgeId.isEmpty) return;

      await supabase.rpc(
        'record_judging_session_entry',
        params: {
          'p_show_id': widget.showId,
          'p_judge_id': normalizedJudgeId,
          'p_entry_id': entryId,
          'p_table_number': null,
        },
      );
    }

  Future<void> _save({required bool goNext}) async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      if (!widget.isQrEntryMode) {
        await ShowLockService.assertShowUnlocked(widget.showId);
      }

      final entryId = _entryUuid;
      if (entryId.isEmpty) {
        throw Exception('Entry ID is missing.');
      }

      final user = supabase.auth.currentUser;
      final session = supabase.auth.currentSession;

      final writerName = widget.isQrEntryMode
          ? (widget.writerName ?? '').trim()
          : (user == null ? '' : _writerNameFromUser(user));

      final writerPhone = (widget.writerPhone ?? '').trim();


      if (widget.isQrEntryMode) {
        if (writerName.isEmpty || writerPhone.isEmpty) {
          throw Exception('Writer name and phone number are required.');
        }
      } else {
        if (user == null || session == null) {
          throw Exception('Please sign in before saving results.');
        }
      }

      final scratched = _isScratched(widget.entry);
      final effectiveStatus = (_resultStatus ?? 'Shown').trim();
      final shouldClearPlacement = scratched || effectiveStatus != 'Shown';

      final awardError = widget.isFurOrWoolClass ? null : _validateAwards();
      if (awardError != null) {
        setState(() {
          _saving = false;
          _msg = awardError;
        });
        return;
      }

      final normalizedPlacement = shouldClearPlacement
          ? ''
          : (_placement ?? '').trim();

      String? normalizedJudgeId;
      if (_judgeId != null && _judgeId!.trim().isNotEmpty) {
        final rawJudgeId = _judgeId!.trim();

        for (final j in widget.judges) {
          final savedJudgeId = (j['id'] ?? '').toString().trim();
          final masterJudgeId = (j['judge_id'] ?? '').toString().trim();
          final assignmentId = (j['assignment_id'] ?? '').toString().trim();

          if (rawJudgeId == savedJudgeId ||
              rawJudgeId == masterJudgeId ||
              rawJudgeId == assignmentId) {
            normalizedJudgeId = savedJudgeId;
            break;
          }
        }

        normalizedJudgeId ??= rawJudgeId;
      }

      final normalizedDqReason = _isDisqualifiedStatus(effectiveStatus)
          ? _dqReasonFromStatus(effectiveStatus)
          : null;

      final now = DateTime.now().toUtc().toIso8601String();

      final isFurOrWoolResult = _isFurOrWoolResultRow();
      final awardsToSave = isFurOrWoolResult
          ? <String>[]
          : (_selectedAwards
              .map((award) => _canonicalAwardCode(award))
              .where((award) => award.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort());

      if (isFurOrWoolResult) {
        final updated = await supabase.rpc(
          'save_results_entry',
          params: {
            'p_show_id': widget.showId,
            'p_entry_id': entryId,
            'p_placement': normalizedPlacement,
            'p_result_status': effectiveStatus,
            'p_disqualified_reason': normalizedDqReason,
            'p_is_shown': effectiveStatus != 'No Show',
            'p_is_disqualified': _isDisqualifiedStatus(effectiveStatus),
            'p_judged_by_show_judge_id': normalizedJudgeId,
            'p_result_entered_by_name':
                writerName.isEmpty ? 'Signed-in Writer' : writerName,
            'p_result_entered_by_phone':
                widget.isQrEntryMode ? writerPhone : null,
            'p_awards': awardsToSave,
            'p_is_qr_entry_mode': widget.isQrEntryMode,
          },
        );

        if (updated == null) {
          throw Exception('Save returned no result.');
        }

        await _recordJudgingSessionEntry(
          entryId: entryId,
          judgeId: normalizedJudgeId,
        );

        widget.entry['placement'] = normalizedPlacement.isEmpty ? null : normalizedPlacement;
        widget.entry['result_status'] = effectiveStatus;
        widget.entry['disqualified_reason'] = normalizedDqReason;
        widget.entry['is_shown'] = effectiveStatus != 'No Show';
        widget.entry['is_disqualified'] = _isDisqualifiedStatus(effectiveStatus);
        widget.entry['judged_by_show_judge_id'] = normalizedJudgeId;
        widget.entry['result_entered_by_name'] =
            writerName.isEmpty ? 'Signed-in Writer' : writerName;
        widget.entry['result_entered_by_phone'] =
            widget.isQrEntryMode ? writerPhone : null;
        widget.entry['result_entered_at'] = now;
        widget.entry['updated_at'] = now;
        widget.entry['_awards'] = awardsToSave;
      } else {
        

      final updated = await supabase.rpc(
        'save_results_entry',
        params: {
          'p_show_id': widget.showId,
          'p_entry_id': entryId,
          'p_placement': normalizedPlacement,
          'p_result_status': effectiveStatus,
          'p_disqualified_reason': normalizedDqReason,
          'p_is_shown': effectiveStatus != 'No Show',
          'p_is_disqualified': _isDisqualifiedStatus(effectiveStatus),
          'p_judged_by_show_judge_id': normalizedJudgeId,
          'p_result_entered_by_name':
              writerName.isEmpty ? 'Signed-in Writer' : writerName,
          'p_result_entered_by_phone':
              widget.isQrEntryMode ? writerPhone : null,
          'p_awards': widget.isFurOrWoolClass ? <String>[] : awardsToSave,
          'p_is_qr_entry_mode': widget.isQrEntryMode,
        },
      );

      if (updated == null) {
        throw Exception('Save returned no result.');
      }

      await _recordJudgingSessionEntry(
        entryId: entryId,
        judgeId: normalizedJudgeId,
      );

      // Local update (same for all entries)
      widget.entry['placement'] = normalizedPlacement.isEmpty ? null : normalizedPlacement;
      widget.entry['result_status'] = effectiveStatus;
      widget.entry['disqualified_reason'] = normalizedDqReason;
      widget.entry['is_shown'] = effectiveStatus != 'No Show';
      widget.entry['is_disqualified'] = _isDisqualifiedStatus(effectiveStatus);
      widget.entry['judged_by_show_judge_id'] = normalizedJudgeId;
      widget.entry['result_entered_by_name'] =
          writerName.isEmpty ? 'Signed-in Writer' : writerName;
      widget.entry['result_entered_by_phone'] =
          widget.isQrEntryMode ? writerPhone : null;
      widget.entry['result_entered_at'] = now;
      widget.entry['updated_at'] = now;
      widget.entry['_awards'] =
          widget.isFurOrWoolClass ? <String>[] : awardsToSave;
      }

      Navigator.pop(
        context,
        ResultsEntryOutcome(
          goNext: goNext,
          classComplete: goNext,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final coopNumber =
        (widget.entry['coop_number'] ?? '').toString().trim();
    final animalName = (widget.entry['animal_name'] ?? '').toString().trim();
    final tattoo = (widget.entry['tattoo'] ?? '').toString().trim();
    final breed = (widget.entry['breed'] ?? '').toString();
    final groupName = (widget.entry['group_name'] ?? '').toString();
    final variety = (widget.entry['variety'] ?? '').toString();
    final sex = (widget.entry['sex'] ?? '').toString();
    final className = (widget.entry['class_name'] ?? '').toString();
    final scratched = _isScratched(widget.entry);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    var placementOptions = _placementOptions();

    final effectiveResultStatus = (_resultStatus ?? 'Shown').trim();
    final canPlace = !scratched && effectiveResultStatus == 'Shown';

    if (placementOptions.isEmpty && canPlace) {
      final count = widget.shownCount <= 0 ? widget.totalCount : widget.shownCount;
      placementOptions = List<String>.generate(count, (i) => '${i + 1}');
    }

    final canAward =
        !scratched && effectiveResultStatus == 'Shown' && (_placement ?? '').trim() == '1';

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: bottomInset + 16,
      ),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Record Results (${widget.currentIndex + 1} of ${widget.totalCount})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (_msg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withValues(alpha: .20)),
                  ),
                  child: Text(
                    _msg!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Text(
                [
                  breed,
                  if (groupName.trim().isNotEmpty) groupName,
                  variety,
                  sex,
                  className,
                ].where((x) => x.trim().isNotEmpty).join(' • '),
              ),
              const SizedBox(height: 4),
              if (coopNumber.isNotEmpty)
                Text(
                  'Coop #: $coopNumber',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              Text(
                animalName.isNotEmpty && tattoo.isNotEmpty
                    ? '$animalName • Ear #: $tattoo'
                    : animalName.isNotEmpty
                        ? animalName
                        : 'Ear #: ${tattoo.isEmpty ? '(No ear #)' : tattoo}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (scratched) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.withValues(alpha: .22)),
                  ),
                  child: const Text(
                    'This animal is scratched. Placement and awards will be cleared.',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _judgeId,
                decoration: const InputDecoration(
                  labelText: 'Judge',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('(Not set)'),
                  ),
                  ...widget.judges.map(
                    (j) => DropdownMenuItem<String>(
                      value: (j['id'] ?? '').toString(),
                      child: Text((j['name'] ?? '').toString()),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (v) {
                        setState(() {
                          _judgeId = (v == null || v.isEmpty) ? null : v;
                        });
                      },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _resultStatus,
                decoration: const InputDecoration(
                  labelText: 'Result Status',
                ),
                items: kResultStatuses
                    .map(
                      (status) => DropdownMenuItem<String>(
                        value: status,
                        child: Text(status),
                      ),
                    )
                    .toList(),
                onChanged: scratched || _saving || AppSession.isSupportMode
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _resultStatus = value;

                          if (_resultStatus != 'Shown') {
                            _placement = null;
                          }

                          if (_resultStatus != 'Shown') {
                            _selectedAwards.clear();
                          }
                        });
                      },
              ),
              const SizedBox(height: 10),
              if (canPlace)
                DropdownButtonFormField<String>(
                  initialValue: (_placement != null && placementOptions.contains(_placement))
                      ? _placement
                      : '',
                  decoration: const InputDecoration(
                    labelText: 'Placement',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('(No placing)'),
                    ),
                    ...placementOptions.map(
                      (p) => DropdownMenuItem<String>(
                        value: p,
                        child: Text(p),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() {
                            _placement = (v == null || v.trim().isEmpty)
                                ? null
                                : v.trim();

                            if ((_placement ?? '').trim() != '1') {
                              _selectedAwards.clear();
                            }
                          });
                        },
                ),
              if (canPlace) const SizedBox(height: 16),
              Text(
                'Awards',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ..._visibleAwardCodes.map((award) {
                final awardCode = _canonicalAwardCode(award);
                final allowed = _canUseAward(award);
                final checked = _selectedAwards.contains(awardCode);

                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  title: Text(_awardDisplayLabel(award, widget.entry)),
                  subtitle: !allowed && canAward
                      ? Text(_awardDisabledReason(award))
                      : null,
                  onChanged: (!canAward || _saving || AppSession.isSupportMode || !allowed)
                      ? null
                      : (v) {
                          setState(() {
                            final pair = _pairedAwardsFor(award);

                            if (v == true) {
                              for (final other in pair) {
                                final otherCode = _canonicalAwardCode(other);
                                if (otherCode != awardCode) {
                                  _selectedAwards.remove(otherCode);
                                }
                              }
                              _selectedAwards.add(awardCode);
                            } else {
                              _selectedAwards.remove(awardCode);
                            }
                          });
                        },
                );
              }),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(goNext: false),
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A623),
                      ),
                      onPressed: _saving ? null : () => _save(goNext: true),
                      child: const Text('Save & Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValidationIssue {
  final String code;
  final String title;
  final String message;

  final Map<String, dynamic> entry;
  final Map<String, dynamic>? conflictsWith;

  final String breed;
  final String species;
  final String? groupName;
  final String? variety;
  final String classSexLabel;

  const _ValidationIssue({
    required this.code,
    required this.title,
    required this.message,
    required this.entry,
    required this.conflictsWith,
    required this.breed,
    required this.species,
    required this.groupName,
    required this.variety,
    required this.classSexLabel,
  });
}
