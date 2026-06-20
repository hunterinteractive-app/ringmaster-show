// lib/screens/admin/coop_numbers_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCoopNumbersScreen extends StatefulWidget {
  final String showId;
  final String showName;

  const AdminCoopNumbersScreen({
    super.key,
    required this.showId,
    required this.showName,
  });

  @override
  State<AdminCoopNumbersScreen> createState() =>
      _AdminCoopNumbersScreenState();
}

class _AdminCoopNumbersScreenState extends State<AdminCoopNumbersScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String _scopeMode = 'separate';
  String? _message;
  bool _messageIsError = false;
  List<_CoopAssignmentRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshFilter);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshFilter)
      ..dispose();

    for (final row in _rows) {
      row.coopController.dispose();
    }

    super.dispose();
  }

  void _refreshFilter() {
    if (mounted) setState(() {});
  }

  String _cleanError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _message = null;
      });
    }

    try {
      final show = await _supabase
          .from('shows')
          .select('coop_numbering_mode')
          .eq('id', widget.showId)
          .single();

      final mode = (show['coop_numbering_mode'] ?? 'separate').toString();

      final assignmentData = await _supabase
          .from('show_animal_coop_numbers')
          .select(
            'animal_id, scope, breed_name, coop_number, is_manual, generated_at',
          )
          .eq('show_id', widget.showId);

      final assignments = (assignmentData as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      final animalIds = assignments
          .map((row) => (row['animal_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final entryRows = <Map<String, dynamic>>[];
      for (var start = 0; start < animalIds.length; start += 200) {
        final end = start + 200 < animalIds.length
            ? start + 200
            : animalIds.length;
        final chunk = animalIds.sublist(start, end);

        final data = await _supabase
            .from('entries')
            .select(
              'animal_id, breed, variety, class_name, sex, tattoo, section_id, scratched_at',
            )
            .eq('show_id', widget.showId)
            .inFilter('animal_id', chunk);

        entryRows.addAll(
          (data as List)
              .map((row) => Map<String, dynamic>.from(row as Map)),
        );
      }

      final sectionIds = entryRows
          .map((row) => (row['section_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final sectionsById = <String, Map<String, dynamic>>{};
      for (var start = 0; start < sectionIds.length; start += 200) {
        final end = start + 200 < sectionIds.length
            ? start + 200
            : sectionIds.length;
        final chunk = sectionIds.sublist(start, end);

        final data = await _supabase
            .from('show_sections')
            .select('id, kind, letter, sort_order')
            .inFilter('id', chunk);

        for (final raw in data as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          sectionsById[(row['id'] ?? '').toString()] = row;
        }
      }

      final entriesByAnimal = <String, List<Map<String, dynamic>>>{};
      for (final entry in entryRows) {
        final animalId = (entry['animal_id'] ?? '').toString();
        if (animalId.isEmpty || entry['scratched_at'] != null) continue;
        entriesByAnimal.putIfAbsent(animalId, () => []).add(entry);
      }

      final newRows = <_CoopAssignmentRow>[];

      for (final assignment in assignments) {
        final animalId = (assignment['animal_id'] ?? '').toString();
        final scope = (assignment['scope'] ?? 'open').toString().toLowerCase();
        final animalEntries = entriesByAnimal[animalId] ?? const [];

        final scopedEntries = animalEntries.where((entry) {
          if (scope == 'all') return true;

          final section = sectionsById[(entry['section_id'] ?? '').toString()];
          final kind = (section?['kind'] ?? 'open').toString().toLowerCase();
          return kind == scope;
        }).toList();

        Map<String, dynamic>? representative;
        for (final entry in scopedEntries) {
          final className = (entry['class_name'] ?? '').toString().toLowerCase();
          if (!className.contains('fur') && !className.contains('wool')) {
            representative = entry;
            break;
          }
        }
        representative ??= scopedEntries.isEmpty ? null : scopedEntries.first;

        final sectionLabels = <Map<String, dynamic>>[];
        final seenLabels = <String>{};

        for (final entry in scopedEntries) {
          final section = sectionsById[(entry['section_id'] ?? '').toString()];
          if (section == null) continue;

          final kind = (section['kind'] ?? '').toString().toLowerCase();
          final letter = (section['letter'] ?? '').toString().trim();
          final label = scope == 'all'
              ? '${kind == 'youth' ? 'Youth' : 'Open'} $letter'.trim()
              : letter;

          if (label.isEmpty || !seenLabels.add(label)) continue;

          sectionLabels.add({
            'label': label,
            'sort_order': section['sort_order'] ?? 9999,
            'kind': kind,
          });
        }

        sectionLabels.sort((a, b) {
          final aKind = (a['kind'] ?? '').toString() == 'open' ? 0 : 1;
          final bKind = (b['kind'] ?? '').toString() == 'open' ? 0 : 1;
          final kindCompare = aKind.compareTo(bKind);
          if (kindCompare != 0) return kindCompare;

          final aSort = int.tryParse((a['sort_order'] ?? 9999).toString()) ?? 9999;
          final bSort = int.tryParse((b['sort_order'] ?? 9999).toString()) ?? 9999;
          final sortCompare = aSort.compareTo(bSort);
          if (sortCompare != 0) return sortCompare;

          return (a['label'] ?? '')
              .toString()
              .compareTo((b['label'] ?? '').toString());
        });

        newRows.add(
          _CoopAssignmentRow(
            animalId: animalId,
            scope: scope,
            breedName: (assignment['breed_name'] ??
                    representative?['breed'] ??
                    '')
                .toString(),
            coopNumber: (assignment['coop_number'] ?? '').toString(),
            variety: (representative?['variety'] ?? '').toString(),
            className: (representative?['class_name'] ?? '').toString(),
            sex: (representative?['sex'] ?? '').toString(),
            tattoo: (representative?['tattoo'] ?? '').toString(),
            showLetters: sectionLabels
                .map((row) => (row['label'] ?? '').toString())
                .join(', '),
            isManual: assignment['is_manual'] == true,
          ),
        );
      }

      newRows.sort(_compareRows);

      if (!mounted) return;

      for (final row in _rows) {
        row.coopController.dispose();
      }

      setState(() {
        _scopeMode = mode == 'combined' ? 'combined' : 'separate';
        _rows = newRows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _messageIsError = true;
        _message = 'Failed to load coop numbers: ${_cleanError(error)}';
      });
    }
  }

  int _scopeRank(String scope) {
    switch (scope) {
      case 'open':
        return 0;
      case 'youth':
        return 1;
      default:
        return 2;
    }
  }

  int _coopNumericPart(String value) {
    final match = RegExp(r'(\d+)$').firstMatch(value.trim());
    return match == null ? 999999 : int.tryParse(match.group(1)!) ?? 999999;
  }

  int _compareRows(_CoopAssignmentRow a, _CoopAssignmentRow b) {
    final scopeCompare = _scopeRank(a.scope).compareTo(_scopeRank(b.scope));
    if (scopeCompare != 0) return scopeCompare;

    final breedCompare = a.breedName.toLowerCase().compareTo(
          b.breedName.toLowerCase(),
        );
    if (breedCompare != 0) return breedCompare;

    final numberCompare = _coopNumericPart(a.coopController.text).compareTo(
          _coopNumericPart(b.coopController.text),
        );
    if (numberCompare != 0) return numberCompare;

    return a.tattoo.toLowerCase().compareTo(b.tattoo.toLowerCase());
  }

  List<_CoopAssignmentRow> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _rows;

    return _rows.where((row) {
      return row.coopController.text.toLowerCase().contains(query) ||
          row.scopeLabel.toLowerCase().contains(query) ||
          row.breedName.toLowerCase().contains(query) ||
          row.variety.toLowerCase().contains(query) ||
          row.className.toLowerCase().contains(query) ||
          row.sex.toLowerCase().contains(query) ||
          row.tattoo.toLowerCase().contains(query) ||
          row.showLetters.toLowerCase().contains(query);
    }).toList();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: Colors.red)
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _generate({required bool overwrite}) async {
    if (overwrite) {
      final confirmed = await _confirm(
        title: 'Regenerate All Coop Numbers?',
        body:
            'This will replace every current coop number, including manual edits, using the selected numbering mode.',
        confirmLabel: 'Regenerate All',
        destructive: true,
      );
      if (!confirmed) return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final result = await _supabase.rpc(
        'assign_show_coop_numbers',
        params: {
          'p_show_id': widget.showId,
          'p_scope_mode': _scopeMode,
          'p_overwrite_existing': overwrite,
        },
      );

      await _load();
      if (!mounted) return;

      setState(() {
        _busy = false;
        _messageIsError = false;
        _message = overwrite
            ? 'Regenerated ${result ?? 0} coop assignments.'
            : 'Generated ${result ?? 0} missing coop assignments.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = true;
        _message = 'Failed to generate coop numbers: ${_cleanError(error)}';
      });
    }
  }

  Future<void> _clearAll() async {
    if (_rows.isEmpty) return;

    final confirmed = await _confirm(
      title: 'Clear All Coop Numbers?',
      body:
          'This will keep every animal assignment but blank every coop number so staff can assign them manually.',
      confirmLabel: 'Clear All',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await _supabase.rpc(
        'update_show_animal_coop_numbers',
        params: {
          'p_show_id': widget.showId,
          'p_updates': _rows
              .map(
                (row) => {
                  'animal_id': row.animalId,
                  'scope': row.scope,
                  'coop_number': '',
                },
              )
              .toList(),
        },
      );

      for (final row in _rows) {
        row.coopController.clear();
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = false;
        _message = 'All coop numbers were cleared.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = true;
        _message = 'Failed to clear coop numbers: ${_cleanError(error)}';
      });
    }
  }

  List<List<_CoopAssignmentRow>> _duplicateGroups() {
    final grouped = <String, List<_CoopAssignmentRow>>{};

    for (final row in _rows) {
      final coop = row.coopController.text.trim().toUpperCase();
      if (coop.isEmpty) continue;

      final key = '${row.scope}|$coop';
      grouped.putIfAbsent(key, () => []).add(row);
    }

    return grouped.values.where((rows) => rows.length > 1).toList();
  }

  Future<bool> _confirmDuplicateSave(
    List<List<_CoopAssignmentRow>> duplicates,
  ) async {
    final lines = <String>[];

    for (final group in duplicates.take(10)) {
      final number = group.first.coopController.text.trim();
      final scope = group.first.scopeLabel;
      final animals = group
          .map((row) => '${row.breedName} ${row.tattoo}'.trim())
          .join(' • ');
      lines.add('$scope $number — $animals');
    }

    if (duplicates.length > 10) {
      lines.add('…and ${duplicates.length - 10} more duplicate groups.');
    }

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Duplicate Coop Numbers Found'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Text(
                  'Some coop numbers are assigned more than once within the same Open, Youth, or combined scope. This can be valid for shared meat pens or fryers.\n\n${lines.join('\n')}',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Review'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    final duplicates = _duplicateGroups();
    if (duplicates.isNotEmpty) {
      final continueSave = await _confirmDuplicateSave(duplicates);
      if (!continueSave) return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final result = await _supabase.rpc(
        'update_show_animal_coop_numbers',
        params: {
          'p_show_id': widget.showId,
          'p_updates': _rows
              .map(
                (row) => {
                  'animal_id': row.animalId,
                  'scope': row.scope,
                  'coop_number': row.coopController.text.trim(),
                },
              )
              .toList(),
        },
      );

      await _load();
      if (!mounted) return;

      setState(() {
        _busy = false;
        _messageIsError = false;
        _message = 'Saved ${result ?? _rows.length} coop assignments.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = true;
        _message = 'Failed to save coop numbers: ${_cleanError(error)}';
      });
    }
  }

  Widget _buildMessage() {
    if (_message == null) return const SizedBox.shrink();

    final color = _messageIsError ? Colors.red : Colors.green;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        _message!,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(_CoopAssignmentRow row) {
    final detailParts = <String>[
      if (row.variety.trim().isNotEmpty) row.variety.trim(),
      if (row.className.trim().isNotEmpty) row.className.trim(),
      if (row.sex.trim().isNotEmpty) row.sex.trim(),
      if (row.showLetters.trim().isNotEmpty) 'Shows ${row.showLetters.trim()}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 125,
              child: TextField(
                controller: row.coopController,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Coop #',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        row.breedName.isEmpty ? 'Unknown Breed' : row.breedName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: row.scope == 'youth'
                              ? Colors.purple.withValues(alpha: .10)
                              : Colors.blue.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          row.scopeLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (row.isManual)
                        const Tooltip(
                          message: 'Manually edited',
                          child: Icon(Icons.edit, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.tattoo.trim().isEmpty
                        ? 'No tattoo / ear tag'
                        : 'Tattoo / Ear #: ${row.tattoo.trim()}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (detailParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      detailParts.join(' • '),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRows = _filteredRows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coop Numbers'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.showName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _buildMessage(),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Numbering mode:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'separate',
                          label: Text('Separate Open / Youth'),
                          icon: Icon(Icons.call_split),
                        ),
                        ButtonSegment<String>(
                          value: 'combined',
                          label: Text('Intermix Open / Youth'),
                          icon: Icon(Icons.merge_type),
                        ),
                      ],
                      selected: {_scopeMode},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) {
                              setState(() => _scopeMode = selection.first);
                            },
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _generate(overwrite: false),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Generate Missing'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _generate(overwrite: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Regenerate All'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      onPressed: _busy || _rows.isEmpty ? null : _clearAll,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear All'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText:
                        'Search coop number, breed, tattoo, class, variety, or show',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${filteredRows.length} of ${_rows.length} assignments',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filteredRows.isEmpty
                      ? Center(
                          child: Text(
                            _rows.isEmpty
                                ? 'No coop assignments yet. Use Generate Missing to create them.'
                                : 'No assignments match your search.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredRows.length,
                          itemBuilder: (context, index) =>
                              _buildAssignmentCard(filteredRows[index]),
                        ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy || _rows.isEmpty ? null : _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoopAssignmentRow {
  final String animalId;
  final String scope;
  final String breedName;
  final String variety;
  final String className;
  final String sex;
  final String tattoo;
  final String showLetters;
  final bool isManual;
  final TextEditingController coopController;

  _CoopAssignmentRow({
    required this.animalId,
    required this.scope,
    required this.breedName,
    required String coopNumber,
    required this.variety,
    required this.className,
    required this.sex,
    required this.tattoo,
    required this.showLetters,
    required this.isManual,
  }) : coopController = TextEditingController(text: coopNumber);

  String get scopeLabel {
    switch (scope) {
      case 'open':
        return 'Open';
      case 'youth':
        return 'Youth';
      default:
        return 'Combined';
    }
  }
}