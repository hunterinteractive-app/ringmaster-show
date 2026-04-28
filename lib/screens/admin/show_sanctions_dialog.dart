//lib/screens/admin/show_sanctions_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';

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
  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  final List<_SectionColumn> _sections = [];
  final List<_SanctionRowModel> _rows = [];

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _existingRecordIds = {};
  final Map<String, bool> _useArbaByRowKey = {};

  int _selectedTabIndex = 0;
  String? _arbaBreedClubId;
  String? _arbaDefaultEmail;

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
      final show = await supabase
          .from('shows')
          .select('is_locked,finalized_at')
          .eq('id', widget.showId)
          .single();

      _isLocked = show['is_locked'] == true;
      _isFinalized =
          (show['finalized_at'] ?? '').toString().trim().isNotEmpty;

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

  String _normalizedClubType(Map<String, dynamic> row) {
    final rawClubType = (row['club_type'] ?? '').toString().trim().toUpperCase();
    final rawBody = (row['sanctioning_body'] ?? '').toString().trim().toUpperCase();

    if (rawClubType == 'NATIONAL BREED CLUB' ||
        rawClubType == 'NATIONAL CLUB') {
      return 'NATIONAL BREED CLUB';
    }
    if (rawClubType == 'STATE BREED CLUB') {
      return 'STATE BREED CLUB';
    }
    if (rawClubType == 'STATE CLUB') {
      return 'STATE CLUB';
    }
    if (rawClubType == 'ARBA') {
      return 'ARBA';
    }

    if (rawBody == 'NATIONAL CLUB') return 'NATIONAL BREED CLUB';
    if (rawBody == 'STATE BREED CLUB') return 'STATE BREED CLUB';
    if (rawBody == 'STATE CLUB') return 'STATE CLUB';
    if (rawBody == 'ARBA') return 'ARBA';

    return '';
  }

  _SanctionTabKind? _tabKindFromClubType(String clubType) {
    switch (clubType) {
      case 'NATIONAL BREED CLUB':
        return _SanctionTabKind.nationalBreed;
      case 'STATE BREED CLUB':
        return _SanctionTabKind.stateBreed;
      case 'STATE CLUB':
        return _SanctionTabKind.stateClub;
      default:
        return null;
    }
  }

  Future<void> _buildPrebuiltRows() async {
    _rows.clear();
    _useArbaByRowKey.clear();
    _arbaBreedClubId = null;
    _arbaDefaultEmail = null;

    _rows.add(
      const _SanctionRowModel(
        key: '__ARBA__',
        label: 'ARBA Number:',
        rowType: _SanctionRowType.arba,
        speciesRank: 0,
        rowRank: -1000,
      ),
    );

    final sectionsRes = await supabase
        .from('show_sections')
        .select(
          'id,display_name,kind,letter,is_enabled,breed_scope,allowed_breed_ids,sort_order',
        )
        .eq('show_id', widget.showId)
        .eq('is_enabled', true)
        .order('sort_order')
        .order('letter');

    final sectionRows = (sectionsRes as List).cast<Map<String, dynamic>>();

    final allBreedsRes = await supabase
        .from('breeds')
        .select('id,name,species,is_active')
        .eq('is_active', true)
        .order('name');

    final allBreedRows = (allBreedsRes as List).cast<Map<String, dynamic>>();

    final breedNameById = <String, String>{
      for (final b in allBreedRows)
        (b['id'] ?? '').toString(): (b['name'] ?? '').toString().trim(),
    };

    final speciesRankByBreedName = <String, int>{
      for (final b in allBreedRows)
        (b['name'] ?? '').toString().trim().toLowerCase():
            (((b['species'] ?? '').toString().trim().toLowerCase().contains('cavy') ||
                    (b['species'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase()
                        .contains('guinea'))
                ? 1
                : 0),
    };

    final allowedBreedNamesBySectionId = <String, Set<String>>{};
    final allSectionIds = <String>{};

    for (final section in sectionRows) {
      final sectionId = (section['id'] ?? '').toString().trim();
      if (sectionId.isEmpty) continue;

      allSectionIds.add(sectionId);

      final breedScope =
          (section['breed_scope'] ?? 'all').toString().trim().toLowerCase();

      if (breedScope == 'all') {
        allowedBreedNamesBySectionId[sectionId] = allBreedRows
            .map((b) => (b['name'] ?? '').toString().trim())
            .where((x) => x.isNotEmpty)
            .toSet();
      } else {
        final allowedIdsRaw =
            (section['allowed_breed_ids'] as List?) ?? const [];
        final allowedIds = allowedIdsRaw
            .map((x) => x.toString())
            .where((x) => x.isNotEmpty)
            .toSet();

        allowedBreedNamesBySectionId[sectionId] = allowedIds
            .map((id) => breedNameById[id] ?? '')
            .where((x) => x.isNotEmpty)
            .toSet();
      }
    }

    final clubsRes = await supabase
        .from('breed_clubs')
        .select(
          'id,sanctioning_body,club_type,club_name,breed_name,state_code,website,is_active',
        )
        .eq('is_active', true)
        .order('club_name');

    final clubRows = (clubsRes as List).cast<Map<String, dynamic>>();

    final contactsRes = await supabase
        .from('breed_club_contacts')
        .select('id,breed_club_id,email,is_primary,is_active')
        .eq('is_active', true)
        .order('is_primary', ascending: false);

    final contactRows = (contactsRes as List).cast<Map<String, dynamic>>();

    final primaryEmailByClubId = <String, String>{};
    for (final c in contactRows) {
      final clubId = (c['breed_club_id'] ?? '').toString().trim();
      final email = (c['email'] ?? '').toString().trim();
      if (clubId.isEmpty || email.isEmpty) continue;
      primaryEmailByClubId.putIfAbsent(clubId, () => email);
    }

    final rowMap = <String, _SanctionRowModel>{};

    for (final club in clubRows) {
      final clubId = (club['id'] ?? '').toString().trim();
      final clubName = (club['club_name'] ?? '').toString().trim();
      final breedName = (club['breed_name'] ?? '').toString().trim();
      final clubType = _normalizedClubType(club);

      if (clubId.isEmpty || clubName.isEmpty || clubType.isEmpty) continue;

      if (clubType == 'ARBA') {
        _arbaBreedClubId = clubId;
        _arbaDefaultEmail = primaryEmailByClubId[clubId];
        continue;
      }

      final tabKind = _tabKindFromClubType(clubType);
      if (tabKind == null) continue;

      Set<String> allowedSectionIds = {};

      if (tabKind == _SanctionTabKind.stateClub) {
        allowedSectionIds = {...allSectionIds};
      } else {
        if (breedName.isEmpty) continue;

        for (final entry in allowedBreedNamesBySectionId.entries) {
          final sectionId = entry.key;
          final allowedNames = entry.value;
          if (allowedNames.contains(breedName)) {
            allowedSectionIds.add(sectionId);
          }
        }
      }

      if (allowedSectionIds.isEmpty) continue;

      final speciesRank = speciesRankByBreedName[breedName.toLowerCase()] ?? 0;
      final dedupeKey =
          '$clubType|${clubName.toLowerCase()}|${breedName.toLowerCase()}|${(club['state_code'] ?? '').toString().trim().toUpperCase()}';

      rowMap[dedupeKey] = _SanctionRowModel(
        key: 'club::$clubId',
        label: clubName,
        rowType: _SanctionRowType.club,
        tabKind: tabKind,
        breedClubId: clubId,
        breedName: breedName.isEmpty ? null : breedName,
        clubName: clubName,
        clubType: clubType,
        defaultEmail: primaryEmailByClubId[clubId],
        stateCode: (club['state_code'] ?? '').toString().trim(),
        allowedSectionIds: allowedSectionIds,
        speciesRank: speciesRank,
        rowRank: tabKind == _SanctionTabKind.stateClub ? 300 : 200,
      );
    }

    final temp = rowMap.values.toList()
      ..sort((a, b) {
        final rank = a.rowRank.compareTo(b.rowRank);
        if (rank != 0) return rank;

        if (a.tabKind == _SanctionTabKind.stateClub &&
            b.tabKind == _SanctionTabKind.stateClub) {
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        }

        final breedCompare =
            (a.breedName ?? '').toLowerCase().compareTo((b.breedName ?? '').toLowerCase());
        if (breedCompare != 0) return breedCompare;

        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    _rows.addAll(temp);

    for (final row in temp) {
      _useArbaByRowKey[row.key] = false;
    }
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
          'id,show_id,section_id,sanctioning_body,club_name,breed_name,sanction_number,notes,breed_club_id,secretary_email,sweepstakes_email,use_arba_number',
        )
        .eq('show_id', widget.showId);

    final saved = (res as List).cast<Map<String, dynamic>>();

    for (final row in _rows) {
      for (final section in _sections) {
        if (row.rowType != _SanctionRowType.arba &&
            !row.allowedSectionIds.contains(section.id)) {
          continue;
        }

        final key = _cellKey(row.key, section.id);

        final match = saved.where((r) {
          final sectionId = (r['section_id'] ?? '').toString().trim();
          if (sectionId != section.id) return false;

          switch (row.rowType) {
            case _SanctionRowType.arba:
              return (r['sanctioning_body'] ?? '').toString().trim().toLowerCase() ==
                  'arba';
            case _SanctionRowType.groupHeader:
              return false;
            case _SanctionRowType.club:
              final savedBreedClubId = (r['breed_club_id'] ?? '').toString().trim();
              if (savedBreedClubId.isNotEmpty &&
                  savedBreedClubId == (row.breedClubId ?? '')) {
                return true;
              }

              final savedClubName =
                  (r['club_name'] ?? '').toString().trim().toLowerCase();
              final savedBreedName =
                  (r['breed_name'] ?? '').toString().trim().toLowerCase();

              return savedClubName == (row.clubName ?? '').toLowerCase() &&
                  savedBreedName == (row.breedName ?? '').toLowerCase();
          }
        }).toList();

        final existing = match.isNotEmpty ? match.first : null;
        final value =
            existing == null ? '' : (existing['sanction_number'] ?? '').toString();

        _controllers[key] = TextEditingController(text: value);

        if (existing != null) {
          final id = (existing['id'] ?? '').toString().trim();
          if (id.isNotEmpty) {
            _existingRecordIds[key] = id;
          }

          final savedUseArba = existing['use_arba_number'] == true;
          if (row.rowType == _SanctionRowType.club && savedUseArba) {
            _useArbaByRowKey[row.key] = true;
          }
        }
      }
    }

    for (final row in _rows.where((r) => r.rowType == _SanctionRowType.club)) {
      bool allMatchArba = true;
      bool sawAny = false;

      for (final section in _sections) {
        if (!row.allowedSectionIds.contains(section.id)) continue;
        sawAny = true;

        final arbaKey = _cellKey('__ARBA__', section.id);
        final rowKey = _cellKey(row.key, section.id);

        final arbaValue = _controllers[arbaKey]?.text.trim() ?? '';
        final rowValue = _controllers[rowKey]?.text.trim() ?? '';

        if (arbaValue.isEmpty || rowValue != arbaValue) {
          allMatchArba = false;
          break;
        }
      }

      if ((_useArbaByRowKey[row.key] ?? false) != true) {
        _useArbaByRowKey[row.key] = sawAny && allMatchArba;
      }
    }
  }

  String _cellKey(String rowKey, String sectionId) => '$rowKey|$sectionId';

  TextEditingController _controllerFor(String rowKey, String sectionId) {
    final key = _cellKey(rowKey, sectionId);
    return _controllers.putIfAbsent(key, () => TextEditingController());
  }

  List<_SanctionRowModel> get _visibleRows {
    final tab = _SanctionTabKind.values[_selectedTabIndex];
    final tabRows = _rows.where((r) => r.tabKind == tab).toList();

    // National Breed Clubs = flat list sorted by breed, then club
    if (tab == _SanctionTabKind.nationalBreed) {
      return tabRows
        ..sort((a, b) {
          final breedCompare = (a.breedName ?? '')
              .toLowerCase()
              .compareTo((b.breedName ?? '').toLowerCase());
          if (breedCompare != 0) return breedCompare;

          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
    }

    // State Clubs = flat alphabetical list
    if (tab == _SanctionTabKind.stateClub) {
      return tabRows
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    }

    // State Breed Clubs = grouped by breed
    final result = <_SanctionRowModel>[];
    String? currentBreed;

    final sorted = [...tabRows]
      ..sort((a, b) {
        final breedCompare = (a.breedName ?? '')
            .toLowerCase()
            .compareTo((b.breedName ?? '').toLowerCase());
        if (breedCompare != 0) return breedCompare;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    for (final row in sorted) {
      final breed = row.breedName ?? '';
      if (breed.isNotEmpty && breed != currentBreed) {
        currentBreed = breed;
        result.add(
          _SanctionRowModel(
            key: 'header::$tab::$breed',
            label: breed,
            rowType: _SanctionRowType.groupHeader,
            tabKind: tab,
            breedName: breed,
            speciesRank: row.speciesRank,
            rowRank: row.rowRank - 1,
          ),
        );
      }
      result.add(row);
    }

    return result;
  }
  Future<void> _saveAll() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);

      for (final row in _rows) {
        if (row.rowType == _SanctionRowType.groupHeader) continue;

        for (final section in _sections) {
          if (row.rowType != _SanctionRowType.arba &&
              !row.allowedSectionIds.contains(section.id)) {
            continue;
          }

          final key = _cellKey(row.key, section.id);
          final ctrl = _controllerFor(row.key, section.id);

          String value = ctrl.text.trim();

          if (row.rowType == _SanctionRowType.club &&
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
              payload['club_name'] = 'ARBA';
              payload['breed_name'] = null;
              payload['breed_club_id'] = _arbaBreedClubId;
              payload['use_arba_number'] = false;
              payload['sweepstakes_email'] = _arbaDefaultEmail;
              break;

            case _SanctionRowType.groupHeader:
              break;

            case _SanctionRowType.club:
              payload['breed_club_id'] = row.breedClubId;
              payload['club_name'] = row.clubName;
              payload['breed_name'] = row.breedName;
              payload['use_arba_number'] = _useArbaByRowKey[row.key] ?? false;
              payload['sweepstakes_email'] = row.defaultEmail;

              switch (row.tabKind) {
                case _SanctionTabKind.nationalBreed:
                  payload['sanctioning_body'] = 'NATIONAL CLUB';
                  break;
                case _SanctionTabKind.stateBreed:
                  payload['sanctioning_body'] = 'STATE BREED CLUB';
                  break;
                case _SanctionTabKind.stateClub:
                  payload['sanctioning_body'] = 'STATE CLUB';
                  break;
                case null:
                  payload['sanctioning_body'] = 'NATIONAL CLUB';
                  break;
              }
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

  Widget _buildTabs() {
    final tabs = const [
      ('National Breed Clubs', _SanctionTabKind.nationalBreed),
      ('State Breed Clubs', _SanctionTabKind.stateBreed),
      ('State Clubs', _SanctionTabKind.stateClub),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(tabs.length, (index) {
        final selected = _selectedTabIndex == index;
        return ChoiceChip(
          label: Text(tabs[index].$1),
          selected: selected,
          onSelected: _saving
              ? null
              : (_) {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                },
        );
      }),
    );
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

    const firstColWidth = 320.0;
    const useArbaColWidth = 92.0;
    const dataColWidth = 132.0;
    const rowHeight = 36.0;
    const smallRowHeight = 32.0;

    final visibleRows = _visibleRows;

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
                  minWidth:
                      firstColWidth +
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
                      decoration: BoxDecoration(
                        color: const Color(0xFF11285A).withOpacity(.08),
                      ),
                      children: [
                        _headerCell('Club / Breed / State Club'),
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
                            enabled: !_saving && !_isReadOnly,
                            height: rowHeight,
                            hintText: '',
                          );
                        }),
                      ],
                    ),
                    ...visibleRows.map((row) {
                      if (row.rowType == _SanctionRowType.groupHeader) {
                        return TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                          ),
                          children: [
                            _labelCell(
                              row.label,
                              height: smallRowHeight,
                              isBold: true,
                            ),
                            _centerCell(const SizedBox.shrink(), height: smallRowHeight),
                            ..._sections.map(
                              (_) => _centerCell(const SizedBox.shrink(), height: smallRowHeight),
                            ),
                          ],
                        );
                      }

                      final useArba = _useArbaByRowKey[row.key] ?? false;

                      return TableRow(
                        children: [
                          _labelCell(
                            row.label,
                            height: smallRowHeight,
                          ),
                          _centerCell(
                            Checkbox(
                              value: useArba,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_saving || _isReadOnly)
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _useArbaByRowKey[row.key] = v ?? false;
                                      });
                                    },
                            ),
                            height: smallRowHeight,
                          ),
                          ..._sections.map((s) {
                            final c = _controllerFor(row.key, s.id);
                            final allowedHere =
                                row.allowedSectionIds.contains(s.id);
                            final locked = useArba;

                            if (!allowedHere) {
                              return SizedBox(
                                height: smallRowHeight,
                                child: const ColoredBox(
                                  color: Color(0xFFF3F4F6),
                                ),
                              );
                            }

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
                              enabled: !_saving && !_isReadOnly && !locked,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
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
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
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
    final isMobile = media.width < 700;
    final dialogWidth = isMobile ? media.width - 16 : media.width * 0.94;
    final dialogHeight = isMobile ? media.height * 0.94 : media.height * 0.88;

    final savedMessage = _msg == 'Saved.';

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF11285A),
                Color(0xFF0B1C43),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/ringmaster_show_logo.png',
                      height: 38,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sanction Numbers — ${widget.showName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F6FB),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sections are pulled from this show only and sorted Open first, Youth last.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        _buildTabs(),
                        const SizedBox(height: 12),
                        if (_msg != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: savedMessage
                                  ? Colors.green.withOpacity(.08)
                                  : Colors.red.withOpacity(.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: savedMessage
                                    ? Colors.green.withOpacity(.25)
                                    : Colors.red.withOpacity(.25),
                              ),
                            ),
                            child: Text(
                              _msg!,
                              style: TextStyle(
                                color: savedMessage ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(.05),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: _buildSpreadsheet(),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    _saving ? null : () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFD4A623),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                onPressed: (_saving || _isReadOnly) ? null : _saveAll,
                                child: Text(_saving ? 'Saving…' : 'Save'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
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
  club,
  groupHeader,
}

enum _SanctionTabKind {
  nationalBreed,
  stateBreed,
  stateClub,
}

class _SanctionRowModel {
  final String key;
  final String label;
  final _SanctionRowType rowType;
  final _SanctionTabKind? tabKind;
  final String? breedClubId;
  final String? breedName;
  final String? clubName;
  final String? clubType;
  final String? defaultEmail;
  final String? stateCode;
  final Set<String> allowedSectionIds;
  final int speciesRank;
  final int rowRank;

  const _SanctionRowModel({
    required this.key,
    required this.label,
    required this.rowType,
    this.tabKind,
    this.breedClubId,
    this.breedName,
    this.clubName,
    this.clubType,
    this.defaultEmail,
    this.stateCode,
    this.allowedSectionIds = const {},
    required this.speciesRank,
    required this.rowRank,
  });
}