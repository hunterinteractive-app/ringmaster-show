// lib/screens/admin/payback_settings_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class PaybackSettingsDialog extends StatefulWidget {
  final String showId;

  const PaybackSettingsDialog({super.key, required this.showId});

  @override
  State<PaybackSettingsDialog> createState() => _PaybackSettingsDialogState();
}

class _PaybackSettingsDialogState extends State<PaybackSettingsDialog> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;

  List<_PaybackSection> _sections = [];
  String? _selectedSectionId;

  final List<_ClassPaybackRow> _classRows = [];
  final List<_SpecialMoneyRow> _specialRows = [];

  Map<String?, List<_ClassPaybackRow>> _classRowsBySection = {};
  Map<String?, List<_SpecialMoneyRow>> _specialRowsBySection = {};

  @override
  void initState() {
    super.initState();
    _loadSetup();
  }

  String? get _sectionKey => _selectedSectionId;

  _PaybackSection? get _selectedSection {
    for (final section in _sections) {
      if (_selectedSectionId == null && section.id.isEmpty) return section;
      if (section.id == _selectedSectionId) return section;
    }
    return null;
  }

  Future<void> _loadSetup({String? preferredSectionId}) async {
    setState(() => _loading = true);

    try {
      final result = await _supabase.rpc(
        'get_show_payback_setup',
        params: {'p_show_id': widget.showId},
      );

      final json = Map<String, dynamic>.from(result as Map);

      final rpcSections = (json['sections'] as List? ?? [])
          .map((e) => _PaybackSection.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (rpcSections.isEmpty) {
        final sectionRows = await _supabase
            .from('show_sections')
            .select('id, kind, letter, sort_order, is_enabled')
            .eq('show_id', widget.showId)
            .order('kind')
            .order('sort_order')
            .order('letter');

        rpcSections.addAll(
          (sectionRows as List)
              .where((e) {
                final row = Map<String, dynamic>.from(e as Map);
                return row['is_enabled'] != false;
              })
              .map(
                (e) => _PaybackSection.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              ),
        );
      }

      final sections = <_PaybackSection>[
        _PaybackSection(
          id: '',
          label: 'All Shows / Default',
          kind: null,
          letter: null,
        ),
        ...rpcSections,
      ];

      final classMap = <String?, List<_ClassPaybackRow>>{};
      final specialMap = <String?, List<_SpecialMoneyRow>>{};

      final schedules = json['schedules'] as List? ?? [];
      for (final rawSchedule in schedules) {
        final schedule = Map<String, dynamic>.from(rawSchedule);
        final sectionId = schedule['section_id']?.toString();

        final grouped = <String, _ClassPaybackRow>{};
        final scheduleSpecies = _normalizedClassSpecies(
          schedule['applies_to_species']?.toString(),
        );

        for (final rawRow in schedule['rows'] as List? ?? []) {
          final rowJson = Map<String, dynamic>.from(rawRow);

          final appliesToSpecies = rowJson.containsKey('applies_to_species')
              ? _normalizedClassSpecies(
                  rowJson['applies_to_species']?.toString(),
                )
              : scheduleSpecies;
          final minShown = (rowJson['min_shown'] as num?)?.toInt() ?? 1;
          final maxShown = (rowJson['max_shown'] as num?)?.toInt();
          final placement = (rowJson['placement'] as num?)?.toInt() ?? 1;
          final amountCents = (rowJson['amount_cents'] as num?)?.toInt() ?? 0;

          final key = '$appliesToSpecies:$minShown:${maxShown ?? 'null'}';

          grouped.putIfAbsent(
            key,
            () => _ClassPaybackRow(
              appliesToSpecies: appliesToSpecies,
              minShown: minShown,
              maxShown: maxShown,
              amountsByPlacement: {},
            ),
          );

          grouped[key]!.amountsByPlacement[placement] = amountCents;
        }

        classMap[sectionId] = grouped.values.toList()
          ..sort((a, b) {
            final minCompare = a.minShown.compareTo(b.minShown);
            if (minCompare != 0) return minCompare;

            final aMax = a.maxShown ?? 999999;
            final bMax = b.maxShown ?? 999999;
            final maxCompare = aMax.compareTo(bMax);
            if (maxCompare != 0) return maxCompare;

            return _speciesSortRank(
              a.appliesToSpecies,
            ).compareTo(_speciesSortRank(b.appliesToSpecies));
          });
      }

      final specials = json['special_money_rules'] as List? ?? [];
      for (final rawRule in specials) {
        final rule = Map<String, dynamic>.from(rawRule);
        final sectionId = rule['section_id']?.toString();

        specialMap.putIfAbsent(sectionId, () => []);
        specialMap[sectionId]!.add(_SpecialMoneyRow.fromJson(rule));
      }

      if (!mounted) return;

      setState(() {
        _sections = sections;
        final firstRealSection = sections
            .where((s) => s.id.isNotEmpty)
            .toList();
        final preferredExists =
            preferredSectionId != null &&
            sections.any((s) => s.id == preferredSectionId);
        final currentExists =
            _selectedSectionId != null &&
            sections.any((s) => s.id == _selectedSectionId);

        if (preferredExists) {
          _selectedSectionId = preferredSectionId;
        } else if (!currentExists) {
          _selectedSectionId = firstRealSection.isNotEmpty
              ? firstRealSection.first.id
              : null;
        }

        _classRowsBySection = classMap;
        _specialRowsBySection = specialMap;

        _loadSelectedSectionRows();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load payback settings: $e')),
      );
    }
  }

  void _loadSelectedSectionRows() {
    final savedClassRows = _classRowsBySection[_sectionKey];

    final classSource = savedClassRows == null || savedClassRows.isEmpty
        ? _defaultClassPaybackRows()
        : savedClassRows;

    _classRows
      ..clear()
      ..addAll(
        _normalizeClassPaybackRows(classSource).map((e) => e.copy()).toList(),
      );

    final savedSpecialRows = _specialRowsBySection[_sectionKey];

    _specialRows
      ..clear()
      ..addAll(
        _normalizeSpecialMoneyRows(
          savedSpecialRows ?? const <_SpecialMoneyRow>[],
        ),
      );
  }

  void _persistCurrentSectionRows() {
    _classRowsBySection[_sectionKey] = _classRows.map((e) => e.copy()).toList();

    _specialRowsBySection[_sectionKey] = _specialRows
        .map((e) => e.copy())
        .toList();
  }

  List<_ClassPaybackRow> _normalizeClassPaybackRows(
    List<_ClassPaybackRow> source,
  ) {
    final defaults = _defaultClassPaybackRows();
    final byRange = <String, _ClassPaybackRow>{};

    for (final row in defaults) {
      final key =
          '${row.appliesToSpecies ?? 'both'}:${row.minShown}:${row.maxShown ?? 'null'}';
      byRange[key] = row.copy();
    }

    for (final sourceRow in source) {
      for (final row in _expandClassPaybackRowForDisplay(sourceRow)) {
        final key =
            '${row.appliesToSpecies ?? 'both'}:${row.minShown}:${row.maxShown ?? 'null'}';
        byRange[key] = row.copy();
      }
    }

    final rows = byRange.values.toList()
      ..sort((a, b) {
        final minCompare = a.minShown.compareTo(b.minShown);
        if (minCompare != 0) return minCompare;

        final aMax = a.maxShown ?? 999999;
        final bMax = b.maxShown ?? 999999;
        final maxCompare = aMax.compareTo(bMax);
        if (maxCompare != 0) return maxCompare;

        return _speciesSortRank(
          a.appliesToSpecies,
        ).compareTo(_speciesSortRank(b.appliesToSpecies));
      });

    return rows;
  }

  List<_ClassPaybackRow> _expandClassPaybackRowForDisplay(
    _ClassPaybackRow row,
  ) {
    if (row.maxShown == null || row.maxShown == row.minShown) {
      return [row.copy()];
    }

    final expanded = <_ClassPaybackRow>[];

    for (var shown = row.minShown; shown <= row.maxShown!; shown++) {
      final amounts = <int, int>{};
      for (final entry in row.amountsByPlacement.entries) {
        if (entry.key <= shown) {
          amounts[entry.key] = entry.value;
        }
      }

      expanded.add(
        _ClassPaybackRow(
          appliesToSpecies: row.appliesToSpecies,
          minShown: shown,
          maxShown: shown,
          amountsByPlacement: amounts,
        ),
      );
    }

    return expanded;
  }

  Future<void> _saveCurrentSection() async {
    _persistCurrentSectionRows();

    setState(() => _saving = true);

    try {
      await _supabase.rpc(
        'save_show_payback_schedule',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': _selectedSectionId,
          'p_rows': _classRows
              .where((r) => r.hasAnyAmount)
              .expand((r) => r.toRpcRows())
              .toList(),
        },
      );

      await _supabase.rpc(
        'save_show_special_money_rules',
        params: {
          'p_show_id': widget.showId,
          'p_section_id': _selectedSectionId,
          'p_rules': _specialRows
              .where((r) => r.awardCode.trim().isNotEmpty && r.amountCents > 0)
              .map((r) => r.toJson())
              .toList(),
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved paybacks for ${_selectedSection?.label ?? 'selected show'}.',
          ),
        ),
      );

      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save payback settings: $e')),
      );
    }
  }

  Future<void> _copyFromAnotherSection() async {
    if (_sections.length < 2) return;

    final fromSectionId = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Copy paybacks from'),
          children: _sections
              .where((s) => s.id != (_selectedSectionId ?? ''))
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(s.id),
                  child: Text(s.label),
                ),
              )
              .toList(),
        );
      },
    );

    if (fromSectionId == null) return;

    setState(() => _saving = true);

    try {
      await _supabase.rpc(
        'copy_show_payback_settings',
        params: {
          'p_show_id': widget.showId,
          'p_from_section_id': fromSectionId.isEmpty ? null : fromSectionId,
          'p_to_section_id': _selectedSectionId,
        },
      );

      await _loadSetup(preferredSectionId: _selectedSectionId);

      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payback settings copied.')));
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to copy payback settings: $e')),
      );
    }
  }

  void _changeSection(String? sectionId) {
    if (sectionId == _selectedSectionId) return;

    setState(() {
      _persistCurrentSectionRows();
      _selectedSectionId = sectionId;
      _loadSelectedSectionRows();
    });
  }

  String _moneyFromCents(int cents) {
    return (cents / 100).toStringAsFixed(2);
  }

  int _centsFromMoney(String value) {
    final cleaned = value.replaceAll('\$', '').trim();
    if (cleaned.isEmpty) return 0;
    final parsed = double.tryParse(cleaned);
    if (parsed == null) return 0;
    return (parsed * 100).round();
  }

  TextStyle get _onPurpleHeaderStyle => const TextStyle(
    color: AppColors.headerForeground,
    fontWeight: FontWeight.w800,
  );

  TextStyle get _onPurpleBodyStyle => TextStyle(
    color: AppColors.headerForeground.withValues(alpha: .9),
    fontWeight: FontWeight.w600,
  );

  Widget _surfaceTextScope({required Widget child}) {
    return AppTheme.surfaceTextScope(context, child: child);
  }

  DataColumn _onPurpleDataColumn(String label) {
    return DataColumn(label: Text(label, style: _onPurpleHeaderStyle));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Payback Settings'),
      content: AppTheme.gradientTextScope(
        context,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.90,
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          child: SizedBox(
            width: 980,
            height: 680,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionSelector(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              TabBar(
                                labelColor: AppColors.headerForeground,
                                unselectedLabelColor: AppColors.headerForeground
                                    .withValues(alpha: .72),
                                indicatorColor: AppColors.headerForeground,
                                dividerColor: AppColors.headerForeground
                                    .withValues(alpha: .3),
                                tabs: const [
                                  Tab(text: 'Class Payback Schedule'),
                                  Tab(text: 'Special Money'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildClassScheduleTab(),
                                    _buildSpecialMoneyTab(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _saveCurrentSection,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildSectionSelector() {
    return Row(
      children: [
        Expanded(
          child: _surfaceTextScope(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedSectionId ?? '',
              dropdownColor: AppColors.surface,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'Show Letter',
                border: OutlineInputBorder(),
              ),
              items: _sections
                  .map(
                    (s) => DropdownMenuItem<String>(
                      value: s.id,
                      child: Text(s.label),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => _changeSection(
                      value == null || value.isEmpty ? null : value,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _saving || _sections.length < 2
              ? null
              : _copyFromAnotherSection,
          icon: const Icon(Icons.copy),
          label: const Text('Copy from...'),
        ),
      ],
    );
  }

  void _ensureClassCounterpartRow(_ClassPaybackRow row) {
    final species = row.appliesToSpecies;
    if (species != 'rabbit' && species != 'cavy') return;

    final counterpartSpecies = species == 'rabbit' ? 'cavy' : 'rabbit';
    final alreadyExists = _classRows.any(
      (existing) =>
          existing.appliesToSpecies == counterpartSpecies &&
          existing.minShown == row.minShown &&
          existing.maxShown == row.maxShown,
    );

    if (alreadyExists) return;

    final newAmounts = <int, int>{};
    for (var placement = 1; placement <= row.maxPayingPlaces; placement++) {
      newAmounts[placement] = 0;
    }

    _classRows.add(
      _ClassPaybackRow(
        appliesToSpecies: counterpartSpecies,
        minShown: row.minShown,
        maxShown: row.maxShown,
        amountsByPlacement: newAmounts,
      ),
    );

    _classRows.sort(_compareClassPaybackRows);
  }

  int _compareClassPaybackRows(_ClassPaybackRow a, _ClassPaybackRow b) {
    final minCompare = a.minShown.compareTo(b.minShown);
    if (minCompare != 0) return minCompare;

    final aMax = a.maxShown ?? 999999;
    final bMax = b.maxShown ?? 999999;
    final maxCompare = aMax.compareTo(bMax);
    if (maxCompare != 0) return maxCompare;

    return _speciesSortRank(
      a.appliesToSpecies,
    ).compareTo(_speciesSortRank(b.appliesToSpecies));
  }

  int _speciesSortRank(String? species) {
    switch (species) {
      case 'rabbit':
        return 0;
      case 'cavy':
        return 1;
      default:
        return 2;
    }
  }

  int _classPlacementColumnCount(List<_ClassPaybackRow> rows) {
    var maxPlacement = 5;

    for (final row in rows) {
      for (final placement in row.amountsByPlacement.keys) {
        if (placement > maxPlacement) maxPlacement = placement;
      }
    }

    return maxPlacement;
  }

  void _addClassPlacementColumn() {
    final rows = _classRows.isEmpty ? _defaultClassPaybackRows() : _classRows;
    final nextPlacement = _classPlacementColumnCount(rows) + 1;
    final nextOpenEndedShown = nextPlacement + 1;

    setState(() {
      if (_classRows.isEmpty) {
        _classRows.addAll(_defaultClassPaybackRows().map((e) => e.copy()));
      }

      for (final row in _classRows) {
        row.maxShown ??= row.minShown;
      }

      for (final species in const ['rabbit', 'cavy']) {
        final hasNextOpenEndedRow = _classRows.any(
          (row) =>
              row.appliesToSpecies == species &&
              row.minShown == nextOpenEndedShown &&
              row.maxShown == null,
        );

        if (!hasNextOpenEndedRow) {
          final amounts = <int, int>{};
          for (var placement = 1; placement <= nextPlacement; placement++) {
            amounts[placement] = 0;
          }

          _classRows.add(
            _ClassPaybackRow(
              appliesToSpecies: species,
              minShown: nextOpenEndedShown,
              maxShown: null,
              amountsByPlacement: amounts,
            ),
          );
        }
      }

      for (final row in _classRows) {
        if (_classPlacementEnabled(row, nextPlacement)) {
          row.amountsByPlacement.putIfAbsent(nextPlacement, () => 0);
        }
      }

      _classRows.sort(_compareClassPaybackRows);
    });
  }

  bool _classPlacementEnabled(_ClassPaybackRow row, int placement) {
    if (row.maxShown == null) return true;
    return placement <= row.maxShown!;
  }

  String _placementHeaderLabel(int placement) {
    final suffix = _ordinalSuffix(placement);
    return '$placement$suffix';
  }

  String _ordinalSuffix(int number) {
    if (number % 100 >= 11 && number % 100 <= 13) return 'th';
    switch (number % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  Widget _buildClassScheduleTab() {
    final rowsForDisplay = _classRows.isEmpty
        ? _defaultClassPaybackRows()
        : _classRows;
    final placementColumnCount = _classPlacementColumnCount(rowsForDisplay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fill the payback amounts for each placement. Rabbit and cavy schedules can be different. The 6+ row applies when six or more are shown in the class.',
          style: _onPurpleBodyStyle,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addClassPlacementColumn,
            icon: const Icon(Icons.add),
            label: Text(
              'Add ${_placementHeaderLabel(placementColumnCount + 1)} placement / shown row',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 58,
                dataRowMaxHeight: 66,
                columnSpacing: 8,
                columns: [
                  _onPurpleDataColumn('Species'),
                  _onPurpleDataColumn('Shown'),
                  ...List.generate(
                    placementColumnCount,
                    (index) =>
                        _onPurpleDataColumn(_placementHeaderLabel(index + 1)),
                  ),
                ],
                rows: rowsForDisplay.map((row) {
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 112,
                          child: _surfaceTextScope(
                            child: DropdownButtonFormField<String>(
                              initialValue: row.appliesToSpecies == 'cavy'
                                  ? 'cavy'
                                  : 'rabbit',
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w700,
                              ),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                              ),
                              items: const [
                                DropdownMenuItem<String>(
                                  value: 'rabbit',
                                  child: Text(
                                    'Rabbit',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'cavy',
                                  child: Text(
                                    'Cavy',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  if (_classRows.isEmpty) {
                                    _classRows.addAll(
                                      _defaultClassPaybackRows().map(
                                        (e) => e.copy(),
                                      ),
                                    );
                                  }
                                  row.appliesToSpecies = value;
                                  _ensureClassCounterpartRow(row);
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 50,
                          child: Text(
                            row.maxShown == null
                                ? '${row.minShown}+'
                                : row.minShown == row.maxShown
                                ? row.minShown.toString()
                                : '${row.minShown}-${row.maxShown}',
                            style: _onPurpleBodyStyle,
                          ),
                        ),
                      ),
                      ...List.generate(placementColumnCount, (i) {
                        final placement = i + 1;
                        final enabled = _classPlacementEnabled(row, placement);

                        return DataCell(
                          SizedBox(
                            width: 78,
                            child: _surfaceTextScope(
                              child: TextFormField(
                                key: ValueKey(
                                  'class-${row.appliesToSpecies ?? 'both'}-${row.minShown}-${row.maxShown}-$placement-${row.amountsByPlacement[placement] ?? 0}',
                                ),
                                enabled: enabled,
                                initialValue: enabled
                                    ? _moneyFromCents(
                                        row.amountsByPlacement[placement] ?? 0,
                                      )
                                    : '',
                                style: const TextStyle(color: AppColors.text),
                                decoration: InputDecoration(
                                  prefixText: '\$',
                                  hintText: enabled ? '0.00' : '—',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (value) {
                                  if (_classRows.isEmpty) {
                                    setState(() {
                                      _classRows.addAll(
                                        _defaultClassPaybackRows().map(
                                          (e) => e.copy(),
                                        ),
                                      );
                                    });
                                  }
                                  row.amountsByPlacement[placement] =
                                      _centsFromMoney(value);
                                },
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialMoneyTab() {
    final rows = _specialRows.isEmpty
        ? _defaultSpecialMoneyRows()
        : _specialRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fill the special money amounts for each award. These are saved by the selected show letter above.',
          style: _onPurpleBodyStyle,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 68,
                dataRowMaxHeight: 78,
                columnSpacing: 12,
                columns: [
                  _onPurpleDataColumn('Award'),
                  _onPurpleDataColumn('Label'),
                  _onPurpleDataColumn('Species'),
                  _onPurpleDataColumn('Amount'),
                  _onPurpleDataColumn('Enabled'),
                  _onPurpleDataColumn('Remove'),
                ],
                rows: rows.asMap().entries.map((entry) {
                  final index = entry.key;
                  final row = entry.value;

                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: _surfaceTextScope(
                            child: TextFormField(
                              key: ValueKey(
                                'special-code-$index-${row.awardCode}',
                              ),
                              initialValue: row.awardCode,
                              enabled: !row.isBuiltIn,
                              style: const TextStyle(color: AppColors.text),
                              decoration: const InputDecoration(
                                hintText: 'BOB',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              textCapitalization: TextCapitalization.characters,
                              onChanged: (value) {
                                row.awardCode = value.trim().toUpperCase();
                                _ensureSpecialRowTracked(row);
                              },
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 260,
                          child: _surfaceTextScope(
                            child: TextFormField(
                              key: ValueKey(
                                'special-label-$index-${row.awardLabel}',
                              ),
                              initialValue: row.awardLabel,
                              enabled: !row.isBuiltIn,
                              style: const TextStyle(color: AppColors.text),
                              decoration: const InputDecoration(
                                hintText: 'Best of Breed',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) {
                                row.awardLabel = value.trim();
                                _ensureSpecialRowTracked(row);
                              },
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 130,
                          child: _surfaceTextScope(
                            child: DropdownButtonFormField<String?>(
                              initialValue: row.appliesToSpecies,
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Both'),
                                ),
                                DropdownMenuItem<String?>(
                                  value: 'rabbit',
                                  child: Text('Rabbit'),
                                ),
                                DropdownMenuItem<String?>(
                                  value: 'cavy',
                                  child: Text('Cavy'),
                                ),
                              ],
                              onChanged: row.isBuiltIn
                                  ? null
                                  : (value) {
                                      setState(() {
                                        row.appliesToSpecies = value;
                                        _ensureSpecialRowTracked(row);
                                      });
                                    },
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: _surfaceTextScope(
                            child: TextFormField(
                              key: ValueKey(
                                'special-amount-$index-${row.amountCents}',
                              ),
                              initialValue: _moneyFromCents(row.amountCents),
                              style: const TextStyle(color: AppColors.text),
                              decoration: const InputDecoration(
                                prefixText: '\$',
                                hintText: '0.00',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (value) {
                                setState(() {
                                  row.amountCents = _centsFromMoney(value);
                                  row.isEnabled = row.amountCents > 0;
                                  _ensureSpecialRowTracked(row);
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        IconButton(
                          tooltip: row.isEnabled ? 'Enabled' : 'Disabled',
                          onPressed: row.amountCents <= 0
                              ? null
                              : () {
                                  setState(() {
                                    row.isEnabled = !row.isEnabled;
                                    _ensureSpecialRowTracked(row);
                                  });
                                },
                          icon: Icon(
                            row.isEnabled
                                ? Icons.check_circle
                                : Icons.remove_circle_outline,
                          ),
                        ),
                      ),
                      DataCell(
                        IconButton(
                          tooltip: 'Remove rule',
                          onPressed: row.isBuiltIn
                              ? null
                              : () {
                                  setState(() {
                                    _ensureSpecialRowTracked(row);
                                    _specialRows.remove(row);
                                  });
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _ensureSpecialRowTracked(_SpecialMoneyRow row) {
    if (!_specialRows.contains(row)) {
      _specialRows.add(row);
    }
  }
}

class _PaybackSection {
  final String id;
  final String label;
  final String? kind;
  final String? letter;

  _PaybackSection({
    required this.id,
    required this.label,
    this.kind,
    this.letter,
  });

  factory _PaybackSection.fromJson(Map<String, dynamic> json) {
    return _PaybackSection(
      id: json['id'].toString(),
      label: (json['label'] ?? '').toString().trim().isNotEmpty
          ? json['label'].toString()
          : _buildSectionLabel(
              json['kind']?.toString(),
              json['letter']?.toString(),
            ),
      kind: json['kind']?.toString(),
      letter: json['letter']?.toString(),
    );
  }
}

String _buildSectionLabel(String? kind, String? letter) {
  final normalizedKind = (kind ?? '').trim().toLowerCase();
  final normalizedLetter = (letter ?? '').trim();

  final kindLabel = normalizedKind == 'youth' ? 'Youth' : 'Open';

  if (normalizedLetter.isEmpty) return kindLabel;
  return '$kindLabel $normalizedLetter';
}

class _ClassPaybackRow {
  String? appliesToSpecies;
  int minShown;
  int? maxShown;
  Map<int, int> amountsByPlacement;

  _ClassPaybackRow({
    required this.appliesToSpecies,
    required this.minShown,
    required this.maxShown,
    required this.amountsByPlacement,
  });

  bool get hasAnyAmount => amountsByPlacement.values.any((v) => v > 0);

  int get maxPayingPlaces {
    if (maxShown != null) return maxShown! < 1 ? 1 : maxShown!;

    var max = 5;
    for (final placement in amountsByPlacement.keys) {
      if (placement > max) max = placement;
    }
    return max;
  }

  _ClassPaybackRow copy() {
    return _ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: minShown,
      maxShown: maxShown,
      amountsByPlacement: Map<int, int>.from(amountsByPlacement),
    );
  }

  List<Map<String, dynamic>> toRpcRows() {
    final rows = <Map<String, dynamic>>[];

    for (final entry in amountsByPlacement.entries) {
      if (entry.value <= 0) continue;

      rows.add({
        'applies_to_species': appliesToSpecies,
        'min_shown': minShown,
        'max_shown': maxShown,
        'placement': entry.key,
        'amount_cents': entry.value,
      });
    }

    return rows;
  }
}

class _SpecialMoneyRow {
  String awardCode;
  String awardLabel;
  int amountCents;
  String? appliesToSpecies;
  String? breedName;
  String? varietyName;
  bool isEnabled;

  _SpecialMoneyRow({
    required this.awardCode,
    required this.awardLabel,
    required this.amountCents,
    required this.appliesToSpecies,
    required this.breedName,
    required this.varietyName,
    required this.isEnabled,
  });

  bool get isBuiltIn {
    final code = awardCode.trim().toUpperCase();

    if (code.startsWith('COMMERCIAL_')) return true;

    return const <String>{
      'BIS',
      'RIS',
      'BD',
      'BDPB',
      'BOB',
      'BOSB',
      'BOG',
      'BOSG',
      'BOV',
      'BOSV',
    }.contains(code);
  }

  _SpecialMoneyRow copy() {
    return _SpecialMoneyRow(
      awardCode: awardCode,
      awardLabel: awardLabel,
      amountCents: amountCents,
      appliesToSpecies: appliesToSpecies,
      breedName: breedName,
      varietyName: varietyName,
      isEnabled: isEnabled,
    );
  }

  factory _SpecialMoneyRow.fromJson(Map<String, dynamic> json) {
    return _SpecialMoneyRow(
      awardCode: json['award_code']?.toString() ?? '',
      awardLabel: json['award_label']?.toString() ?? '',
      amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
      appliesToSpecies: json['applies_to_species']?.toString(),
      breedName: json['breed_name']?.toString(),
      varietyName: json['variety_name']?.toString(),
      isEnabled: ((json['amount_cents'] as num?)?.toInt() ?? 0) > 0
          ? (json['is_enabled'] as bool? ?? true)
          : false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'award_code': awardCode.trim().toUpperCase(),
      'award_label': awardLabel.trim().isEmpty
          ? awardCode.trim().toUpperCase()
          : awardLabel.trim(),
      'amount_cents': amountCents,
      'applies_to_species': appliesToSpecies,
      'breed_name': breedName,
      'variety_name': varietyName,
      'is_enabled': isEnabled,
    };
  }
}

List<_ClassPaybackRow> _defaultClassPaybackRows() {
  return [
    ..._defaultClassPaybackRowsForSpecies('rabbit'),
    ..._defaultClassPaybackRowsForSpecies('cavy'),
  ];
}

List<_ClassPaybackRow> _defaultClassPaybackRowsForSpecies(
  String appliesToSpecies,
) {
  return [
    _ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: 1,
      maxShown: 1,
      amountsByPlacement: {1: 0},
    ),
    _ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: 2,
      maxShown: 2,
      amountsByPlacement: {1: 0, 2: 0},
    ),
    _ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: 3,
      maxShown: 3,
      amountsByPlacement: {1: 0, 2: 0, 3: 0},
    ),
    _ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: 4,
      maxShown: 4,
      amountsByPlacement: {1: 0, 2: 0, 3: 0, 4: 0},
    ),
    _ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: 5,
      maxShown: 5,
      amountsByPlacement: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
    ),
    _ClassPaybackRow(
      appliesToSpecies: appliesToSpecies,
      minShown: 6,
      maxShown: null,
      amountsByPlacement: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
    ),
  ];
}

List<_SpecialMoneyRow> _defaultSpecialMoneyRows() {
  return [
    _SpecialMoneyRow(
      awardCode: 'BIS',
      awardLabel: 'Best in Show',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'RIS',
      awardLabel: 'Reserve in Show',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BD',
      awardLabel: 'Best Display',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BDPB',
      awardLabel: 'Best Display Per Breed',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOB',
      awardLabel: 'Best of Breed',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOSB',
      awardLabel: 'Best Opposite Sex of Breed',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOG',
      awardLabel: 'Best of Group',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOSG',
      awardLabel: 'Best Opposite Sex of Group',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOV',
      awardLabel: 'Best of Variety',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOSV',
      awardLabel: 'Best Opposite Sex of Variety',
      amountCents: 0,
      appliesToSpecies: 'rabbit',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    ..._defaultCommercialClassMoneyRows(),
    _SpecialMoneyRow(
      awardCode: 'BIS',
      awardLabel: 'Best in Show',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'RIS',
      awardLabel: 'Reserve in Show',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BD',
      awardLabel: 'Best Display',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BDPB',
      awardLabel: 'Best Display Per Breed',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOB',
      awardLabel: 'Best of Breed',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOSB',
      awardLabel: 'Best Opposite Sex of Breed',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOV',
      awardLabel: 'Best of Variety',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
    _SpecialMoneyRow(
      awardCode: 'BOSV',
      awardLabel: 'Best Opposite Sex of Variety',
      amountCents: 0,
      appliesToSpecies: 'cavy',
      breedName: null,
      varietyName: null,
      isEnabled: false,
    ),
  ];
}

List<_SpecialMoneyRow> _defaultCommercialClassMoneyRows() {
  const commercialClasses = <Map<String, String>>[
    {'code': 'MEAT_PEN', 'label': 'Meat Pen'},
    {'code': 'SINGLE_FRYER', 'label': 'Single Fryer'},
    {'code': 'ROASTER', 'label': 'Roaster'},
    {'code': 'STEWER', 'label': 'Stewer'},
  ];

  final rows = <_SpecialMoneyRow>[];

  for (final commercialClass in commercialClasses) {
    final classCode = commercialClass['code']!;
    final classLabel = commercialClass['label']!;

    for (var placement = 1; placement <= 5; placement++) {
      rows.add(
        _SpecialMoneyRow(
          awardCode: 'COMMERCIAL_${classCode}_$placement',
          awardLabel: '$classLabel - ${_placementLabelForDefault(placement)}',
          amountCents: 0,
          appliesToSpecies: 'rabbit',
          breedName: classLabel,
          varietyName: null,
          isEnabled: false,
        ),
      );
    }
  }

  return rows;
}

String _placementLabelForDefault(int placement) {
  if (placement % 100 >= 11 && placement % 100 <= 13) {
    return '${placement}th';
  }

  switch (placement % 10) {
    case 1:
      return '${placement}st';
    case 2:
      return '${placement}nd';
    case 3:
      return '${placement}rd';
    default:
      return '${placement}th';
  }
}

List<_SpecialMoneyRow> _normalizeSpecialMoneyRows(
  List<_SpecialMoneyRow> source,
) {
  final byKey = <String, _SpecialMoneyRow>{};

  for (final row in _defaultSpecialMoneyRows()) {
    final key =
        '${row.appliesToSpecies ?? 'both'}:${row.awardCode.trim().toUpperCase()}';
    byKey[key] = row.copy();
  }

  for (final row in source) {
    if (!row.isBuiltIn) continue;

    final copy = row.copy();
    if (copy.amountCents <= 0) {
      copy.isEnabled = false;
    }

    final key =
        '${copy.appliesToSpecies ?? 'both'}:${copy.awardCode.trim().toUpperCase()}';
    byKey[key] = copy;
  }

  final rows = byKey.values.toList()
    ..sort((a, b) {
      final speciesCompare = _specialMoneySpeciesSortRank(
        a.appliesToSpecies,
      ).compareTo(_specialMoneySpeciesSortRank(b.appliesToSpecies));
      if (speciesCompare != 0) return speciesCompare;

      final aCommercial = a.awardCode.startsWith('COMMERCIAL_');
      final bCommercial = b.awardCode.startsWith('COMMERCIAL_');
      if (aCommercial != bCommercial) return aCommercial ? 1 : -1;

      return a.awardLabel.toLowerCase().compareTo(b.awardLabel.toLowerCase());
    });

  return rows;
}

int _specialMoneySpeciesSortRank(String? species) {
  switch (species) {
    case 'rabbit':
      return 0;
    case 'cavy':
      return 1;
    default:
      return 2;
  }
}

String _normalizedClassSpecies(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == 'cavy') return 'cavy';
  return 'rabbit';
}
