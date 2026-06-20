import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'qr_results_entry_screen.dart';

final supabase = Supabase.instance.client;

class TableQrQueueScreen extends StatefulWidget {
  final String showId;
  final String tableNumber;
  final String token;

  const TableQrQueueScreen({
    super.key,
    required this.showId,
    required this.tableNumber,
    required this.token,
  });

  @override
  State<TableQrQueueScreen> createState() => _TableQrQueueScreenState();
}

class _TableQrQueueScreenState extends State<TableQrQueueScreen> {
  bool _loading = true;
  String? _msg;

  Timer? _refreshTimer;
  DateTime? _lastRefreshedAt;
  bool _autoAdvancing = false;

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _loading) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _msg = null;
      });
    }

    try {
      final result = await supabase.rpc(
        'get_table_results_queue',
        params: {
          'p_show_id': widget.showId,
          'p_table_number': widget.tableNumber,
          'p_token': widget.token,
        },
      );

      _rows = (result as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      await _enrichCoopRanges();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastRefreshedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) {
          _msg = e.toString();
        }
      });
    }
  }

  // --- Coop range helpers ---

  int _coopNumberValue(String value) {
    final match = RegExp(r'(\d+)$').firstMatch(value.trim());
    return match == null ? 999999 : int.tryParse(match.group(1)!) ?? 999999;
  }

  String _coopPrefix(String value) {
    return value.replaceAll(RegExp(r'\d+$'), '').trim().toUpperCase();
  }

  int _compareCoopNumbers(String a, String b) {
    final prefixCompare = _coopPrefix(a).compareTo(_coopPrefix(b));
    if (prefixCompare != 0) return prefixCompare;
    return _coopNumberValue(a).compareTo(_coopNumberValue(b));
  }

  Future<void> _enrichCoopRanges() async {
    if (_rows.isEmpty) return;

    final showRow = await supabase
        .from('shows')
        .select('coop_numbering_mode')
        .eq('id', widget.showId)
        .maybeSingle();

    final coopMode =
        (showRow?['coop_numbering_mode'] ?? 'separate')
            .toString()
            .trim()
            .toLowerCase();

    final entriesBySectionAndBreed =
        <String, List<Map<String, dynamic>>>{};
    final allEntryIds = <String>{};

    final sectionIds = _rows
        .map((row) => (row['section_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final sectionId in sectionIds) {
      final result = await supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': sectionId,
        },
      );

      final rows = (result as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      for (final entry in rows) {
        final entryId =
            (entry['entry_id'] ?? entry['id'] ?? '').toString().trim();
        final breed =
            (entry['breed'] ?? entry['breed_name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        if (entryId.isEmpty || breed.isEmpty) continue;

        allEntryIds.add(entryId);
        entriesBySectionAndBreed
            .putIfAbsent('$sectionId|$breed', () => [])
            .add(entry);
      }
    }

    final animalIdByEntryId = <String, String>{};
    final entryIds = allEntryIds.toList();

    for (var i = 0; i < entryIds.length; i += 100) {
      final chunk = entryIds.skip(i).take(100).toList();
      if (chunk.isEmpty) continue;

      final rows = await supabase
          .from('entries')
          .select('id,animal_id')
          .inFilter('id', chunk);

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final entryId = (row['id'] ?? '').toString().trim();
        final animalId = (row['animal_id'] ?? '').toString().trim();
        if (entryId.isNotEmpty && animalId.isNotEmpty) {
          animalIdByEntryId[entryId] = animalId;
        }
      }
    }

    final animalIds = animalIdByEntryId.values.toSet().toList();
    final coopByAnimalAndScope = <String, String>{};

    for (var i = 0; i < animalIds.length; i += 100) {
      final chunk = animalIds.skip(i).take(100).toList();
      if (chunk.isEmpty) continue;

      final rows = await supabase
          .from('show_animal_coop_numbers')
          .select('animal_id,scope,coop_number')
          .eq('show_id', widget.showId)
          .inFilter('animal_id', chunk);

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final animalId = (row['animal_id'] ?? '').toString().trim();
        final scope = (row['scope'] ?? '').toString().trim().toLowerCase();
        final coopNumber = (row['coop_number'] ?? '').toString().trim();
        if (animalId.isEmpty || scope.isEmpty || coopNumber.isEmpty) continue;
        coopByAnimalAndScope['$animalId|$scope'] = coopNumber;
      }
    }

    for (final queueRow in _rows) {
      final sectionId = (queueRow['section_id'] ?? '').toString().trim();
      final breed = (queueRow['breed'] ?? '').toString().trim().toLowerCase();
      final sectionKind =
          (queueRow['section_kind'] ?? 'open')
              .toString()
              .trim()
              .toLowerCase();
      final scope = coopMode == 'combined' ? 'all' : sectionKind;

      final entries = entriesBySectionAndBreed['$sectionId|$breed'] ?? const [];
      final coopNumbers = <String>{};

      for (final entry in entries) {
        final entryId =
            (entry['entry_id'] ?? entry['id'] ?? '').toString().trim();
        final animalId = animalIdByEntryId[entryId] ?? '';
        if (animalId.isEmpty) continue;

        final coopNumber = coopByAnimalAndScope['$animalId|$scope'];
        if (coopNumber != null && coopNumber.isNotEmpty) {
          coopNumbers.add(coopNumber);
        }
      }

      final sorted = coopNumbers.toList()..sort(_compareCoopNumbers);
      queueRow['_coop_count'] = sorted.length;

      if (sorted.isEmpty) {
        queueRow['_coop_range'] = '';
      } else if (sorted.length == 1) {
        queueRow['_coop_range'] = sorted.first;
      } else {
        queueRow['_coop_range'] = '${sorted.first}–${sorted.last}';
      }
    }
  }

  // --- end coop range helpers ---

  Future<void> _openBreed(
    Map<String, dynamic> row, {
    bool autoAdvanceWhenComplete = true,
  }) async {
    final assignmentId = (row['assignment_id'] ?? '').toString();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrResultsEntryScreen(
          showId: widget.showId,
          sectionId: (row['section_id'] ?? '').toString(),
          breedId: (row['breed'] ?? '').toString(),
          token: widget.token,
        ),
      ),
    );

    if (!mounted) return;
    await _load(silent: true);

    if (!mounted || !autoAdvanceWhenComplete || _autoAdvancing) return;

    Map<String, dynamic>? updatedRow;
    for (final current in _rows) {
      if ((current['assignment_id'] ?? '').toString() == assignmentId) {
        updatedRow = current;
        break;
      }
    }

    if (updatedRow == null || !_isComplete(updatedRow)) return;

    final next = _nextIncompleteRow();
    if (next == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Table queue complete.')),
      );
      return;
    }

    _autoAdvancing = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Breed complete. Opening next breed...')),
    );

    await Future<void>.delayed(const Duration(milliseconds: 650));

    if (!mounted) return;
    _autoAdvancing = false;
    await _openBreed(next);
  }

  String _sectionLabel(Map<String, dynamic> row) {
    final kind = (row['section_kind'] ?? '').toString();
    final letter = (row['show_letter'] ?? '').toString();

    if (kind.isEmpty) return letter;

    final label = kind.toLowerCase() == 'youth' ? 'Youth' : 'Open';

    return '$label $letter';
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _totalEntries(Map<String, dynamic> row) {
    final total = _intValue(row['total_entries']);
    if (total > 0) return total;
    return _intValue(row['entry_count']);
  }

  int _completedEntries(Map<String, dynamic> row) {
    return _intValue(row['completed_entries']);
  }

  bool _isComplete(Map<String, dynamic> row) {
    final total = _totalEntries(row);
    if (total <= 0) return false;
    return _completedEntries(row) >= total;
  }

  bool _isInProgress(Map<String, dynamic> row) {
    final completed = _completedEntries(row);
    return completed > 0 && !_isComplete(row);
  }

  String _statusLabel(Map<String, dynamic> row) {
    if (_isComplete(row)) return 'Complete';
    if (_isInProgress(row)) return 'In Progress';
    return 'Not Started';
  }

  IconData _statusIcon(Map<String, dynamic> row) {
    if (_isComplete(row)) return Icons.check_circle;
    if (_isInProgress(row)) return Icons.pending;
    return Icons.radio_button_unchecked;
  }

  Color _statusColor(BuildContext context, Map<String, dynamic> row) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isComplete(row)) return Colors.green;
    if (_isInProgress(row)) return colorScheme.primary;
    return colorScheme.onSurfaceVariant;
  }

  Map<String, dynamic>? _nextIncompleteRow() {
    for (final row in _rows) {
      if (!_isComplete(row)) return row;
    }
    return null;
  }

  String _lastRefreshLabel() {
    final refreshed = _lastRefreshedAt;
    if (refreshed == null) return 'Auto-refreshes every 20 seconds';

    final diff = DateTime.now().difference(refreshed).inSeconds;
    if (diff < 5) return 'Updated just now';
    if (diff < 60) return 'Updated ${diff}s ago';
    return 'Updated ${DateTime.now().difference(refreshed).inMinutes}m ago';
  }

  Future<void> _openNextBreed() async {
    final next = _nextIncompleteRow();
    if (next == null) return;
    await _openBreed(next, autoAdvanceWhenComplete: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_msg != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Table Queue'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(child: Text(_msg!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Table ${widget.tableNumber} Queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_rows.where(_isComplete).length}/${_rows.length} breed${_rows.length == 1 ? '' : 's'} complete',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(_lastRefreshLabel()),
              ],
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(
                    child: Text('No breeds assigned to this table yet.'),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final row = _rows[i];

                        final count = _totalEntries(row);
                        final completed = _completedEntries(row);
                        final nextRow = _nextIncompleteRow();
                        final isNext = nextRow != null && identical(nextRow, row);
                        final statusColor = _statusColor(context, row);

                        final breed = (row['breed'] ?? '').toString();
                        final judge = (row['judge_name'] ?? '').toString();
                        final coopRange =
                            (row['_coop_range'] ?? '').toString().trim();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: statusColor.withValues(alpha: 0.12),
                              child: Icon(
                                _statusIcon(row),
                                color: statusColor,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    breed,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (isNext)
                                  const Chip(
                                    label: Text('Next'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              [
                                '${_sectionLabel(row)} • $completed/$count entered • ${_statusLabel(row)}',
                                if (coopRange.isNotEmpty) 'Coops: $coopRange',
                                'Judge: ${judge.isEmpty ? 'TBD' : judge}',
                              ].join('\n'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openBreed(
                              row,
                              autoAdvanceWhenComplete: isNext,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _nextIncompleteRow() == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openNextBreed,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Next Breed'),
            ),
    );
  }
}