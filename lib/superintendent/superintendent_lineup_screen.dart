// lib/superintendent/superintendent_lineup_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

final supabase = Supabase.instance.client;

class SuperintendentLineupScreen extends StatefulWidget {
  const SuperintendentLineupScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  final String showId;
  final String showName;

  @override
  State<SuperintendentLineupScreen> createState() =>
      _SuperintendentLineupScreenState();
}

class _SuperintendentLineupScreenState extends State<SuperintendentLineupScreen> {
  late Future<_LineupData> _future;
  int _extraTableCount = 0;
  bool _isAutoFilling = false;
  bool _isSyncingEntries = false;
  bool _isSavingPublishedState = false;
  String _addBreedSortMode = 'letter';
  String? _addBreedShowLetter;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadData();
    });
    await _future;
  }

  Future<void> _syncLineupToEntries() async {
    try {
      await supabase.rpc(
        'apply_lineup_to_entries',
        params: {'p_show_id': widget.showId},
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Line-up saved, but entry judge sync failed: $error')),
      );
    }
  }

  Future<void> _manualSyncLineupToEntries() async {
    if (_isSyncingEntries) return;

    setState(() => _isSyncingEntries = true);
    await _syncLineupToEntries();

    if (!mounted) return;
    await _refresh();

    if (!mounted) return;
    setState(() => _isSyncingEntries = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Judges synced to entries.')),
    );
  }

  Future<bool> _confirmPublishWithIssues(_LineupData data) async {
    final conflictCount = _lineupConflictCount(data.assignments);
    if (conflictCount <= 0) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish judge order?'),
        content: Text(
          'This line-up still has $conflictCount item${conflictCount == 1 ? '' : 's'} needing attention. Exhibitors will be able to see the published judge order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish Anyway'),
          ),
        ],
      ),
    );

    return result == true;
  }

  int _lineupConflictCount(List<Map<String, dynamic>> assignments) {
    var count = 0;
    for (final row in assignments) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      if (isJudgeChange) continue;

      final hasDuplicate = row['duplicate_judge_breed'] == true;
      final hasOverride = (row['override_reason'] ?? row['notes'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;

      if (hasDuplicate && !hasOverride) count += 1;
    }
    return count;
  }

  Future<void> _setJudgeOrderPublished(
    _LineupData data,
    bool value,
  ) async {
    if (_isSavingPublishedState) return;

    if (value) {
      final confirmed = await _confirmPublishWithIssues(data);
      if (!confirmed) return;
    }

    setState(() => _isSavingPublishedState = true);

    try {
      await supabase
          .from('shows')
          .update({
            'superintendent_judge_order_published': value,
            'superintendent_judge_order_published_at':
                value ? DateTime.now().toUtc().toIso8601String() : null,
            'superintendent_judge_order_published_by':
                value ? supabase.auth.currentUser?.id : null,
          })
          .eq('id', widget.showId);

      if (!mounted) return;

      setState(() {
        _isSavingPublishedState = false;
        _future = _loadData();
      });
      await _future;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Judge order published for exhibitors.'
                : 'Judge order hidden from exhibitors.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingPublishedState = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish update failed: $error')),
      );
    }
  }

  Future<_LineupData> _loadData() async {
    // Load the RPCs sequentially to avoid type issues
    final assignments = await supabase.rpc(
      'get_show_judging_lineup',
      params: {'p_show_id': widget.showId},
    );

    final judges = await supabase.rpc(
      'get_show_lineup_judges',
      params: {'p_show_id': widget.showId},
    );

    final breedCounts = await supabase.rpc(
      'get_show_lineup_breed_counts',
      params: {'p_show_id': widget.showId},
    );

    final workloads = await supabase.rpc(
      'get_show_judge_daily_workload',
      params: {'p_show_id': widget.showId},
    );

    final showRow = await supabase
        .from('shows')
        .select(
          'superintendent_judge_order_published, superintendent_judge_order_published_at, superintendent_judge_order_published_by',
        )
        .eq('id', widget.showId)
        .maybeSingle();

    final currentUserId = supabase.auth.currentUser?.id;
    final preferenceRows = currentUserId == null
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await supabase
                .from('show_superintendent_user_preferences')
                .select()
                .eq('user_id', currentUserId)
                .limit(1) as List,
          );

    final sections = await supabase
        .from('show_sections')
        .select('id, kind, letter, display_name')
        .eq('show_id', widget.showId);

    final assignmentRows = List<Map<String, dynamic>>.from(assignments as List);
    final judgeRows = List<Map<String, dynamic>>.from(judges as List);
    final breedRows = List<Map<String, dynamic>>.from(breedCounts as List);
    final workloadRows = List<Map<String, dynamic>>.from(workloads as List);

    final sectionRows = List<Map<String, dynamic>>.from(sections as List);
    final sectionById = <String, Map<String, dynamic>>{
      for (final section in sectionRows) section['id'].toString(): section,
    };

    String normalizedSectionKind(dynamic value) {
      final raw = (value ?? '').toString().trim().toLowerCase();
      if (raw == 'open') return 'open';
      if (raw == 'youth') return 'youth';
      if (raw.contains('open')) return 'open';
      if (raw.contains('youth')) return 'youth';
      return raw;
    }

    String? inferSectionIdForAssignment(Map<String, dynamic> row) {
      final current = (row['section_id'] ?? '').toString().trim();
      if (current.isNotEmpty) return current;

      final letter = (row['show_letter'] ??
              row['letter'] ??
              row['section_letter'] ??
              row['showLetter'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();

      final kind = normalizedSectionKind(
        row['scope'] ??
            row['section_kind'] ??
            row['kind'] ??
            row['breed_scope'] ??
            row['section_label'] ??
            row['section_name'],
      );

      final matches = sectionRows.where((section) {
        final sectionLetter = (section['letter'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final sectionKind = normalizedSectionKind(section['kind']);

        final letterMatches = letter.isEmpty || sectionLetter == letter;
        final kindMatches = kind.isEmpty || sectionKind == kind;

        return letterMatches && kindMatches;
      }).toList();

      if (matches.length == 1) {
        return (matches.first['id'] ?? '').toString().trim();
      }

      return null;
    }

    final sectionBackfills = <Map<String, String>>[];

    for (final assignment in assignmentRows) {
      final assignmentId = (assignment['id'] ?? '').toString().trim();
      final existingSectionId = (assignment['section_id'] ?? '').toString().trim();
      final inferredSectionId = inferSectionIdForAssignment(assignment);

      if (existingSectionId.isEmpty &&
          inferredSectionId != null &&
          inferredSectionId.isNotEmpty) {
        assignment['section_id'] = inferredSectionId;

        if (assignmentId.isNotEmpty &&
            (assignment['breed_id'] ?? '').toString() != '__judge_change__') {
          sectionBackfills.add({
            'id': assignmentId,
            'section_id': inferredSectionId,
          });
        }
      }
    }

    for (final backfill in sectionBackfills) {
      try {
        await supabase
            .from('show_judging_assignments')
            .update({'section_id': backfill['section_id']})
            .eq('id', backfill['id']!);
      } catch (error) {
        debugPrint('Unable to backfill judging assignment section_id: $error');
      }
    }

    void applySectionMetadata(Map<String, dynamic> row) {
      final sectionId = row['section_id']?.toString();
      if (sectionId == null || sectionId.isEmpty) return;

      final section = sectionById[sectionId];
      if (section == null) return;

      row['section_kind'] ??= section['kind'];
      row['kind'] ??= section['kind'];
      row['letter'] ??= section['letter'];
      row['section_letter'] ??= section['letter'];
      row['show_letter'] ??= section['letter'];
      row['section_label'] ??= section['display_name'];
      row['section_name'] ??= section['display_name'];
    }

    for (final row in assignmentRows) {
      applySectionMetadata(row);
    }

    for (final row in breedRows) {
      applySectionMetadata(row);
    }

    for (final assignment in assignmentRows) {
      final breedId = (assignment['breed_id'] ?? '').toString();
      if (breedId == '__judge_change__') {
        assignment['is_judge_change'] = true;
      }

      final judgeId = assignment['judge_id']?.toString();
      final hasJudgeName =
          (assignment['judge_name'] ?? '').toString().trim().isNotEmpty;

      if (judgeId != null && judgeId.isNotEmpty && !hasJudgeName) {
        final matchingJudge = judgeRows.cast<Map<String, dynamic>?>().firstWhere(
              (judge) => judge?['judge_id']?.toString() == judgeId,
              orElse: () => null,
            );

        if (matchingJudge != null) {
          assignment['judge_name'] = matchingJudge['judge_name'];
        }
      }
    }

    for (final assignment in assignmentRows) {
      if (assignment['is_judge_change'] == true) continue;
      if ((assignment['species'] ?? '').toString().isNotEmpty) continue;

      final matchingBreed = breedRows.cast<Map<String, dynamic>?>().firstWhere(
        (breed) {
          if (breed == null) return false;

          final sameSection = (breed['section_id'] ?? '').toString() ==
              (assignment['section_id'] ?? '').toString();
          final sameBreed = (breed['breed'] ?? '').toString().toLowerCase() ==
              (assignment['breed_id'] ?? '').toString().toLowerCase();
          final assignmentVariety =
              (assignment['variety_key'] ?? '').toString().toLowerCase();
          final breedVariety = (breed['variety'] ?? '').toString().toLowerCase();
          final sameVariety = assignmentVariety.isEmpty ||
              breedVariety == assignmentVariety;

          return sameSection && sameBreed && sameVariety;
        },
        orElse: () => null,
      );

      if (matchingBreed != null) {
        void fillIfBlank(String key, dynamic value) {
          final current = assignment[key]?.toString().trim() ?? '';
          if (current.isEmpty && value != null) {
            assignment[key] = value;
          }
        }

        fillIfBlank('species', matchingBreed['species']);
        fillIfBlank('show_letter', matchingBreed['show_letter']);
        fillIfBlank('letter', matchingBreed['letter']);
        fillIfBlank('section_letter', matchingBreed['section_letter']);
        fillIfBlank('scope', matchingBreed['scope']);
        fillIfBlank('section_kind', matchingBreed['section_kind']);
        fillIfBlank('kind', matchingBreed['kind']);
      }
    }

    return _LineupData(
      assignments: assignmentRows,
      judges: judgeRows,
      breedCounts: breedRows,
      workloads: workloadRows,
      userPreferences: preferenceRows.isEmpty
          ? const <String, dynamic>{}
          : preferenceRows.first,
      judgeOrderPublished:
          (showRow?['superintendent_judge_order_published'] == true),
      judgeOrderPublishedAt:
          showRow?['superintendent_judge_order_published_at']?.toString(),
      judgeOrderPublishedBy:
          showRow?['superintendent_judge_order_published_by']?.toString(),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByTable(
    List<Map<String, dynamic>> assignments,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final row in assignments) {
      final table = (row['table_number'] ?? 'Unassigned').toString();
      grouped.putIfAbsent(table, () => <Map<String, dynamic>>[]).add(row);
    }

    for (final rows in grouped.values) {
      rows.sort((a, b) {
        final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      });

      int? currentJudgeRowIndex;
      String? currentJudgeName;
      String? currentJudgeId;

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final isJudgeChange = row['is_judge_change'] == true ||
            (row['breed_id'] ?? '').toString() == '__judge_change__';

        if (isJudgeChange) {
          currentJudgeRowIndex = i;
          currentJudgeName = (row['judge_name'] ?? 'Judge not set').toString();
          currentJudgeId = row['judge_id']?.toString();
          row['effective_judge_name'] = currentJudgeName;
          row['effective_judge_id'] = currentJudgeId;
          row['block_head_count'] = 0;
          continue;
        }

        row['effective_judge_name'] = currentJudgeName ??
            (row['judge_name'] ?? 'Judge not set').toString();
        row['effective_judge_id'] = currentJudgeId ?? row['judge_id']?.toString();

        if (currentJudgeRowIndex != null) {
          final actual = (row['entry_count_actual'] as num?)?.toInt();
          final estimated = (row['entry_count_estimated'] as num?)?.toInt();
          final count = actual ?? estimated ?? 0;
          rows[currentJudgeRowIndex]['block_head_count'] =
              ((rows[currentJudgeRowIndex]['block_head_count'] as num?)?.toInt() ?? 0) + count;
        }
      }
    }

    // Replace each judge row's local block count with the judge's running total
    // across the entire line-up. This lets the total follow the judge if they
    // are added to another table.
    final runningHeadByJudgeId = <String, int>{};

    for (final rows in grouped.values) {
      for (final row in rows) {
        final isJudgeChange = row['is_judge_change'] == true ||
            (row['breed_id'] ?? '').toString() == '__judge_change__';
        if (isJudgeChange) continue;

        final judgeId = (row['effective_judge_id'] ?? row['judge_id'] ?? '')
            .toString();
        if (judgeId.isEmpty) continue;

        final actual = (row['entry_count_actual'] as num?)?.toInt();
        final estimated = (row['entry_count_estimated'] as num?)?.toInt();
        final count = actual ?? estimated ?? 0;

        runningHeadByJudgeId[judgeId] =
            (runningHeadByJudgeId[judgeId] ?? 0) + count;
      }
    }

    final activeJudgeRowByJudgeId = <String, Map<String, dynamic>>{};

    for (final rows in grouped.values) {
      for (final row in rows) {
        final isJudgeChange = row['is_judge_change'] == true ||
            (row['breed_id'] ?? '').toString() == '__judge_change__';
        if (!isJudgeChange) continue;

        final judgeId = (row['effective_judge_id'] ?? row['judge_id'] ?? '')
            .toString();
        if (judgeId.isEmpty) continue;

        row['block_head_count'] = 0;

        final existing = activeJudgeRowByJudgeId[judgeId];
        if (existing == null) {
          activeJudgeRowByJudgeId[judgeId] = row;
          continue;
        }

        final existingCreated = DateTime.tryParse(
              (existing['created_at'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final rowCreated = DateTime.tryParse(
              (row['created_at'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        if (rowCreated.isAfter(existingCreated)) {
          activeJudgeRowByJudgeId[judgeId] = row;
        }
      }
    }

    for (final entry in activeJudgeRowByJudgeId.entries) {
      entry.value['block_head_count'] = runningHeadByJudgeId[entry.key] ?? 0;
    }

    // --- BEGIN: Duplicate judge/breed/scope detection across show letters ---
    final judgeBreedLetters = <String, Set<String>>{};

    for (final rows in grouped.values) {
      for (final row in rows) {
        final isJudgeChange = row['is_judge_change'] == true ||
            (row['breed_id'] ?? '').toString() == '__judge_change__';
        if (isJudgeChange) continue;

        final judgeId = (row['effective_judge_id'] ?? row['judge_id'] ?? '').toString();
        final breed = (row['breed_id'] ?? '').toString().trim().toLowerCase();
        final scope = (row['scope'] ?? row['section_kind'] ?? row['kind'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final letter = (row['show_letter'] ?? row['letter'] ?? row['section_letter'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (judgeId.isEmpty || breed.isEmpty || scope.isEmpty || letter.isEmpty) continue;

        final key = '$judgeId|$breed|$scope';
        judgeBreedLetters.putIfAbsent(key, () => <String>{}).add(letter);
      }
    }

    for (final rows in grouped.values) {
      for (final row in rows) {
        final isJudgeChange = row['is_judge_change'] == true ||
            (row['breed_id'] ?? '').toString() == '__judge_change__';
        if (isJudgeChange) continue;

        final judgeId = (row['effective_judge_id'] ?? row['judge_id'] ?? '').toString();
        final breed = (row['breed_id'] ?? '').toString().trim().toLowerCase();
        final scope = (row['scope'] ?? row['section_kind'] ?? row['kind'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final letter = (row['show_letter'] ?? row['letter'] ?? row['section_letter'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (judgeId.isEmpty || breed.isEmpty || scope.isEmpty || letter.isEmpty) continue;

        final key = '$judgeId|$breed|$scope';
        row['duplicate_judge_breed'] = (judgeBreedLetters[key]?.length ?? 0) > 1;
      }
    }
    // --- END: Duplicate judge/breed/scope detection across show letters ---

    return grouped;
  }

  int _nextSortOrderForTable(
    String tableNumber,
    Map<String, List<Map<String, dynamic>>> grouped,
  ) {
    final rows = grouped[tableNumber] ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) return 0;

    final maxSort = rows
        .map((row) => (row['sort_order'] as num?)?.toInt() ?? 0)
        .fold<int>(0, (max, value) => value > max ? value : max);

    return maxSort + 1;
  }

  Future<void> _openAddJudgeSheet(
    _LineupData data, {
    required String tableNumber,
    required int sortOrder,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Material(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _AddJudgeChangeSheet(
              showId: widget.showId,
              judges: data.judges,
              tableNumber: tableNumber,
              sortOrder: sortOrder,
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      await _syncLineupToEntries();
      await _refresh();
    }
  }

  List<String> _tableNumbersForData(
    _LineupData data,
    Map<String, List<Map<String, dynamic>>> grouped,
  ) {
    final defaultCount = data.judges.isEmpty ? 1 : data.judges.length;
    final tableNumbers = <String>[
      for (var i = 1; i <= defaultCount + _extraTableCount; i++) '$i',
    ];

    for (final existing in grouped.keys) {
      if (!tableNumbers.contains(existing)) {
        tableNumbers.add(existing);
      }
    }

    tableNumbers.sort((a, b) {
      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return a.compareTo(b);
    });

    return tableNumbers;
  }

  void _addTable() {
    setState(() {
      _extraTableCount += 1;
    });
  }

  Future<void> _openAddSheet(
    _LineupData data, {
    required String tableNumber,
    required int sortOrder,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Material(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: _AddAssignmentSheet(
              showId: widget.showId,
              judges: data.judges,
              breedCounts: data.breedCounts,
              assignedRows: data.assignments,
              userPreferences: data.userPreferences,
              tableNumber: tableNumber,
              sortOrder: sortOrder,
              initialSortMode: _addBreedSortMode,
              initialShowLetter: _addBreedShowLetter,
              onSortModeChanged: (value) {
                _addBreedSortMode = value;
              },
              onShowLetterChanged: (value) {
                _addBreedShowLetter = value;
              },
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      await _syncLineupToEntries();
      await _refresh();
    }
  }

  Future<void> _deleteAssignment(String assignmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from line-up?'),
        content: const Text('This will remove this breed from the judging line-up.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await supabase
        .from('show_judging_assignments')
        .delete()
        .eq('id', assignmentId);

    await _syncLineupToEntries();
    await _refresh();
  }

  Future<void> _reorderAssignments(
    List<Map<String, dynamic>> assignments,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;

    final reordered = List<Map<String, dynamic>>.from(assignments);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    for (var i = 0; i < reordered.length; i++) {
      final id = reordered[i]['id']?.toString();
      if (id == null || id.isEmpty) continue;

      await supabase
          .from('show_judging_assignments')
          .update({'sort_order': i})
          .eq('id', id);
    }

    await _syncLineupToEntries();
    await _refresh();
  }

  Future<void> _moveAssignmentToTable(
    String assignmentId,
    String tableNumber,
    int sortOrder,
  ) async {
    if (assignmentId.isEmpty) return;

    await supabase
        .from('show_judging_assignments')
        .update({
          'table_number': tableNumber,
          'sort_order': sortOrder,
        })
        .eq('id', assignmentId);

    await _syncLineupToEntries();
    await _refresh();
  }

  // --- BEGIN: Auto Fill Helpers ---
  String _scopeLabelForAutoRow(Map<String, dynamic> row) {
    final raw = (row['scope'] ??
            row['section_scope'] ??
            row['section_kind'] ??
            row['kind'] ??
            row['breed_scope'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();

    if (raw == 'open') return 'Open';
    if (raw == 'youth') return 'Youth';

    final label = (row['section_label'] ?? row['section_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (label.contains('youth')) return 'Youth';
    if (label.contains('open')) return 'Open';

    return '';
  }

  String _showLetterForAutoRow(Map<String, dynamic> row) {
    return (row['show_letter'] ??
            row['letter'] ??
            row['section_letter'] ??
            row['showLetter'] ??
            '')
        .toString()
        .trim();
  }

  String _judgeNameFromLineupJudge(Map<String, dynamic> judge) {
    return (judge['judge_name'] ??
            judge['display_name'] ??
            judge['name'] ??
            'Unknown Judge')
        .toString();
  }

  List<Map<String, dynamic>> _autoBreedOptions(_LineupData data) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in data.breedCounts) {
      final showLetter = _showLetterForAutoRow(row);
      final scope = _scopeLabelForAutoRow(row);
      final breed = (row['breed'] ?? '').toString().trim();
      if (showLetter.isEmpty || scope.isEmpty || breed.isEmpty) continue;

      final key = '$showLetter|$scope|$breed'.toLowerCase();
      final count = (row['entry_count'] as num?)?.toInt() ?? 0;

      grouped.putIfAbsent(
        key,
        () => <String, dynamic>{
          'section_id': row['section_id'],
          'show_letter': showLetter,
          'scope': scope,
          'breed': breed,
          'variety': null,
          'species': row['species'],
          'entry_count': 0,
        },
      );

      grouped[key]!['entry_count'] =
          ((grouped[key]!['entry_count'] as num?)?.toInt() ?? 0) + count;
    }

    final rows = grouped.values.toList();
    final openYouthMode =
        (data.userPreferences['open_youth_mode'] ?? 'together').toString();
    final showOrder =
        (data.userPreferences['show_order'] ?? 'open_first').toString();
    final pairOpenYouth = openYouthMode == 'together';

    int scopeRank(String scope) {
      final normalized = scope.toLowerCase();
      if (showOrder == 'youth_first') {
        if (normalized == 'youth') return 0;
        if (normalized == 'open') return 1;
      } else {
        if (normalized == 'open') return 0;
        if (normalized == 'youth') return 1;
      }
      return 2;
    }

    final breedTotalsByLetter = <String, int>{};
    for (final row in rows) {
      final letter = (row['show_letter'] ?? '').toString();
      final breed = (row['breed'] ?? '').toString();
      final key = '$letter|$breed'.toLowerCase();
      breedTotalsByLetter[key] =
          (breedTotalsByLetter[key] ?? 0) +
              ((row['entry_count'] as num?)?.toInt() ?? 0);
    }

    rows.sort((a, b) {
      final aLetter = (a['show_letter'] ?? '').toString();
      final bLetter = (b['show_letter'] ?? '').toString();
      final letterCompare = aLetter.compareTo(bLetter);
      if (letterCompare != 0) return letterCompare;

      final aBreed = (a['breed'] ?? '').toString();
      final bBreed = (b['breed'] ?? '').toString();
      final aScope = (a['scope'] ?? '').toString();
      final bScope = (b['scope'] ?? '').toString();
      final aCount = (a['entry_count'] as num?)?.toInt() ?? 0;
      final bCount = (b['entry_count'] as num?)?.toInt() ?? 0;

      if (pairOpenYouth) {
        // Keep Open and Youth for the same Show Letter + Breed adjacent.
        // Larger combined breeds still come first within the show letter.
        final aTotal =
            breedTotalsByLetter['$aLetter|$aBreed'.toLowerCase()] ?? aCount;
        final bTotal =
            breedTotalsByLetter['$bLetter|$bBreed'.toLowerCase()] ?? bCount;
        final totalCompare = bTotal.compareTo(aTotal);
        if (totalCompare != 0) return totalCompare;

        final breedCompare = aBreed.compareTo(bBreed);
        if (breedCompare != 0) return breedCompare;

        return scopeRank(aScope).compareTo(scopeRank(bScope));
      }

      // Separate Open/Youth mode: finish the selected scope order first within
      // each show letter, then use size and breed name.
      final scopeCompare = scopeRank(aScope).compareTo(scopeRank(bScope));
      if (scopeCompare != 0) return scopeCompare;

      final countCompare = bCount.compareTo(aCount);
      if (countCompare != 0) return countCompare;

      return aBreed.compareTo(bBreed);
    });

    return rows;
  }

  Future<void> _autoFillLineup(_LineupData data) async {
    setState(() => _isAutoFilling = true);
    if (data.judges.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add judges to the show first.')),
      );
      setState(() => _isAutoFilling = false);
      return;
    }

    final existingBreedRows = data.assignments.where((row) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      return !isJudgeChange;
    }).toList();

    if (existingBreedRows.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current line-up?'),
          content: const Text(
            'Auto Fill will clear the current superintendent line-up for this show and rebuild it from the current breed counts and selected judges.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Auto Fill'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _isAutoFilling = false);
        return;
      }
    }

    final breedRows = _autoBreedOptions(data);
    if (breedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No breed counts available to auto fill.')),
      );
      setState(() => _isAutoFilling = false);
      return;
    }

    try {
      await supabase
          .from('show_judging_assignments')
          .delete()
          .eq('show_id', widget.showId);

      // --- BEGIN: Load judge preferences ---
      // Prefer show-level aggregate superintendent preference weights when the
      // RPC exists. This lets Auto Fill weigh preferences from every assigned
      // superintendent without exposing another user's private rating details
      // in the UI. Fall back to the current user's own preferences if the RPC
      // has not been installed yet.
      final currentUserId = supabase.auth.currentUser?.id;
      List<Map<String, dynamic>> judgePreferenceRows;

      try {
        final aggregatedRows = await supabase.rpc(
          'get_show_superintendent_judge_preference_weights',
          params: {'p_show_id': widget.showId},
        );

        judgePreferenceRows = List<Map<String, dynamic>>.from(
          aggregatedRows as List,
        );
      } catch (_) {
        judgePreferenceRows = currentUserId == null
            ? const <Map<String, dynamic>>[]
            : List<Map<String, dynamic>>.from(
                await supabase
                    .from('show_superintendent_judge_preferences')
                    .select(
                      'judge_id, speed_rating, overall_quality_rating, accuracy_rating, best_class_system, daily_head_limit, allows_overage, overage_rate_per_, average_entries_per_hour',
                    )
                    .eq('user_id', currentUserId) as List,
              );
      }

      final judgePreferencesByJudgeId = <String, Map<String, dynamic>>{
        for (final row in judgePreferenceRows) row['judge_id'].toString(): row,
      };

      double judgePreferenceScore(
        String judgeId,
        Map<String, dynamic> breed,
        int currentLoad,
        int breedCount,
      ) {
        final preference = judgePreferencesByJudgeId[judgeId];
        if (preference == null) {
          return currentLoad + breedCount.toDouble();
        }

        final speed = (preference['speed_rating'] ??
                    preference['avg_speed_rating'] ??
                    preference['weighted_speed_rating'] as num?)
                ?.toDouble() ??
            5;
        final quality = (preference['overall_quality_rating'] ??
                    preference['avg_overall_quality_rating'] ??
                    preference['weighted_overall_quality_rating'] as num?)
                ?.toDouble() ??
            5;
        final accuracy = (preference['accuracy_rating'] ??
                    preference['avg_accuracy_rating'] ??
                    preference['weighted_accuracy_rating'] as num?)
                ?.toDouble() ??
            5;
        final dailyLimit = (preference['daily_head_limit'] ??
                    preference['avg_daily_head_limit'] ??
                    preference['weighted_daily_head_limit'] as num?)
                ?.toInt() ??
            250;
        final allowsOverage = preference['allows_overage'] != false;
        final overageRate = (preference['overage_rate_per_'] ??
                    preference['avg_overage_rate_per_'] ??
                    preference['weighted_overage_rate_per_'] as num?)
                ?.toDouble() ??
            0;
        final bestClassSystem =
            (preference['best_class_system'] ?? preference['preferred_class_system'] ?? 'unknown')
                .toString();
        final averageEntriesPerHour = (preference['average_entries_per_hour'] ??
                    preference['avg_average_entries_per_hour'] ??
                    preference['weighted_average_entries_per_hour'] as num?)
                ?.toDouble() ??
            0;

        final projectedLoad = currentLoad + breedCount;
        final ratingAverage = (speed + quality + accuracy) / 3.0;

        // When average_entries_per_hour is saved, score by projected judging
        // time instead of raw head count. Faster judges can take more head
        // without being unfairly penalized, while slower judges are protected
        // from being overloaded.
        final hasSpeedRate = averageEntriesPerHour > 0;
        final projectedHours = hasSpeedRate
            ? projectedLoad / averageEntriesPerHour
            : projectedLoad.toDouble();
        final currentHours = hasSpeedRate
            ? currentLoad / averageEntriesPerHour
            : currentLoad.toDouble();

        // Higher ratings reduce the score, making that judge more attractive.
        // The speed rate has the strongest effect through projectedHours.
        var score = projectedHours - (ratingAverage * 0.18);

        // Respect private capacity preferences. If overage is not allowed,
        // strongly avoid going past the judge's daily head limit.
        if (projectedLoad > dailyLimit) {
          final overage = projectedLoad - dailyLimit;
          final overagePenalty = hasSpeedRate
              ? overage / averageEntriesPerHour
              : overage.toDouble();
          score += allowsOverage
              ? overagePenalty * (1.25 + overageRate)
              : overagePenalty * 1000.0;
        }

        // Small preference nudge if the user marked the judge better for a class system.
        final classSystem = (breed['class_system'] ?? breed['classSystem'] ?? '')
            .toString()
            .toLowerCase();
        if (classSystem.isNotEmpty) {
          if (bestClassSystem == 'four_class' && classSystem.contains('four')) {
            score -= 15;
          } else if (bestClassSystem == 'six_class' && classSystem.contains('six')) {
            score -= 15;
          } else if (bestClassSystem == 'both') {
            score -= 8;
          }
        }

        // Slightly prefer judges who already have a compatible judging pace,
        // but do not let pace completely override duplicate and capacity rules.
        if (hasSpeedRate) {
          score -= (averageEntriesPerHour.clamp(0, 120) / 120.0) * 0.35;
        }

        return score;
      }
      // --- END: Load judge preferences ---

      final tableCount = data.judges.length;
      final judgeLoads = <String, int>{};
      final judgeBreedScopes = <String, Set<String>>{};
      final sortOrderByTable = <String, int>{};

      for (var i = 0; i < data.judges.length; i++) {
        final judge = data.judges[i];
        final judgeId = judge['judge_id']?.toString();
        if (judgeId == null || judgeId.isEmpty) continue;

        final tableNumber = '${i + 1}';
        judgeLoads[judgeId] = 0;
        judgeBreedScopes[judgeId] = <String>{};
        sortOrderByTable[tableNumber] = 1;

        await supabase.rpc(
          'upsert_show_judging_assignment',
          params: {
            'p_show_id': widget.showId,
            'p_section_id': null,
            'p_breed_id': '__judge_change__',
            'p_variety_key': null,
            'p_judge_id': judgeId,
            'p_table_number': tableNumber,
            'p_sort_order': 0,
            'p_status': 'draft',
            'p_scope': 'combined',
            'p_is_judge_change': true,
            'p_entry_count_actual': 0,
            'p_notes': 'Auto Fill judge start',
          },
        );
      }

      // Process rows in show-letter order. This makes the line-up favor
      // completing Show A before moving to Show B, then C, etc. Judge selection
      // inside each show letter still uses workload, duplicate rules, and saved
      // superintendent judge preferences.
      for (final breed in breedRows) {
        final breedName = (breed['breed'] ?? '').toString().toLowerCase();
        final scope = (breed['scope'] ?? '').toString().toLowerCase();
        final count = (breed['entry_count'] as num?)?.toInt() ?? 0;
        final breedScopeKey = '$breedName|$scope';

        Map<String, dynamic>? selectedJudge;
        var selectedScore = double.infinity;

        for (final judge in data.judges) {
          final judgeId = judge['judge_id']?.toString();
          if (judgeId == null || judgeId.isEmpty) continue;

          final usedBreedScopes = judgeBreedScopes[judgeId] ?? <String>{};
          if (usedBreedScopes.contains(breedScopeKey)) continue;

          final load = judgeLoads[judgeId] ?? 0;
          final score = judgePreferenceScore(judgeId, breed, load, count);
          if (score < selectedScore) {
            selectedJudge = judge;
            selectedScore = score;
          }
        }

        // If every judge already has this breed/scope somewhere, place it with
        // the lowest scored judge and record an override note.
        selectedJudge ??= data.judges.fold<Map<String, dynamic>?>(null, (best, judge) {
          final judgeId = judge['judge_id']?.toString();
          if (judgeId == null || judgeId.isEmpty) return best;
          if (best == null) return judge;

          final bestId = best['judge_id']?.toString();
          final bestScore = bestId == null
              ? double.infinity
              : judgePreferenceScore(
                  bestId,
                  breed,
                  judgeLoads[bestId] ?? 0,
                  count,
                );
          final score = judgePreferenceScore(
            judgeId,
            breed,
            judgeLoads[judgeId] ?? 0,
            count,
          );
          return score < bestScore ? judge : best;
        });

        final judgeId = selectedJudge?['judge_id']?.toString();
        if (judgeId == null || judgeId.isEmpty) continue;

        final judgeIndex = data.judges.indexOf(selectedJudge!);
        final tableNumber = '${judgeIndex + 1}';
        final sortOrder = sortOrderByTable[tableNumber] ?? 1;
        final requiresOverride =
            judgeBreedScopes[judgeId]?.contains(breedScopeKey) == true;

        await supabase.rpc(
          'upsert_show_judging_assignment',
          params: {
            'p_show_id': widget.showId,
            'p_section_id': breed['section_id'],
            'p_breed_id': breed['breed'],
            'p_variety_key': breed['variety'],
            'p_judge_id': null,
            'p_table_number': tableNumber,
            'p_sort_order': sortOrder,
            'p_status': 'draft',
            'p_scope': breed['scope'],
            'p_entry_count_actual': count,
            'p_notes': requiresOverride
                ? 'Auto Fill override: same judge assigned same breed/Open-Youth because no clean judge was available.'
                : judgePreferencesByJudgeId.containsKey(judgeId)
                    ? 'Auto Fill used superintendent judge preferences including judging pace when available.'
                    : null,
          },
        );

        sortOrderByTable[tableNumber] = sortOrder + 1;
        judgeLoads[judgeId] = (judgeLoads[judgeId] ?? 0) + count;
        judgeBreedScopes.putIfAbsent(judgeId, () => <String>{}).add(breedScopeKey);
      }

      await _syncLineupToEntries();

      if (!mounted) return;
      setState(() => _isAutoFilling = false);
      setState(() {
        _future = _loadData();
      });
      await _future;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto Fill completed. Review before finalizing.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAutoFilling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      if (!mounted) return;
      setState(() {
        _future = _loadData();
      });
      await _future;
    }
  }
  // --- END: Auto Fill Helpers ---

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Judging Line-Up',
      subtitle: widget.showName,
      actions: [
        TextButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
        TextButton.icon(
          onPressed: _isSyncingEntries ? null : _manualSyncLineupToEntries,
          icon: _isSyncingEntries
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(_isSyncingEntries ? 'Syncing...' : 'Sync Judges'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
        TextButton.icon(
          onPressed: _isAutoFilling
              ? null
              : () async {
                  final data = await _future;
                  if (!mounted) return;
                  await _autoFillLineup(data);
                },
          icon: _isAutoFilling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high),
          label: Text(_isAutoFilling ? 'Auto Filling...' : 'Auto Fill'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
        TextButton.icon(
          onPressed: _addTable,
          icon: const Icon(Icons.table_chart),
          label: const Text('Add Table'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
      ],
      body: FutureBuilder<_LineupData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final data = snapshot.data ?? _LineupData.empty();
          final grouped = _groupByTable(data.assignments);
          final tableNumbers = _tableNumbersForData(data, grouped);

          return Column(
            children: [
              if (_isAutoFilling || _isSyncingEntries)
                const LinearProgressIndicator(minHeight: 3),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      _SummaryCards(
                        data: data,
                        isSavingPublishedState: _isSavingPublishedState,
                        onPublishChanged: (value) => _setJudgeOrderPublished(
                          data,
                          value,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ResponsiveTableGrid(
                        tableNumbers: tableNumbers,
                        groupedAssignments: grouped,
                        onAddBreed: (tableNumber) => _openAddSheet(
                          data,
                          tableNumber: tableNumber,
                          sortOrder: _nextSortOrderForTable(tableNumber, grouped),
                        ),
                        onChangeJudge: (tableNumber) => _openAddJudgeSheet(
                          data,
                          tableNumber: tableNumber,
                          sortOrder: _nextSortOrderForTable(tableNumber, grouped),
                        ),
                        onDeleteAssignment: _deleteAssignment,
                        onReorderAssignments: _reorderAssignments,
                        onMoveAssignmentToTable: (assignmentId, tableNumber) =>
                            _moveAssignmentToTable(
                          assignmentId,
                          tableNumber,
                          _nextSortOrderForTable(tableNumber, grouped),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LineupData {
  const _LineupData({
    required this.assignments,
    required this.judges,
    required this.breedCounts,
    required this.workloads,
    required this.userPreferences,
    required this.judgeOrderPublished,
    required this.judgeOrderPublishedAt,
    required this.judgeOrderPublishedBy,
  });

  factory _LineupData.empty() => const _LineupData(
        assignments: <Map<String, dynamic>>[],
        judges: <Map<String, dynamic>>[],
        breedCounts: <Map<String, dynamic>>[],
        workloads: <Map<String, dynamic>>[],
        userPreferences: <String, dynamic>{},
        judgeOrderPublished: false,
        judgeOrderPublishedAt: null,
        judgeOrderPublishedBy: null,
      );

  final List<Map<String, dynamic>> assignments;
  final List<Map<String, dynamic>> judges;
  final List<Map<String, dynamic>> breedCounts;
  final List<Map<String, dynamic>> workloads;
  final Map<String, dynamic> userPreferences;
  final bool judgeOrderPublished;
  final String? judgeOrderPublishedAt;
  final String? judgeOrderPublishedBy;
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.data,
    required this.isSavingPublishedState,
    required this.onPublishChanged,
  });

  final _LineupData data;
  final bool isSavingPublishedState;
  final ValueChanged<bool> onPublishChanged;

  bool _isJudgeRow(Map<String, dynamic> row) {
    return row['is_judge_change'] == true ||
        (row['breed_id'] ?? '').toString() == '__judge_change__';
  }

  String _scopeLabelForRow(Map<String, dynamic> row) {
    final raw = (row['scope'] ?? row['section_kind'] ?? row['kind'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (raw == 'open') return 'Open';
    if (raw == 'youth') return 'Youth';
    return '';
  }

  String _showLetterForRow(Map<String, dynamic> row) {
    return (row['show_letter'] ?? row['letter'] ?? row['section_letter'] ?? '')
        .toString()
        .trim();
  }

  int _headCountForRow(Map<String, dynamic> row) {
    final actual = (row['entry_count_actual'] as num?)?.toInt();
    final estimated = (row['entry_count_estimated'] as num?)?.toInt();
    final count = (row['entry_count'] as num?)?.toInt();
    return actual ?? estimated ?? count ?? 0;
  }

  String _breedKeyFromAssignment(Map<String, dynamic> row) {
    final letter = _showLetterForRow(row).toLowerCase();
    final scope = _scopeLabelForRow(row).toLowerCase();
    final breed = (row['breed_id'] ?? '').toString().trim().toLowerCase();
    if (letter.isEmpty || scope.isEmpty || breed.isEmpty) return '';
    return '$letter|$scope|$breed';
  }

  String _breedKeyFromCount(Map<String, dynamic> row) {
    final letter = _showLetterForRow(row).toLowerCase();
    final scope = _scopeLabelForRow(row).toLowerCase();
    final breed = (row['breed'] ?? '').toString().trim().toLowerCase();
    if (letter.isEmpty || scope.isEmpty || breed.isEmpty) return '';
    return '$letter|$scope|$breed';
  }

  @override
  Widget build(BuildContext context) {
    final assignedBreedRows = data.assignments.where((row) => !_isJudgeRow(row)).toList();
    final judgeRows = data.assignments.where(_isJudgeRow).toList();

    final assignedBreedKeys = <String>{};
    var assignedHead = 0;
    var conflictCount = 0;

    for (final row in assignedBreedRows) {
      final key = _breedKeyFromAssignment(row);
      if (key.isNotEmpty) assignedBreedKeys.add(key);
      assignedHead += _headCountForRow(row);
      if (row['duplicate_judge_breed'] == true) conflictCount += 1;
    }

    final availableBreedKeys = <String>{};
    var availableHead = 0;

    for (final row in data.breedCounts) {
      final key = _breedKeyFromCount(row);
      if (key.isNotEmpty) availableBreedKeys.add(key);
      availableHead += _headCountForRow(row);
    }

    final unassignedBreedRows = availableBreedKeys.difference(assignedBreedKeys).length;
    final remainingHead = (availableHead - assignedHead).clamp(0, availableHead);

    final tableNumbers = data.assignments
        .map((row) => (row['table_number'] ?? '').toString())
        .where((table) => table.isNotEmpty)
        .toSet();

    final assignedJudgeIds = judgeRows
        .map((row) => row['judge_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final assignedJudgeLabel = '${assignedJudgeIds.length}/${data.judges.length}';
    final assignedHeadLabel = '$assignedHead/$availableHead';

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          icon: Icons.gavel,
          label: 'Judges Assigned',
          value: assignedJudgeLabel,
          helper: assignedJudgeIds.length == data.judges.length
              ? '${tableNumbers.length} active table${tableNumbers.length == 1 ? '' : 's'}'
              : '${data.judges.length - assignedJudgeIds.length} judge(s) not used',
          isWarning: assignedJudgeIds.length < data.judges.length,
        ),
        _MetricCard(
          icon: Icons.pets,
          label: 'Head Assigned',
          value: assignedHeadLabel,
          helper: availableHead == 0
              ? 'No entries'
              : '${((assignedHead / availableHead) * 100).toStringAsFixed(0)}% complete • $remainingHead remaining',
          isWarning: remainingHead > 0,
        ),
        _MetricCard(
          icon: Icons.warning_amber,
          label: 'Needs Attention',
          value: conflictCount.toString(),
          helper: conflictCount == 0
              ? 'No duplicate judge/breed flags'
              : 'Duplicate judge/breed flags',
          isWarning: conflictCount > 0,
        ),
        _PublishJudgeOrderCard(
          published: data.judgeOrderPublished,
          saving: isSavingPublishedState,
          publishedAt: data.judgeOrderPublishedAt,
          onChanged: onPublishChanged,
        ),
      ],
    );
  }
}

class _PublishJudgeOrderCard extends StatelessWidget {
  const _PublishJudgeOrderCard({
    required this.published,
    required this.saving,
    required this.publishedAt,
    required this.onChanged,
  });

  final bool published;
  final bool saving;
  final String? publishedAt;
  final ValueChanged<bool> onChanged;

  String _publishedHelper() {
    if (!published) return 'Hidden from exhibitors';

    final parsed = DateTime.tryParse((publishedAt ?? '').toString());
    if (parsed == null) return 'Visible to exhibitors';

    final local = parsed.toLocal();
    final date = '${local.month}/${local.day}/${local.year}';
    final minute = local.minute.toString().padLeft(2, '0');
    final hour12 = local.hour == 0
        ? 12
        : local.hour > 12
            ? local.hour - 12
            : local.hour;
    final amPm = local.hour >= 12 ? 'PM' : 'AM';

    return 'Published $date $hour12:$minute $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = published ? Colors.green : Colors.orange;

    return Container(
      width: 250,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            published ? Icons.visibility : Icons.visibility_off,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  published ? 'Published' : 'Not Published',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  'Judge Order',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _publishedHelper(),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: published,
            onChanged: saving ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
    this.isWarning = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helper;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = isWarning ? colorScheme.error : colorScheme.primary;

    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (helper != null && helper!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    helper!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _ResponsiveTableGrid extends StatelessWidget {
  const _ResponsiveTableGrid({
    required this.tableNumbers,
    required this.groupedAssignments,
    required this.onAddBreed,
    required this.onChangeJudge,
    required this.onDeleteAssignment,
    required this.onReorderAssignments,
    required this.onMoveAssignmentToTable,
  });

  final List<String> tableNumbers;
  final Map<String, List<Map<String, dynamic>>> groupedAssignments;
  final void Function(String tableNumber) onAddBreed;
  final void Function(String tableNumber) onChangeJudge;
  final Future<void> Function(String assignmentId) onDeleteAssignment;
  final Future<void> Function(
    List<Map<String, dynamic>> assignments,
    int oldIndex,
    int newIndex,
  ) onReorderAssignments;
  final Future<void> Function(String assignmentId, String tableNumber)
      onMoveAssignmentToTable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 1200
            ? 4
            : maxWidth >= 900
                ? 3
                : maxWidth >= 620
                    ? 2
                    : 1;
        final spacing = 12.0;
        final cardWidth = (maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tableNumbers.map((tableNumber) {
            return SizedBox(
              width: cardWidth,
              child: _TableCard(
                tableNumber: tableNumber,
                tableNumbers: tableNumbers,
                assignments: groupedAssignments[tableNumber] ?? const <Map<String, dynamic>>[],
                onAddBreed: () => onAddBreed(tableNumber),
                onChangeJudge: () => onChangeJudge(tableNumber),
                onDeleteAssignment: onDeleteAssignment,
                onReorderAssignments: onReorderAssignments,
                onMoveAssignmentToTable: onMoveAssignmentToTable,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.tableNumber,
    required this.tableNumbers,
    required this.assignments,
    required this.onAddBreed,
    required this.onChangeJudge,
    required this.onDeleteAssignment,
    required this.onReorderAssignments,
    required this.onMoveAssignmentToTable,
  });

  final String tableNumber;
  final List<String> tableNumbers;
  final List<Map<String, dynamic>> assignments;
  final VoidCallback onAddBreed;
  final VoidCallback onChangeJudge;
  final Future<void> Function(String assignmentId) onDeleteAssignment;
  final Future<void> Function(
    List<Map<String, dynamic>> assignments,
    int oldIndex,
    int newIndex,
  ) onReorderAssignments;
  final Future<void> Function(String assignmentId, String tableNumber)
      onMoveAssignmentToTable;


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasBreedRows = assignments.any((row) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      return !isJudgeChange;
    });
    final hasJudgeRows = assignments.any((row) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      return isJudgeChange;
    });
    final hasActiveJudgeRows = assignments.any((row) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      if (!isJudgeChange) return false;

      final blockHeadCount = (row['block_head_count'] as num?)?.toInt() ?? 0;
      return blockHeadCount > 0;
    });

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) {
        onMoveAssignmentToTable(details.data, tableNumber);
      },
      builder: (context, candidateData, rejectedData) {
        final isDragTarget = candidateData.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDragTarget ? colorScheme.primary : colorScheme.outlineVariant,
              width: isDragTarget ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final veryCompact = constraints.maxWidth < 330;

                final title = Text(
                  'Table $tableNumber',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                );

                final judgeButton = OutlinedButton.icon(
                  onPressed: onChangeJudge,
                  icon: const Icon(Icons.gavel, size: 16),
                  label: const Text('Judge'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                final breedButton = FilledButton.icon(
                  onPressed: onAddBreed,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Breed'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                if (veryCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          judgeButton,
                          const SizedBox(width: 8),
                          breedButton,
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: title,
                    ),
                    const SizedBox(width: 8),
                    judgeButton,
                    const SizedBox(width: 8),
                    breedButton,
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: assignments.isEmpty
                ? Text(
                    'Table empty — fill with judge.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: assignments.length,
                        onReorder: (oldIndex, newIndex) => onReorderAssignments(
                          assignments,
                          oldIndex,
                          newIndex,
                        ),
                        itemBuilder: (context, index) {
                          final row = assignments[index];
                          final id = row['id']?.toString() ?? 'row-$index';

                      return _LineupRow(
                        key: ValueKey(id),
                        row: row,
                        index: index,
                        currentTableNumber: tableNumber,
                        tableNumbers: tableNumbers,
                        onMoveToTable: onMoveAssignmentToTable,
                        onDelete: () {
                          final assignmentId = row['id']?.toString();
                          if (assignmentId == null || assignmentId.isEmpty) return;
                          onDeleteAssignment(assignmentId);
                        },
                      );
                        },
                      ),
                      if (!hasBreedRows) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Table empty — fill with breeds for this judge.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (hasBreedRows && !hasActiveJudgeRows) ...[
                        const SizedBox(height: 10),
                        Divider(
                          height: 1,
                          color: colorScheme.error.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasJudgeRows
                              ? 'Judge moved — fill this table with a judge.'
                              : 'Table has breeds — fill with judge.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: onChangeJudge,
                            icon: const Icon(Icons.gavel, size: 16),
                            label: const Text('Add Judge'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
            ],
          ),
        );
      },
    );
  }
}


class _SpeciesIcon extends StatelessWidget {
  const _SpeciesIcon({required this.speciesLabel});

  final String speciesLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalized = speciesLabel.toLowerCase();

    final emoji = normalized == 'rabbit'
        ? '🐇'
        : normalized == 'cavy'
            ? '🐹'
            : '•';

    return SizedBox(
      width: 22,
      child: Text(
        emoji,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: normalized == 'rabbit' || normalized == 'cavy' ? 18 : 22,
          color: colorScheme.onSurfaceVariant,
          height: 1,
        ),
      ),
    );
  }
}
class _LineupRow extends StatelessWidget {
  const _LineupRow({
    super.key,
    required this.row,
    required this.index,
    required this.currentTableNumber,
    required this.tableNumbers,
    required this.onMoveToTable,
    required this.onDelete,
  });

  final Map<String, dynamic> row;
  final int index;
  final String currentTableNumber;
  final List<String> tableNumbers;
  final Future<void> Function(String assignmentId, String tableNumber)
      onMoveToTable;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isJudgeChange = row['is_judge_change'] == true ||
        (row['breed_id'] ?? '').toString() == '__judge_change__';
    final headCount = (row['entry_count_actual'] as num?)?.toInt() ??
        (row['entry_count_estimated'] as num?)?.toInt() ??
        0;
    final judgeName = (row['judge_name'] ?? 'Judge not set').toString();
    final showLetter = (row['show_letter'] ??
            row['letter'] ??
            row['section_letter'] ??
            row['showLetter'] ??
            '')
        .toString()
        .trim();
    final rawBreedName = (row['breed_id'] ?? 'Breed not set').toString();
    final breedName = isJudgeChange
        ? judgeName
        : [
            if (showLetter.isNotEmpty) showLetter,
            rawBreedName,
          ].join(' | ');
    final speciesRaw = (row['species'] ?? row['species_name'] ?? '').toString().toLowerCase();
    final speciesLabel = speciesRaw == 'cavy'
        ? 'Cavy'
        : speciesRaw == 'rabbit'
            ? 'Rabbit'
            : 'Species not set';
    final scopeRaw = (row['scope'] ?? row['section_kind'] ?? row['kind'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final scopeLabel = scopeRaw == 'youth'
        ? 'Youth'
        : scopeRaw == 'open'
            ? 'Open'
            : '';

    // Duplicate judge/breed detection and override
    final isDuplicateJudgeBreed = row['duplicate_judge_breed'] == true;
    final hasOverride = (row['override_reason'] ?? row['notes'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;

    final assignmentId = row['id']?.toString() ?? '';

    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: isJudgeChange
                ? Icon(
                    Icons.swap_horiz,
                    size: 22,
                    color: colorScheme.onSurfaceVariant,
                  )
                : _SpeciesIcon(speciesLabel: speciesLabel),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  breedName,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: !isJudgeChange && isDuplicateJudgeBreed && !hasOverride
                        ? colorScheme.error
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isJudgeChange
                      ? 'JUDGE'
                      : [
                          speciesLabel.toUpperCase(),
                          if (scopeLabel.isNotEmpty) scopeLabel.toUpperCase(),
                        ].join(' • '),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                if (!isJudgeChange && isDuplicateJudgeBreed) ...[
                  const SizedBox(height: 2),
                  Text(
                    hasOverride
                        ? 'Duplicate judge/breed override recorded'
                        : 'Duplicate judge/breed needs override',
                    style: textTheme.bodySmall?.copyWith(
                      color: hasOverride ? colorScheme.primary : colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!isJudgeChange && assignmentId.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Move to table',
              icon: Icon(
                Icons.drive_file_move_outline,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              onSelected: (targetTable) {
                if (targetTable == currentTableNumber) return;
                onMoveToTable(assignmentId, targetTable);
              },
              itemBuilder: (context) => tableNumbers
                  .where((table) => table != currentTableNumber)
                  .map(
                    (table) => PopupMenuItem<String>(
                      value: table,
                      child: Text('Move to Table $table'),
                    ),
                  )
                  .toList(),
            ),
          IconButton(
            tooltip: isJudgeChange ? 'Remove judge' : 'Remove breed',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: onDelete,
          ),
          if (!(isJudgeChange && ((row['block_head_count'] as num?)?.toInt() ?? 0) == 0)) ...[
            const SizedBox(width: 4),
            Text(
              isJudgeChange
                  ? (() {
                      final total = (row['block_head_count'] as num?)?.toInt() ?? 0;
                      return total == 0 ? '' : '$total / 250';
                    })()
                  : '$headCount',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );

    if (isJudgeChange || assignmentId.isEmpty) {
      return rowContent;
    }

    return Draggable<String>(
      data: assignmentId,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Text(
            breedName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: rowContent,
      ),
      child: rowContent,
    );
  }
}

class _AddJudgeChangeSheet extends StatefulWidget {
  const _AddJudgeChangeSheet({
    required this.showId,
    required this.judges,
    required this.tableNumber,
    required this.sortOrder,
  });

  final String showId;
  final List<Map<String, dynamic>> judges;
  final String tableNumber;
  final int sortOrder;

  @override
  State<_AddJudgeChangeSheet> createState() => _AddJudgeChangeSheetState();
}

class _AddJudgeChangeSheetState extends State<_AddJudgeChangeSheet> {
  String? _judgeId;
  bool _saving = false;

  void _selectJudge(String? value) {
    if (value == null || value.isEmpty || _saving) return;
    setState(() => _judgeId = value);
    _save();
  }

  Future<void> _save() async {
    if (_judgeId == null || _judgeId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a judge first.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await supabase.rpc(
        'upsert_show_judging_assignment',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': null,
          'p_breed_id': '__judge_change__',
          'p_variety_key': null,
          'p_judge_id': _judgeId,
          'p_table_number': widget.tableNumber,
          'p_sort_order': widget.sortOrder,
          'p_status': 'draft',
          'p_scope': 'combined',
          'p_is_judge_change': true,
          'p_entry_count_actual': 0,
          'p_notes': 'Judge change',
        },
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Judge to Table ${widget.tableNumber}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _judgeId,
            decoration: const InputDecoration(
              labelText: 'Judge',
              border: OutlineInputBorder(),
            ),
            items: widget.judges.map((judge) {
              final id = judge['judge_id']?.toString();
              final name = (judge['judge_name'] ?? 'Unknown Judge').toString();
              return DropdownMenuItem<String>(
                value: id,
                child: Text(name),
              );
            }).toList(),
            onChanged: _selectJudge,
          ),
          if (_saving) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _AddAssignmentSheet extends StatefulWidget {
  const _AddAssignmentSheet({
    required this.showId,
    required this.judges,
    required this.breedCounts,
    required this.assignedRows,
    required this.userPreferences,
    required this.tableNumber,
    required this.sortOrder,
    required this.initialSortMode,
    required this.initialShowLetter,
    required this.onSortModeChanged,
    required this.onShowLetterChanged,
  });

  final String showId;
  final List<Map<String, dynamic>> judges;
  final List<Map<String, dynamic>> breedCounts;
  final List<Map<String, dynamic>> assignedRows;
  final Map<String, dynamic> userPreferences;
  final String tableNumber;
  final int sortOrder;
  final String initialSortMode;
  final String? initialShowLetter;
  final ValueChanged<String> onSortModeChanged;
  final ValueChanged<String?> onShowLetterChanged;

  @override
  State<_AddAssignmentSheet> createState() => _AddAssignmentSheetState();
}

class _AddAssignmentSheetState extends State<_AddAssignmentSheet> {
  bool _alreadyAssignedExactBreedRow(Map<String, dynamic> breed) {
    final targetBreed = (breed['breed'] ?? '').toString().trim().toLowerCase();
    final targetScope = _scopeLabelForRow(breed).toLowerCase();
    final targetLetter = _showLetterForRow(breed).toLowerCase();

    if (targetBreed.isEmpty || targetScope.isEmpty || targetLetter.isEmpty) {
      return false;
    }

    final assignedKey = '$targetLetter|$targetScope|$targetBreed'.toLowerCase();
    if (_newlyAssignedBreedKeys.contains(assignedKey)) {
      return true;
    }

    for (final row in widget.assignedRows) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      if (isJudgeChange) continue;

      final rowBreed = (row['breed_id'] ?? '').toString().trim().toLowerCase();
      final rowScope = _scopeLabelForRow(row).toLowerCase();
      final rowLetter = _showLetterForRow(row).toLowerCase();

      if (rowBreed == targetBreed &&
          rowScope == targetScope &&
          rowLetter == targetLetter) {
        return true;
      }
    }

    return false;
  }
  String _scopeLabelForRow(Map<String, dynamic> row) {
    final raw = (row['scope'] ??
            row['section_scope'] ??
            row['section_kind'] ??
            row['kind'] ??
            row['breed_scope'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();

    if (raw == 'open') return 'Open';
    if (raw == 'youth') return 'Youth';

    final label = (row['section_label'] ?? row['section_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (label.contains('youth')) return 'Youth';
    if (label.contains('open')) return 'Open';

    return '';
  }

  String _showLetterForRow(Map<String, dynamic> row) {
    return (row['show_letter'] ??
            row['letter'] ??
            row['section_letter'] ??
            row['showLetter'] ??
            '')
        .toString()
        .trim();
  }
  bool _saving = false;
  bool _addedAny = false;
  late String _breedSortMode;
  String? _selectedShowLetter;
  final Set<String> _newlyAssignedBreedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _breedSortMode = widget.initialSortMode;
    _selectedShowLetter = widget.initialShowLetter;
  }

  Set<String> get _assignedBreedKeys {
    final keys = <String>{};

    for (final row in widget.assignedRows) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      if (isJudgeChange) continue;

      final showLetter = _showLetterForRow(row);
      final breed = (row['breed_id'] ?? '').toString();
      final scope = _scopeLabelForRow(row);
      if (showLetter.isEmpty || breed.isEmpty || scope.isEmpty) continue;

      keys.add('$showLetter|$scope|$breed'.toLowerCase());
    }

    return {...keys, ..._newlyAssignedBreedKeys};
  }

  List<String> get _availableShowLetters {
    final letters = <String>{};
    final assignedBreedKeys = _assignedBreedKeys;

    for (final row in widget.breedCounts) {
      final showLetter = _showLetterForRow(row);
      final breed = (row['breed'] ?? '').toString();
      final scope = _scopeLabelForRow(row);
      final assignedKey = '$showLetter|$scope|$breed'.toLowerCase();
      if (assignedBreedKeys.contains(assignedKey)) continue;

      final letter = showLetter;
      if (letter.isNotEmpty) letters.add(letter);
    }

    final sorted = letters.toList();
    sorted.sort();
    return sorted;
  }

  Map<String, dynamic>? get _currentJudgeRow {
    final tableRows = widget.assignedRows
        .where((row) => (row['table_number'] ?? '').toString() == widget.tableNumber)
        .toList();

    tableRows.sort((a, b) {
      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });

    for (final row in tableRows.reversed) {
      final isJudgeChange = row['is_judge_change'] == true ||
          (row['breed_id'] ?? '').toString() == '__judge_change__';
      if (isJudgeChange) return row;
    }

    return null;
  }

  String? get _currentJudgeId => _currentJudgeRow?['judge_id']?.toString();

  String get _currentJudgeName {
    final judgeName = (_currentJudgeRow?['judge_name'] ?? '').toString().trim();
    if (judgeName.isNotEmpty) return judgeName;
    return 'No judge selected';
  }

  // Group breed counts by show letter + scope + breed, summing all varieties.
  List<Map<String, dynamic>> get _breedOptions {
    final grouped = <String, Map<String, dynamic>>{};
    final assignedBreedKeys = _assignedBreedKeys;

    for (final row in widget.breedCounts) {
      final showLetter = _showLetterForRow(row);
      final breed = (row['breed'] ?? '').toString();
      final species = row['species'];
      final scope = _scopeLabelForRow(row);
      final assignedKey = '$showLetter|$scope|$breed'.toLowerCase();
      if (assignedBreedKeys.contains(assignedKey)) continue;
      if (_selectedShowLetter != null &&
          _selectedShowLetter!.isNotEmpty &&
          showLetter != _selectedShowLetter) {
        continue;
      }
      final key = '$showLetter|$scope|$breed';
      final count = (row['entry_count'] as num?)?.toInt() ?? 0;

      grouped.putIfAbsent(
        key,
        () => <String, dynamic>{
          'dropdown_key': key,
          'assigned_key': assignedKey,
          'section_id': row['section_id'],
          'section_ids': <String>{row['section_id']?.toString() ?? ''},
          'show_letter': showLetter,
          'breed': breed,
          'variety': null,
          'species': species,
          'entry_count': 0,
          'scope': scope,
        },
      );

      final sectionIds = grouped[key]!['section_ids'];
      if (sectionIds is Set<String>) {
        final sectionId = row['section_id']?.toString() ?? '';
        if (sectionId.isNotEmpty) sectionIds.add(sectionId);
      }

      grouped[key]!['entry_count'] =
          ((grouped[key]!['entry_count'] as num?)?.toInt() ?? 0) + count;
    }

    final options = grouped.values.toList();

    final openYouthMode =
        (widget.userPreferences['open_youth_mode'] ?? 'together').toString();
    final showOrder =
        (widget.userPreferences['show_order'] ?? 'open_first').toString();
    final pairOpenYouth = openYouthMode == 'together';

    int scopeRank(String scope) {
      final normalized = scope.toLowerCase();
      if (showOrder == 'youth_first') {
        if (normalized == 'youth') return 0;
        if (normalized == 'open') return 1;
      } else {
        if (normalized == 'open') return 0;
        if (normalized == 'youth') return 1;
      }
      return 2;
    }

    final breedTotalsByLetter = <String, int>{};
    for (final row in options) {
      final letter = (row['show_letter'] ?? '').toString();
      final breed = (row['breed'] ?? '').toString();
      final key = '$letter|$breed'.toLowerCase();
      breedTotalsByLetter[key] =
          (breedTotalsByLetter[key] ?? 0) +
              ((row['entry_count'] as num?)?.toInt() ?? 0);
    }

    options.sort((a, b) {
      final aLetter = (a['show_letter'] ?? '').toString();
      final bLetter = (b['show_letter'] ?? '').toString();
      final aBreed = (a['breed'] ?? '').toString();
      final bBreed = (b['breed'] ?? '').toString();
      final aScope = (a['scope'] ?? '').toString();
      final bScope = (b['scope'] ?? '').toString();
      final aCount = (a['entry_count'] as num?)?.toInt() ?? 0;
      final bCount = (b['entry_count'] as num?)?.toInt() ?? 0;

      if (_breedSortMode == 'count') {
        final countCompare = bCount.compareTo(aCount);
        if (countCompare != 0) return countCompare;

        if (pairOpenYouth) {
          final aTotal =
              breedTotalsByLetter['$aLetter|$aBreed'.toLowerCase()] ?? aCount;
          final bTotal =
              breedTotalsByLetter['$bLetter|$bBreed'.toLowerCase()] ?? bCount;
          final totalCompare = bTotal.compareTo(aTotal);
          if (totalCompare != 0) return totalCompare;
        }

        final breedCompare = aBreed.compareTo(bBreed);
        if (breedCompare != 0) return breedCompare;
        return scopeRank(aScope).compareTo(scopeRank(bScope));
      }

      final letterCompare = aLetter.compareTo(bLetter);
      if (letterCompare != 0) return letterCompare;

      if (pairOpenYouth) {
        final aTotal =
            breedTotalsByLetter['$aLetter|$aBreed'.toLowerCase()] ?? aCount;
        final bTotal =
            breedTotalsByLetter['$bLetter|$bBreed'.toLowerCase()] ?? bCount;
        final totalCompare = bTotal.compareTo(aTotal);
        if (totalCompare != 0) return totalCompare;

        final breedCompare = aBreed.compareTo(bBreed);
        if (breedCompare != 0) return breedCompare;

        return scopeRank(aScope).compareTo(scopeRank(bScope));
      }

      final scopeCompare = scopeRank(aScope).compareTo(scopeRank(bScope));
      if (scopeCompare != 0) return scopeCompare;

      final countCompare = bCount.compareTo(aCount);
      if (countCompare != 0) return countCompare;

      return aBreed.compareTo(bBreed);
    });

    return options;
  }

  // --- BEGIN: Open & Youth Pair helpers ---
  List<Map<String, dynamic>> _openYouthPairFor(
    Map<String, dynamic> breed,
    List<Map<String, dynamic>> options,
  ) {
    final showLetter = (breed['show_letter'] ?? '').toString();
    final breedName = (breed['breed'] ?? '').toString();

    final matches = options.where((option) {
      final optionLetter = (option['show_letter'] ?? '').toString();
      final optionBreed = (option['breed'] ?? '').toString();
      final optionScope = _scopeLabelForRow(option).toLowerCase();

      return optionLetter == showLetter &&
          optionBreed == breedName &&
          (optionScope == 'open' || optionScope == 'youth');
    }).toList();

    final hasOpen = matches.any(
      (option) => _scopeLabelForRow(option).toLowerCase() == 'open',
    );
    final hasYouth = matches.any(
      (option) => _scopeLabelForRow(option).toLowerCase() == 'youth',
    );

    if (!hasOpen || !hasYouth) return const <Map<String, dynamic>>[];

    matches.sort((a, b) {
      final aScope = _scopeLabelForRow(a).toLowerCase();
      final bScope = _scopeLabelForRow(b).toLowerCase();
      if (aScope == bScope) return 0;
      if (aScope == 'open') return -1;
      return 1;
    });

    return matches;
  }

  List<Map<String, dynamic>> _existingSameJudgeBreedRows(Map<String, dynamic> breed) {
    final judgeId = _currentJudgeId;
    if (judgeId == null || judgeId.isEmpty) return const <Map<String, dynamic>>[];

    final targetBreed = (breed['breed'] ?? '').toString().trim().toLowerCase();
    final targetScope = _scopeLabelForRow(breed).toLowerCase();
    final targetLetter = _showLetterForRow(breed).toLowerCase();
    if (targetBreed.isEmpty || targetScope.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final rowsByTable = <String, List<Map<String, dynamic>>>{};
    for (final row in widget.assignedRows) {
      final table = (row['table_number'] ?? 'Unassigned').toString();
      rowsByTable.putIfAbsent(table, () => <Map<String, dynamic>>[]).add(row);
    }

    final matches = <Map<String, dynamic>>[];

    for (final rows in rowsByTable.values) {
      rows.sort((a, b) {
        final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      });

      String? activeJudgeId;

      for (final row in rows) {
        final isJudgeChange = row['is_judge_change'] == true ||
            (row['breed_id'] ?? '').toString() == '__judge_change__';

        if (isJudgeChange) {
          activeJudgeId = row['judge_id']?.toString();
          continue;
        }

        final rowBreed = (row['breed_id'] ?? '').toString().trim().toLowerCase();
        final rowScope = _scopeLabelForRow(row).toLowerCase();
        final rowLetter = _showLetterForRow(row).toLowerCase();

        if (activeJudgeId == judgeId &&
            rowBreed == targetBreed &&
            rowScope == targetScope &&
            rowLetter != targetLetter) {
          matches.add(row);
        }
      }
    }

    return matches;
  }

  Future<String?> _requestDuplicateOverride(
    Map<String, dynamic> breed,
    List<Map<String, dynamic>> conflicts,
  ) async {
    final controller = TextEditingController();
    final breedName = (breed['breed'] ?? 'this breed').toString();
    final judgeName = _currentJudgeName;

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Override required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$judgeName already has ${_scopeLabelForRow(breed)} $breedName assigned in another show letter.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Override reason',
                hintText: 'Example: emergency judge change, superintendent approved, etc.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: const Text('Save Override'),
          ),
        ],
      ),
    );

    controller.dispose();
    return reason;
  }

  Future<bool> _addBreedRow(Map<String, dynamic> breed) async {
    if (_alreadyAssignedExactBreedRow(breed)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That show letter, breed, and Open/Youth row is already assigned.'),
          ),
        );
      }
      return false;
    }

    // --- BEGIN: Determine usable section_id for breed row ---
    String? sectionIdForBreed(Map<String, dynamic> row) {
      final directSectionId = (row['section_id'] ?? '').toString().trim();
      if (directSectionId.isNotEmpty) return directSectionId;

      final sectionIds = row['section_ids'];
      if (sectionIds is Set<String>) {
        final ids = sectionIds.where((id) => id.trim().isNotEmpty).toList();
        if (ids.length == 1) return ids.first;
      }

      if (sectionIds is Iterable) {
        final ids = sectionIds
            .map((id) => id.toString().trim())
            .where((id) => id.isNotEmpty)
            .toList();
        if (ids.length == 1) return ids.first;
      }

      return null;
    }

    final sectionId = sectionIdForBreed(breed);

    if (sectionId == null || sectionId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not determine the show letter for this breed row.'),
          ),
        );
      }
      return false;
    }
    // --- END: Determine usable section_id for breed row ---

    final conflicts = await _loadJudgeBreedConflictsWithSectionId(breed, sectionId);
    if (!mounted) return false;

    final canAdd = await _confirmConflicts(breed, conflicts);
    if (!mounted || !canAdd) return false;

    String? overrideReason;
    final duplicateRows = _existingSameJudgeBreedRows(breed);
    if (duplicateRows.isNotEmpty) {
      overrideReason = await _requestDuplicateOverride(breed, duplicateRows);
      if (!mounted || overrideReason == null || overrideReason.trim().isEmpty) {
        return false;
      }
    }

    await supabase.rpc(
      'upsert_show_judging_assignment',
      params: {
        'p_show_id': widget.showId,
        'p_section_id': sectionId,
        'p_breed_id': breed['breed'],
        'p_variety_key': breed['variety'],
        'p_judge_id': null,
        'p_table_number': widget.tableNumber,
        'p_sort_order': widget.sortOrder + _newlyAssignedBreedKeys.length,
        'p_status': 'draft',
        'p_scope': (breed['scope'] ?? '').toString().isEmpty
            ? 'combined'
            : breed['scope'],
        'p_entry_count_actual': breed['entry_count'],
        'p_notes': overrideReason == null
            ? null
            : 'Duplicate judge/breed override: $overrideReason',
      },
    );

    if (!mounted) return false;
    setState(() {
      _addedAny = true;
      _newlyAssignedBreedKeys.add((breed['assigned_key'] ?? '').toString());
    });

    return true;
  }

  // Helper to use sectionId in judge conflict check
  Future<List<String>> _loadJudgeBreedConflictsWithSectionId(Map<String, dynamic> breed, String? sectionId) async {
    final judgeId = _currentJudgeId;
    if (judgeId == null || judgeId.isEmpty) return const <String>[];

    try {
      final result = await supabase.rpc(
        'validate_show_judge_breed_conflict',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': sectionId,
          'p_judge_id': judgeId,
          'p_breed': breed['breed'],
        },
      );

      if (result is! List) return const <String>[];

      return result.map<String>((item) {
        if (item is Map) {
          final exhibitor = (item['exhibitor_name'] ??
                  item['display_name'] ??
                  item['exhibitor_display_name'] ??
                  'Unknown exhibitor')
              .toString();
          final relationship = (item['relationship'] ??
                  item['conflict_type'] ??
                  'entry conflict')
              .toString();
          final scope = (item['scope'] ?? item['section_scope'] ?? '').toString();
          final scopeLabel = scope.isEmpty ? '' : ' • $scope';
          return '$exhibitor • $relationship$scopeLabel';
        }

        return item.toString();
      }).toList();
    } catch (_) {
      return const <String>[];
    }
  }
  // --- END: Open & Youth Pair helpers ---

  void _close() {
    Navigator.pop(context, _addedAny);
  }

  Future<List<String>> _loadJudgeBreedConflicts(Map<String, dynamic> breed) async {
    final judgeId = _currentJudgeId;
    if (judgeId == null || judgeId.isEmpty) return const <String>[];

    try {
      final result = await supabase.rpc(
        'validate_show_judge_breed_conflict',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': breed['section_id'],
          'p_judge_id': judgeId,
          'p_breed': breed['breed'],
        },
      );

      if (result is! List) return const <String>[];

      return result.map<String>((item) {
        if (item is Map) {
          final exhibitor = (item['exhibitor_name'] ??
                  item['display_name'] ??
                  item['exhibitor_display_name'] ??
                  'Unknown exhibitor')
              .toString();
          final relationship = (item['relationship'] ??
                  item['conflict_type'] ??
                  'entry conflict')
              .toString();
          final scope = (item['scope'] ?? item['section_scope'] ?? '').toString();
          final scopeLabel = scope.isEmpty ? '' : ' • $scope';
          return '$exhibitor • $relationship$scopeLabel';
        }

        return item.toString();
      }).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<bool> _confirmConflicts(
    Map<String, dynamic> breed,
    List<String> conflicts,
  ) async {
    if (conflicts.isEmpty) return true;

    final breedName = (breed['breed'] ?? 'this breed').toString();
    final judgeName = _currentJudgeName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Potential judge conflict'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$judgeName may have entries or family entries in $breedName.'),
            const SizedBox(height: 12),
            ...conflicts.take(6).map(
                  (conflict) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $conflict'),
                  ),
                ),
            if (conflicts.length > 6) Text('• +${conflicts.length - 6} more'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _addBreed(Map<String, dynamic> breed) async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      await _addBreedRow(breed);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addOpenYouthPair(
    Map<String, dynamic> breed,
    List<Map<String, dynamic>> options,
  ) async {
    if (_saving) return;

    final pair = _openYouthPairFor(breed, options);
    if (pair.isEmpty) return;

    setState(() => _saving = true);

    try {
      for (final row in pair) {
        final added = await _addBreedRow(row);
        if (!mounted || !added) break;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableLetters = _availableShowLetters;
    final selectedLetterForDropdown =
        availableLetters.contains(_selectedShowLetter) ? _selectedShowLetter : null;

    if (_selectedShowLetter != selectedLetterForDropdown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedShowLetter = selectedLetterForDropdown;
        });
        widget.onShowLetterChanged(selectedLetterForDropdown);
      });
    }

    final options = _breedOptions;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add Breeds to Table ${widget.tableNumber}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Done',
                  onPressed: _saving ? null : _close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Current judge: $_currentJudgeName',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedLetterForDropdown,
              decoration: const InputDecoration(
                labelText: 'Show Letter',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All show letters'),
                ),
                ..._availableShowLetters.map(
                  (letter) => DropdownMenuItem<String>(
                    value: letter,
                    child: Text(letter),
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() => _selectedShowLetter = value);
                      widget.onShowLetterChanged(value);
                    },
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'letter',
                  icon: Icon(Icons.sort_by_alpha),
                  label: Text('Breed'),
                ),
                ButtonSegment<String>(
                  value: 'count',
                  icon: Icon(Icons.format_list_numbered),
                  label: Text('Count'),
                ),
              ],
              selected: {_breedSortMode},
              onSelectionChanged: _saving
                  ? null
                  : (selection) {
                      final value = selection.first;
                      setState(() => _breedSortMode = value);
                      widget.onSortModeChanged(value);
                    },
            ),
            const SizedBox(height: 16),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'All available breeds have already been added to the line-up.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final breed = options[index];
                    final scope = _scopeLabelForRow(breed);
                    final label = [
                      breed['show_letter'],
                      if (scope.isNotEmpty) scope,
                      breed['breed'],
                    ].where((part) => part != null && part.toString().isNotEmpty).join(' • ');
                    final count = (breed['entry_count'] as num?)?.toInt() ?? 0;
                    final pair = _openYouthPairFor(breed, options);
                    final canAddPair = pair.length > 1;

                    return ListTile(
                      enabled: !_saving,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('$count entered'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          if (canAddPair)
                            Tooltip(
                              message: 'Add Open & Youth',
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.library_add_check_outlined),
                                onPressed: _saving
                                    ? null
                                    : () => _addOpenYouthPair(breed, options),
                              ),
                            ),
                          Tooltip(
                            message: 'Add this row',
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _saving ? null : () => _addBreed(breed),
                            ),
                          ),
                        ],
                      ),
                      onTap: _saving ? null : () => _addBreed(breed),
                    );
                  },
                ),
              ),
            if (_saving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _saving ? null : _close,
                icon: const Icon(Icons.check),
                label: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLineupCard extends StatelessWidget {
  const _EmptyLineupCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.table_chart_outlined, size: 56, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'No line-up rows yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a breed to start building the superintendent judging order.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add First Breed'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              'Unable to load line-up',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}