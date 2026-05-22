// lib/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart

import 'package:ringmaster_show/utils/cavy/cavy_awards.dart';

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

    final allEligibleRows = <Map<String, dynamic>>[];
    final rowList = <Map<String, dynamic>>[];

    for (final section in enabledSections) {
      final sectionId = _str(section['id']);
      final showLetter = _str(section['letter']).toUpperCase();
      final sectionKind = _str(section['kind']).toUpperCase();

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

        final scratchedAt = _str(row['scratched_at']);
        final isShown = row['is_shown'] != false;
        final isDisqualified = row['is_disqualified'] == true;

        // Keep DQ / No Show / Wrong Class / Wrong Sex rows on the exhibitor report.
        // Only omit truly scratched entries.
        if (scratchedAt.isNotEmpty) continue;

        row['resolved_show_letter'] = showLetter;
        row['resolved_section_kind'] = sectionKind;

        allEligibleRows.add(row);

        final rowExhibitorId = _str(row['exhibitor_id']);
        if (rowExhibitorId == exhibitorId) {
          rowList.add(row);
        }
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
    final contextByEntryId = _buildEntryContextByShow(allEligibleRows);
    final displayPlacementByEntryId =
        _buildDisplayPlacementByEntryId(allEligibleRows);
    final pointsByEntryId =
        await _loadAnimalSweepstakesPointsByEntryId(showId, entryIds);

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

      final sectionId = _str(row['section_id']);
      final ctx = contextByEntryId['$entryId|$sectionId'];

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
        placing: _displayResultOrPlacement(row, displayPlacementByEntryId),
        classCount: ctx?.classCount,
        exhibitorCount: ctx?.exhibitorCount,
        awardsText: _formatAwards(awards),
        judgeName: judgeNamesByRef[judgeRef] ?? '',
        earnedLeg: earnedLegEntryIds.contains(entryId),
        specialtyPoints: pointsByEntryId[entryId] ?? 0,
        totalPoints: pointsByEntryId[entryId] ?? 0,
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

  Future<Map<String, int>> _loadAnimalSweepstakesPointsByEntryId(
    String showId,
    List<String> entryIds,
  ) async {
    try {
      final uniqueEntryIds = entryIds
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (uniqueEntryIds.isEmpty) return {};

      final map = <String, int>{};

      for (var i = 0; i < uniqueEntryIds.length; i += 100) {
        final chunk = uniqueEntryIds.skip(i).take(100).toList();

        final rows = await repo.supabase
            .from('sweepstakes_entry_results')
            .select('entry_id, points')
            .inFilter('entry_id', chunk);

        for (final row in List<Map<String, dynamic>>.from(rows as List)) {
          final entryId = _str(row['entry_id']);
          if (entryId.isEmpty) continue;

          final points = _toInt(row['points']);
          map[entryId] = (map[entryId] ?? 0) + points;
        }
      }

      // ignore: avoid_print
      print(
        'EXHIBITOR REPORT SWEEPSTAKES DEBUG loaded points for ${map.length} of ${uniqueEntryIds.length} entries in show $showId.',
      );

      return map;
    } catch (e) {
      // ignore: avoid_print
      print('Failed loading exhibitor sweepstakes points for show $showId: $e');
      return {};
    }
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

  Map<String, String> _buildDisplayPlacementByEntryId(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, String>{};
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final entryId = _str(row['entry_id']);
      final showLetter = _str(row['resolved_show_letter']).toUpperCase();
      final breed = _str(row['breed_name']);
      final variety = _str(row['variety_name']);
      final className = _str(row['class_name']);
      final sex = _str(row['sex']);

      if (entryId.isEmpty || showLetter.isEmpty) continue;

      final key = '$showLetter|$breed|$variety|$className|$sex';
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
    }

    for (final rowsInClass in grouped.values) {
      final classSize = rowsInClass.length;

      rowsInClass.sort((a, b) {
        final aPlacement = int.tryParse(_str(a['placement'])) ?? 999;
        final bPlacement = int.tryParse(_str(b['placement'])) ?? 999;
        final placementCompare = aPlacement.compareTo(bPlacement);
        if (placementCompare != 0) return placementCompare;

        return _str(a['tattoo']).compareTo(_str(b['tattoo']));
      });

      for (var i = 0; i < rowsInClass.length; i++) {
        final row = rowsInClass[i];
        final entryId = _str(row['entry_id']);
        if (entryId.isEmpty) continue;

        final storedPlacement = int.tryParse(_str(row['placement']));

        if (storedPlacement != null &&
            storedPlacement > 0 &&
            storedPlacement <= classSize) {
          result[entryId] = '$storedPlacement';
        } else {
          result[entryId] = '${i + 1}';
        }
      }
    }

    return result;
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

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();

    final text = value.toString().trim();
    if (text.isEmpty) return 0;

    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;

    final asDouble = double.tryParse(text);
    if (asDouble != null) return asDouble.round();

    return 0;
  }

  Map<String, _EntryLegContext> _buildEntryContextByShow(
    List<Map<String, dynamic>> rows,
  ) {
    final byEntryIdAndShow = <String, _EntryLegContext>{};

    for (final row in rows) {
      final entryId = _str(row['entry_id']);
      final sectionId = _str(row['section_id']);
      final showLetter = _str(row['resolved_show_letter']).toUpperCase();

      if (entryId.isEmpty || sectionId.isEmpty || showLetter.isEmpty) continue;

      final scopedRows = rows.where((e) {
        return _str(e['section_id']) == sectionId;
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
            _str(e['class_name']) == className &&
            _str(e['sex']) == sex;
      }).toList();
      final classAnimals = classRows.length;
      final classExhibitors = classRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      byEntryIdAndShow['$entryId|$sectionId'] = _EntryLegContext(
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

  String _displayResultOrPlacement(
    Map<String, dynamic> row,
    Map<String, String> displayPlacementByEntryId,
  ) {
    final entryId = _str(row['entry_id']);
    final status = _str(row['result_status']);
    final dqReason = _str(row['disqualified_reason']);
    final isDisqualified = row['is_disqualified'] == true;
    final isShown = row['is_shown'] != false;

    if (!isShown || status == 'No Show') {
      return 'No Show';
    }

    if (isDisqualified || status.startsWith('Disqualified')) {
      if (status.startsWith('Disqualified - ')) return status;
      if (dqReason.isNotEmpty) return 'Disqualified - $dqReason';
      return 'Disqualified';
    }

    if (status == 'Unworthy of Award') {
      return 'Unworthy of Award';
    }

    return displayPlacementByEntryId[entryId] ?? _str(row['placement']);
  }

  String _formatAwards(Set<String> awards) {
    if (awards.isEmpty) return '';

    const preferredOrder = [
      'BIS',
      'BEST_IN_SHOW',
      'RIS',
      'RESERVE_IN_SHOW',
      'HM',
      'BOB',
      'BOSB',
      'BOS',
      'BJB',
      'BIB',
      'BSB',
      'BOG',
      'BOSG',
      'BOV',
      'BOSV',
      'BJV',
      'BIV',
      'BSV',
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

    return normalized.map((award) {
      switch (award) {
        case 'BEST_IN_SHOW':
          return 'Best In Show';
        case 'RESERVE_IN_SHOW':
          return 'Reserve In Show';
        case 'BEST_6_CLASS':
          return 'Best 6-Class';
        case 'BEST_4_CLASS':
          return 'Best 4-Class';
        default:
          return cavyAwardLabels[award] ?? award;
      }
    }).join(', ');
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