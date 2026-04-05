// lib/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart

import '../../models/base/report_request.dart';
import '../../models/exhibitor/exhibitor_report_data.dart';
import '../closeout_repository.dart';
import 'legs_report_loader.dart';

class ExhibitorReportLoader {
  final CloseoutRepository repo;

  ExhibitorReportLoader(this.repo);

  Future<ExhibitorReportData> load(ReportRequest request) async {
    final showId = request.showId;
    final exhibitorId = (request.exhibitorId ?? '').trim();

    if (exhibitorId.isEmpty) {
      throw Exception(
        'ExhibitorReportLoader requires request.exhibitorId for seeded exhibitor artifacts.',
      );
    }

    final show = await repo.loadShowBasics(showId);
    final arbaDetails = await _loadArbaDetails(showId);

    final enabledSectionsRaw = await repo.supabase
        .from('show_sections')
        .select('id, kind, letter, sort_order')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .order('sort_order');

    final enabledSections =
        List<Map<String, dynamic>>.from(enabledSectionsRaw as List);

    final rowList = <Map<String, dynamic>>[];

    for (final section in enabledSections) {
      final sectionId = _str(section['id']);
      final showLetter = _str(section['letter']).toUpperCase();

      final rows = await repo.supabase.rpc(
        'report_results_entry_rows',
        params: {
          'p_show_id': showId,
          'p_section_id': sectionId,
          'p_show_letter': showLetter.isEmpty ? null : showLetter,
        },
      );

      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);

        final rowExhibitorId = _str(row['exhibitor_id']);
        if (rowExhibitorId != exhibitorId) continue;

        final scratchedAt = _str(row['scratched_at']);
        final isShown = row['is_shown'] != false;
        final isDisqualified = row['is_disqualified'] == true;

        if (!isShown || isDisqualified || scratchedAt.isNotEmpty) continue;

        row['resolved_show_letter'] = showLetter;
        row['resolved_section_kind'] = _str(section['kind']).toUpperCase();

        rowList.add(row);
      }
    }

    if (rowList.isEmpty) {
      throw Exception(
        'No shown result rows found for exhibitor_id=$exhibitorId in show_id=$showId.',
      );
    }

    final entryIds = rowList
        .map((e) => _str(e['entry_id']))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final judgeRefs = rowList
        .map((e) => _str(e['judged_by_show_judge_id']))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final awardsByEntryId = await _loadAwardsByEntryId(showId, entryIds);
    final judgeNamesByRef = await _loadJudgeNamesByShowJudgeId(judgeRefs);
    final contextByEntryId = _buildEntryContextByShow(rowList);
    final pointsByEntryId = await _loadPointsByEntryId(showId);

    final showName = _str(show['name']);
    final showDate = _formatShowDateRange(show['start_date'], show['end_date']);
    final showLocation = [
      _str(show['location_name']),
      _str(show['location_address']),
    ].where((e) => e.isNotEmpty).join(', ');

    final secretaryName = _firstNonEmpty([
      _str(arbaDetails?['secretary_name']),
      _str(show['secretary_name']),
    ]);

    final secretaryEmail = _firstNonEmpty([
      _str(arbaDetails?['secretary_email']),
      _str(show['secretary_email']),
    ]);

    rowList.sort((a, b) {
      final aLetter = _str(a['resolved_show_letter']).toUpperCase();
      final bLetter = _str(b['resolved_show_letter']).toUpperCase();
      final letterCompare = aLetter.compareTo(bLetter);
      if (letterCompare != 0) return letterCompare;

      final breedCompare =
          _str(a['breed_name']).compareTo(_str(b['breed_name']));
      if (breedCompare != 0) return breedCompare;

      final varietyCompare =
          _str(a['variety_name']).compareTo(_str(b['variety_name']));
      if (varietyCompare != 0) return varietyCompare;

      final classCompare =
          _str(a['class_name']).compareTo(_str(b['class_name']));
      if (classCompare != 0) return classCompare;

      final sexCompare = _str(a['sex']).compareTo(_str(b['sex']));
      if (sexCompare != 0) return sexCompare;

      return _str(a['tattoo']).compareTo(_str(b['tattoo']));
    });

    final first = rowList.first;

    final exhibitorName = _firstNonEmpty([
      request.exhibitorName ?? '',
      _str(first['exhibitor_showing_name']),
      [
        _str(first['exhibitor_first_name']),
        _str(first['exhibitor_last_name']),
      ].where((e) => e.isNotEmpty).join(' '),
      _str(first['exhibitor_label']),
      'Unknown Exhibitor',
    ]);

    final address1 = _str(first['exhibitor_address_line1']);
    final address2 = _str(first['exhibitor_address_line2']);
    final cityStateZip = [
      _str(first['exhibitor_city']),
      _str(first['exhibitor_state']),
      _str(first['exhibitor_zip']),
    ].where((e) => e.isNotEmpty).join(' ');

    // Use the same loader that creates the actual leg certificates.
    final earnedLegEntryIds = <String>{};

    final legsLoader = LegsReportLoader(repo);
    final legCertificates = await legsLoader.load(
      ReportRequest(
        showId: showId,
        reportName: 'legs',
        finalizeRunId: request.finalizeRunId,
        artifactId: request.artifactId,
        showName: request.showName,
        showDate: request.showDate,
        sanctionNumber: request.sanctionNumber,
        exhibitorId: exhibitorId,
        exhibitorName: request.exhibitorName,
      ),
    );

    for (final cert in legCertificates) {
      final entryId = _str(cert.entryId);
      if (entryId.isNotEmpty) {
        earnedLegEntryIds.add(entryId);
      }
    }

    final entryRows = rowList.map((row) {
      final entryId = _str(row['entry_id']);
      final judgeRef = _str(row['judged_by_show_judge_id']);
      final showLetter = _str(row['resolved_show_letter']).toUpperCase();

      final awards = (awardsByEntryId[entryId] ?? const <String>{})
          .map((e) => e.toUpperCase())
          .toSet();

      final ctx = contextByEntryId['$entryId|$showLetter'];

      final scope = _str(row['resolved_section_kind']).toUpperCase();
      final showLabel = scope.isEmpty
          ? showLetter
          : '${scope[0]}${scope.substring(1).toLowerCase()} $showLetter';

      final showSort = showLetter.isNotEmpty ? showLetter.codeUnitAt(0) : 999;

      return ExhibitorEntryRow(
        showSection: showLabel,
        showSectionSort: showSort,
        tattoo: _str(row['tattoo']),
        breed: _str(row['breed_name']),
        variety: _str(row['variety_name']),
        className: _str(row['class_name']),
        sex: _str(row['sex']),
        placing: _str(row['placement']),
        classCount: ctx?.classCount,
        exhibitorCount: ctx?.exhibitorCount,
        awardsText: _formatAwards(awards),
        judgeName: judgeNamesByRef[judgeRef] ?? '',
        earnedLeg: earnedLegEntryIds.contains(entryId),
        displayPoints: pointsByEntryId[entryId]?.displayPoints ?? 0,
        specialtyPoints: pointsByEntryId[entryId]?.specialtyPoints ?? 0,
        totalPoints: pointsByEntryId[entryId]?.totalPoints ?? 0,
      );
    }).toList();

    return ExhibitorReportData(
      exhibitorName: exhibitorName,
      exhibitorAddress: [address1, address2]
          .where((e) => e.isNotEmpty)
          .join(', '),
      exhibitorCityStateZip: cityStateZip,
      showName: showName,
      showDate: showDate,
      showLocation: showLocation,
      secretaryName: secretaryName,
      secretaryEmail: secretaryEmail,
      entries: entryRows,
    );
  }

  Future<Map<String, dynamic>?> _loadArbaDetails(String showId) async {
    try {
      final row = await repo.supabase
          .from('show_arba_report_details')
          .select('secretary_name, secretary_email')
          .eq('show_id', showId)
          .maybeSingle();

      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Set<String>>> _loadAwardsByEntryId(
    String showId,
    List<String> entryIds,
  ) async {
    if (entryIds.isEmpty) return {};

    try {
      final rows = await repo.supabase
          .from('entry_awards')
          .select('entry_id, award_code')
          .eq('show_id', showId)
          .inFilter('entry_id', entryIds);

      final map = <String, Set<String>>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final entryId = _str(row['entry_id']);
        final awardCode = _str(row['award_code']);
        if (entryId.isEmpty || awardCode.isEmpty) continue;
        map.putIfAbsent(entryId, () => <String>{}).add(awardCode);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> _loadJudgeNamesByShowJudgeId(
    List<String> rawJudgeRefs,
  ) async {
    if (rawJudgeRefs.isEmpty) return {};

    try {
      final refs =
          rawJudgeRefs.where((e) => e.trim().isNotEmpty).toSet().toList();

      final directJudgeRows = await repo.supabase
          .from('judges')
          .select('id, name, first_name, last_name')
          .inFilter('id', refs);

      final directJudgeNameById = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(directJudgeRows)) {
        final judgeId = _str(row['id']);
        final judgeName = _firstNonEmpty([
          _str(row['name']),
          [
            _str(row['first_name']),
            _str(row['last_name']),
          ].where((e) => e.isNotEmpty).join(' '),
        ]);
        if (judgeId.isNotEmpty && judgeName.isNotEmpty) {
          directJudgeNameById[judgeId] = judgeName;
        }
      }

      final unresolvedRefs =
          refs.where((ref) => !directJudgeNameById.containsKey(ref)).toList();

      final resolvedByRef = <String, String>{...directJudgeNameById};

      if (unresolvedRefs.isNotEmpty) {
        final showJudgeRows = await repo.supabase
            .from('show_judges')
            .select('id, judge_id')
            .inFilter('id', unresolvedRefs);

        final showJudgeList = List<Map<String, dynamic>>.from(showJudgeRows);

        final fallbackJudgeIds = showJudgeList
            .map((e) => _str(e['judge_id']))
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

        final fallbackJudgeNameById = <String, String>{};

        if (fallbackJudgeIds.isNotEmpty) {
          final fallbackJudgeRows = await repo.supabase
              .from('judges')
              .select('id, name, first_name, last_name')
              .inFilter('id', fallbackJudgeIds);

          for (final row
              in List<Map<String, dynamic>>.from(fallbackJudgeRows)) {
            final judgeId = _str(row['id']);
            final judgeName = _firstNonEmpty([
              _str(row['name']),
              [
                _str(row['first_name']),
                _str(row['last_name']),
              ].where((e) => e.isNotEmpty).join(' '),
            ]);
            if (judgeId.isNotEmpty && judgeName.isNotEmpty) {
              fallbackJudgeNameById[judgeId] = judgeName;
            }
          }
        }

        for (final row in showJudgeList) {
          final showJudgeId = _str(row['id']);
          final judgeId = _str(row['judge_id']);
          if (showJudgeId.isEmpty) continue;

          final judgeName = fallbackJudgeNameById[judgeId] ?? '';
          if (judgeName.isNotEmpty) {
            resolvedByRef[showJudgeId] = judgeName;
          }
        }
      }

      return resolvedByRef;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, _EntryPoints>> _loadPointsByEntryId(String showId) async {
    try {
      final rows = await repo.supabase
          .from('show_points_entries')
          .select('''
            exhibitor_id,
            points_category,
            total_points,
            metadata
          ''')
          .eq('show_id', showId);

      final map = <String, _EntryPoints>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final metadataRaw = row['metadata'];
        Map<String, dynamic> metadata = const {};

        if (metadataRaw is Map) {
          metadata = Map<String, dynamic>.from(metadataRaw);
        }

        final entryId = _str(metadata['entry_id']);
        if (entryId.isEmpty) continue;

        final pointsCategory = _str(row['points_category']).toLowerCase();
        final totalPoints = (row['total_points'] as num?)?.toInt() ?? 0;

        final current = map[entryId] ?? const _EntryPoints();

        var displayPoints = current.displayPoints;
        var specialtyPoints = current.specialtyPoints;

        if (pointsCategory.contains('specialty') ||
            pointsCategory.contains('sweepstakes_specialty') ||
            pointsCategory.contains('spec')) {
          specialtyPoints += totalPoints;
        } else {
          displayPoints += totalPoints;
        }

        map[entryId] = _EntryPoints(
          displayPoints: displayPoints,
          specialtyPoints: specialtyPoints,
        );
      }

      return map;
    } catch (_) {
      return {};
    }
  }

  Map<String, _EntryLegContext> _buildEntryContextByShow(
    List<Map<String, dynamic>> rows,
  ) {
    final byEntryIdAndShow = <String, _EntryLegContext>{};

    for (final row in rows) {
      final entryId = _str(row['entry_id']);
      final showLetter = _str(row['resolved_show_letter']).toUpperCase();
      if (entryId.isEmpty || showLetter.isEmpty) continue;

      final scopedRows = rows.where((e) {
        return _str(e['resolved_show_letter']).toUpperCase() == showLetter;
      }).toList();

      final breed = _str(row['breed_name']);
      final variety = _str(row['variety_name']);
      final groupName = _str(row['group_name']);
      final usesGroupAwards = row['uses_group_awards'] == true;
      final className = _str(row['class_name']);
      final sex = _str(row['sex']);

      final showAnimals = scopedRows.length;
      final showExhibitors = scopedRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final breedRows =
          scopedRows.where((e) => _str(e['breed_name']) == breed).toList();
      final breedAnimals = breedRows.length;
      final breedExhibitors = breedRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;
      final breedSameSexAnimals =
          breedRows.where((e) => _str(e['sex']) == sex).length;

      final varietyRows = scopedRows.where((e) {
        return _str(e['breed_name']) == breed &&
            _str(e['variety_name']) == variety;
      }).toList();
      final varietyAnimals = varietyRows.length;
      final varietyExhibitors = varietyRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;
      final varietySameSexAnimals =
          varietyRows.where((e) => _str(e['sex']) == sex).length;

      final groupRows = usesGroupAwards && groupName.isNotEmpty
          ? scopedRows.where((e) {
              return e['uses_group_awards'] == true &&
                  _str(e['group_name']) == groupName;
            }).toList()
          : <Map<String, dynamic>>[];
      final groupAnimals = groupRows.length;
      final groupExhibitors = groupRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;
      final groupSameSexAnimals =
          groupRows.where((e) => _str(e['sex']) == sex).length;

      final classRows = scopedRows.where((e) {
        return _str(e['breed_name']) == breed &&
            _str(e['variety_name']) == variety &&
            _str(e['class_name']) == className;
      }).toList();
      final classAnimals = classRows.length;
      final classExhibitors = classRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      byEntryIdAndShow['$entryId|$showLetter'] = _EntryLegContext(
        classCount: classAnimals,
        exhibitorCount: classExhibitors,
        breedAnimals: breedAnimals,
        breedExhibitors: breedExhibitors,
        breedSameSexAnimals: breedSameSexAnimals,
        varietyAnimals: varietyAnimals,
        varietyExhibitors: varietyExhibitors,
        varietySameSexAnimals: varietySameSexAnimals,
        groupAnimals: groupAnimals,
        groupExhibitors: groupExhibitors,
        groupSameSexAnimals: groupSameSexAnimals,
        classAnimals: classAnimals,
        classExhibitors: classExhibitors,
        showAnimals: showAnimals,
        showExhibitors: showExhibitors,
      );
    }

    return byEntryIdAndShow;
  }

  String _formatAwards(Set<String> awards) {
    if (awards.isEmpty) return '';

    const preferredOrder = [
      'BIS',
      'BEST_IN_SHOW',
      'RIS',
      'RESERVE_IN_SHOW',
      'BOB',
      'BOS',
      'BOSB',
      'BOG',
      'BOSG',
      'BOV',
      'BOSV',
      'BEST_6_CLASS',
      'BEST_4_CLASS',
      '1ST',
      'FIRST',
      '1',
    ];

    final normalized = awards.map((e) => e.toUpperCase()).toSet().toList();

    normalized.sort((a, b) {
      final aIndex = preferredOrder.indexOf(a);
      final bIndex = preferredOrder.indexOf(b);

      if (aIndex == -1 && bIndex == -1) return a.compareTo(b);
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    return normalized.join(', ');
  }

  String _formatShowDateRange(dynamic startDate, dynamic endDate) {
    final start = _tryParseDate(startDate);
    final end = _tryParseDate(endDate);

    if (start == null && end == null) return '';
    if (start != null && end != null) {
      return '${_fmtDate(start)} - ${_fmtDate(end)}';
    }
    return _fmtDate(start ?? end!);
  }

  String _fmtDate(DateTime value) {
    return '${value.month}/${value.day}/${value.year}';
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _str(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

class _EntryLegContext {
  final int classCount;
  final int exhibitorCount;

  final int breedAnimals;
  final int breedExhibitors;
  final int breedSameSexAnimals;

  final int varietyAnimals;
  final int varietyExhibitors;
  final int varietySameSexAnimals;

  final int groupAnimals;
  final int groupExhibitors;
  final int groupSameSexAnimals;

  final int classAnimals;
  final int classExhibitors;

  final int showAnimals;
  final int showExhibitors;

  const _EntryLegContext({
    required this.classCount,
    required this.exhibitorCount,
    required this.breedAnimals,
    required this.breedExhibitors,
    required this.breedSameSexAnimals,
    required this.varietyAnimals,
    required this.varietyExhibitors,
    required this.varietySameSexAnimals,
    required this.groupAnimals,
    required this.groupExhibitors,
    required this.groupSameSexAnimals,
    required this.classAnimals,
    required this.classExhibitors,
    required this.showAnimals,
    required this.showExhibitors,
  });
}

class _EntryPoints {
  final int displayPoints;
  final int specialtyPoints;

  const _EntryPoints({
    this.displayPoints = 0,
    this.specialtyPoints = 0,
  });

  int get totalPoints => displayPoints + specialtyPoints;
}