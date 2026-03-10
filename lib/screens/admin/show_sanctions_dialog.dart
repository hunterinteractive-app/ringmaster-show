//lib/screens/admin/show_sanctions_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ShowSanctionsDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShowSanctionsDialog(
        showId: showId,
        showName: showName,
      ),
    );
  }
}

class _ShowSanctionsDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowSanctionsDialog({
    required this.showId,
    required this.showName,
  });

  @override
  State<_ShowSanctionsDialog> createState() => _ShowSanctionsDialogState();
}

class _ShowSanctionsDialogState extends State<_ShowSanctionsDialog> {
  static const String _table = 'show_sanctions';

  bool _loading = true;
  bool _saving = false;
  String? _msg;

  final List<_SectionColumn> _sections = [];
  final List<_SanctionRowModel> _rows = [];

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _existingRecordIds = {};
  final Map<String, bool> _useArbaByRowKey = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      await _loadSections();
      await _buildPrebuiltRows();
      await _loadSavedSanctions();

      if (!mounted) return;
      setState(() {
        _loading = false;
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
    final res = await supabase
        .from('show_sections')
        .select('id, kind, letter, display_name, sort_order, is_enabled')
        .eq('show_id', widget.showId)
        .eq('is_enabled', true);

    _sections.clear();

    final items = (res as List).cast<Map<String, dynamic>>();
    items.sort((a, b) {
      int kindRank(String k) {
        switch (k.toLowerCase()) {
          case 'open':
            return 0;
          case 'youth':
            return 1;
          default:
            return 99;
        }
      }

      final ak = (a['kind'] ?? '').toString();
      final bk = (b['kind'] ?? '').toString();

      final kr = kindRank(ak).compareTo(kindRank(bk));
      if (kr != 0) return kr;

      final aso = int.tryParse((a['sort_order'] ?? '').toString()) ?? 9999;
      final bso = int.tryParse((b['sort_order'] ?? '').toString()) ?? 9999;
      final sr = aso.compareTo(bso);
      if (sr != 0) return sr;

      final ad = _sectionDisplayName(a).toLowerCase();
      final bd = _sectionDisplayName(b).toLowerCase();
      return ad.compareTo(bd);
    });

    for (final s in items) {
      _sections.add(
        _SectionColumn(
          id: (s['id'] ?? '').toString(),
          kind: (s['kind'] ?? '').toString(),
          displayName: _sectionDisplayName(s),
        ),
      );
    }
  }

  String _sectionDisplayName(Map<String, dynamic> s) {
    final dn = (s['display_name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final letter = (s['letter'] ?? '').toString().trim();
    final kind = (s['kind'] ?? '').toString().trim();

    if (kind.isNotEmpty && letter.isNotEmpty) {
      return '${_title(kind)} $letter';
    }
    if (letter.isNotEmpty) return 'Show $letter';
    return 'Section';
  }

  String _title(String v) {
    if (v.isEmpty) return v;
    return '${v[0].toUpperCase()}${v.substring(1).toLowerCase()}';
  }

  Future<void> _buildPrebuiltRows() async {
    _rows.clear();
    _useArbaByRowKey.clear();

    _rows.add(
      const _SanctionRowModel(
        key: '__ARBA__',
        label: 'ARBA Number:',
        rowType: _SanctionRowType.arba,
        speciesRank: 0,
        rowRank: -1000,
      ),
    );

    final show = await supabase
        .from('shows')
        .select('is_single_breed_show,single_breed_id')
        .eq('id', widget.showId)
        .single();

    final isSingleBreedShow = show['is_single_breed_show'] == true;
    final singleBreedId = (show['single_breed_id'] ?? '').toString().trim();

    List<String> allowedBreedIds = [];

    if (isSingleBreedShow && singleBreedId.isNotEmpty) {
      allowedBreedIds = [singleBreedId];
    } else {
      final sb = await supabase
          .from('show_breeds')
          .select('breed_id,is_enabled')
          .eq('show_id', widget.showId);

      final sbRows = (sb as List).cast<Map<String, dynamic>>();
      if (sbRows.isNotEmpty) {
        allowedBreedIds = sbRows
            .where((r) => r['is_enabled'] == true)
            .map((r) => (r['breed_id'] ?? '').toString())
            .where((x) => x.isNotEmpty)
            .toList();
      }
    }

    late final List<dynamic> breedRes;
    if (allowedBreedIds.isEmpty) {
      breedRes = await supabase
          .from('breeds')
          .select('id,name,species,is_active')
          .eq('is_active', true)
          .order('name');
    } else {
      breedRes = await supabase
          .from('breeds')
          .select('id,name,species,is_active')
          .eq('is_active', true)
          .inFilter('id', allowedBreedIds);
    }

    final breedRows = (breedRes as List).cast<Map<String, dynamic>>();
    final temp = <_SanctionRowModel>[];

    for (final b in breedRows) {
      final name = (b['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final speciesRaw = (b['species'] ?? '').toString().trim().toLowerCase();
      final isCavy = speciesRaw.contains('cavy') || speciesRaw.contains('guinea');
      final speciesRank = isCavy ? 1 : 0;

      final row = _SanctionRowModel(
        key: 'breed::$name',
        label: name,
        rowType: _SanctionRowType.breed,
        breedName: name,
        speciesRank: speciesRank,
        rowRank: 100,
      );

      temp.add(row);
      _useArbaByRowKey[row.key] = false;
    }

    temp.sort((a, b) {
      final sp = a.speciesRank.compareTo(b.speciesRank);
      if (sp != 0) return sp;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    _rows.addAll(temp);
  }

  Future<void> _loadSavedSanctions() async {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _existingRecordIds.clear();

    final res = await supabase
        .from(_table)
        .select(
          'id,show_id,section_id,sanctioning_body,club_name,breed_name,sanction_number,notes',
        )
        .eq('show_id', widget.showId);

    final saved = (res as List).cast<Map<String, dynamic>>();

    for (final row in _rows) {
      for (final section in _sections) {
        final key = _cellKey(row.key, section.id);

        final match = saved.where((r) {
          final sectionId = (r['section_id'] ?? '').toString().trim();
          if (sectionId != section.id) return false;

          switch (row.rowType) {
            case _SanctionRowType.arba:
              return (r['sanctioning_body'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase() ==
                  'arba';
            case _SanctionRowType.breed:
              return (r['breed_name'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase() ==
                  (row.breedName ?? '').toLowerCase();
            case _SanctionRowType.club:
              return (r['club_name'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase() ==
                  (row.clubName ?? '').toLowerCase();
          }
        }).toList();

        final existing = match.isNotEmpty ? match.first : null;
        final value = existing == null
            ? ''
            : (existing['sanction_number'] ?? '').toString();

        _controllers[key] = TextEditingController(text: value);

        if (existing != null) {
          final id = (existing['id'] ?? '').toString().trim();
          if (id.isNotEmpty) {
            _existingRecordIds[key] = id;
          }
        }
      }
    }

    for (final row in _rows.where((r) => r.rowType == _SanctionRowType.breed)) {
      bool allMatchArba = true;

      for (final section in _sections) {
        final arbaKey = _cellKey('__ARBA__', section.id);
        final breedKey = _cellKey(row.key, section.id);

        final arbaValue = _controllers[arbaKey]?.text.trim() ?? '';
        final breedValue = _controllers[breedKey]?.text.trim() ?? '';

        if (arbaValue.isEmpty || breedValue != arbaValue) {
          allMatchArba = false;
          break;
        }
      }

      _useArbaByRowKey[row.key] = allMatchArba && _sections.isNotEmpty;
    }
  }

  String _cellKey(String rowKey, String sectionId) => '$rowKey|$sectionId';

  TextEditingController _controllerFor(String rowKey, String sectionId) {
    final key = _cellKey(rowKey, sectionId);
    return _controllers.putIfAbsent(key, () => TextEditingController());
  }

  Future<void> _saveAll() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      for (final row in _rows) {
        for (final section in _sections) {
          final key = _cellKey(row.key, section.id);
          final ctrl = _controllerFor(row.key, section.id);

          String value = ctrl.text.trim();

          if (row.rowType == _SanctionRowType.breed &&
              (_useArbaByRowKey[row.key] ?? false)) {
            final arbaValue = _controllerFor('__ARBA__', section.id).text.trim();
            value = arbaValue;
          }

          final existingId = _existingRecordIds[key];

          if (value.isEmpty) {
            if (existingId != null && existingId.isNotEmpty) {
              await supabase.from(_table).delete().eq('id', existingId);
              _existingRecordIds.remove(key);
            }
            continue;
          }

          final payload = <String, dynamic>{
            'show_id': widget.showId,
            'section_id': section.id,
            'sanction_number': value,
            'notes': null,
          };

          switch (row.rowType) {
            case _SanctionRowType.arba:
              payload['sanctioning_body'] = 'ARBA';
              payload['club_name'] = null;
              payload['breed_name'] = null;
              break;
            case _SanctionRowType.breed:
              payload['sanctioning_body'] = 'Breed';
              payload['club_name'] = null;
              payload['breed_name'] = row.breedName;
              break;
            case _SanctionRowType.club:
              payload['sanctioning_body'] = 'Club';
              payload['club_name'] = row.clubName;
              payload['breed_name'] = null;
              break;
          }

          if (existingId != null && existingId.isNotEmpty) {
            await supabase.from(_table).update(payload).eq('id', existingId);
          } else {
            final inserted = await supabase
                .from(_table)
                .insert(payload)
                .select('id')
                .single();

            final newId = (inserted['id'] ?? '').toString().trim();
            if (newId.isNotEmpty) {
              _existingRecordIds[key] = newId;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Saved.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  Widget _buildSpreadsheet() {
    if (_sections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No enabled show sections were found for this show.'),
        ),
      );
    }

    const firstColWidth = 260.0;
    const useArbaColWidth = 92.0;
    const dataColWidth = 132.0;
    const rowHeight = 36.0;
    const smallRowHeight = 32.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: firstColWidth +
                      useArbaColWidth +
                      (_sections.length * dataColWidth),
                ),
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: {
                    0: const FixedColumnWidth(firstColWidth),
                    1: const FixedColumnWidth(useArbaColWidth),
                    for (int i = 0; i < _sections.length; i++)
                      i + 2: const FixedColumnWidth(dataColWidth),
                  },
                  border: TableBorder.all(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey.shade100),
                      children: [
                        _headerCell('Show Name:'),
                        _headerCell('Use ARBA'),
                        ..._sections.map((s) => _headerCell(s.displayName)),
                      ],
                    ),
                    TableRow(
                      children: [
                        _labelCell(
                          'ARBA Number:',
                          height: rowHeight,
                          isBold: true,
                        ),
                        _centerCell(const SizedBox.shrink(), height: rowHeight),
                        ..._sections.map((s) {
                          final c = _controllerFor('__ARBA__', s.id);
                          return _inputCell(
                            controller: c,
                            enabled: !_saving,
                            height: rowHeight,
                            hintText: '',
                          );
                        }),
                      ],
                    ),
                    ..._rows
                        .where((r) => r.rowType != _SanctionRowType.arba)
                        .map((row) {
                      final isBreed = row.rowType == _SanctionRowType.breed;
                      final useArba = _useArbaByRowKey[row.key] ?? false;

                      return TableRow(
                        children: [
                          _labelCell(
                            row.label,
                            height: smallRowHeight,
                          ),
                          _centerCell(
                            isBreed
                                ? Checkbox(
                                    value: useArba,
                                    visualDensity: VisualDensity.compact,
                                    onChanged: _saving
                                        ? null
                                        : (v) {
                                            setState(() {
                                              _useArbaByRowKey[row.key] = v ?? false;
                                            });
                                          },
                                  )
                                : const SizedBox.shrink(),
                            height: smallRowHeight,
                          ),
                          ..._sections.map((s) {
                            final c = _controllerFor(row.key, s.id);
                            final locked = isBreed && useArba;

                            if (locked) {
                              final arbaValue =
                                  _controllerFor('__ARBA__', s.id).text.trim();
                              if (c.text != arbaValue) {
                                c.text = arbaValue;
                                c.selection = TextSelection.fromPosition(
                                  TextPosition(offset: c.text.length),
                                );
                              }
                            }

                            return _inputCell(
                              controller: c,
                              enabled: !_saving && !locked,
                              height: smallRowHeight,
                              hintText: '',
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _labelCell(
    String text, {
    required double height,
    bool isBold = false,
  }) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerCell(Widget child, {required double height}) {
    return SizedBox(
      height: height,
      child: Center(child: child),
    );
  }

  Widget _inputCell({
    required TextEditingController controller,
    required bool enabled,
    required double height,
    required String hintText,
  }) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: TextField(
          controller: controller,
          enabled: enabled,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final dialogWidth = media.width * 0.94;
    final dialogHeight = media.height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sanction Numbers — ${widget.showName}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Sections are pulled from this show only and sorted Open first, Youth last.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              if (_msg != null) ...[
                Text(
                  _msg!,
                  style: TextStyle(
                    color: _msg == 'Saved.' ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildSpreadsheet(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _saveAll,
                    child: Text(_saving ? 'Saving…' : 'Save'),
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

class _SectionColumn {
  final String id;
  final String kind;
  final String displayName;

  const _SectionColumn({
    required this.id,
    required this.kind,
    required this.displayName,
  });
}

enum _SanctionRowType {
  arba,
  breed,
  club,
}

class _SanctionRowModel {
  final String key;
  final String label;
  final _SanctionRowType rowType;
  final String? breedName;
  final String? clubName;
  final int speciesRank;
  final int rowRank;

  const _SanctionRowModel({
    required this.key,
    required this.label,
    required this.rowType,
    this.breedName,
    this.clubName,
    required this.speciesRank,
    required this.rowRank,
  });
}