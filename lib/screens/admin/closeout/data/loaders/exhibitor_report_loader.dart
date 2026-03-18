import '../../models/base/report_request.dart';
import '../../models/exhibitor/exhibitor_report_data.dart';
import '../closeout_repository.dart';

class ExhibitorReportLoader {
  final CloseoutRepository repo;

  ExhibitorReportLoader(this.repo);

  final Map<String, int> _judgeOrderMap = {};

  Future<List<ExhibitorReportData>> load(ReportRequest request) async {
    final showId = request.showId;

    final show = await repo.loadShowBasics(showId);
    final arbaDetails = await _loadArbaDetails(showId);

    final rows = await repo.supabase
        .from('report_entry_base_v')
        .select('''
          show_id,
          entry_id,
          exhibitor_id,
          exhibitor_label,
          exhibitor_showing_name,
          exhibitor_first_name,
          exhibitor_last_name,
          exhibitor_address_line1,
          exhibitor_address_line2,
          exhibitor_city,
          exhibitor_state,
          exhibitor_zip,
          tattoo,
          breed,
          variety,
          group_name,
          uses_group_awards,
          class_name,
          sex,
          placement,
          judged_by_show_judge_id,
          is_shown,
          species
        ''')
        .eq('show_id', showId)
        .eq('is_shown', true);

    final rowList = List<Map<String, dynamic>>.from(rows);

    if (rowList.isEmpty) return const [];

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
    final contextByEntryId = _buildEntryContext(rowList);
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

    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final row in rowList) {
      final exhibitorKey = _firstNonEmpty([
        _str(row['exhibitor_id']),
        _str(row['exhibitor_label']),
        _str(row['exhibitor_showing_name']),
      ]);

      if (exhibitorKey.isEmpty) continue;
      grouped.putIfAbsent(exhibitorKey, () => []).add(row);
    }

    final reports = <ExhibitorReportData>[];

    for (final exhibitorRows in grouped.values) {
      exhibitorRows.sort((a, b) {
        final aJudgeRef = _str(a['judged_by_show_judge_id']);
        final bJudgeRef = _str(b['judged_by_show_judge_id']);

        final aSectionSort = _judgeOrderIndex(aJudgeRef);
        final bSectionSort = _judgeOrderIndex(bJudgeRef);
        if (aSectionSort != bSectionSort) {
          return aSectionSort.compareTo(bSectionSort);
        }

        final breedCompare = _str(a['breed']).compareTo(_str(b['breed']));
        if (breedCompare != 0) return breedCompare;

        final varietyCompare = _str(a['variety']).compareTo(_str(b['variety']));
        if (varietyCompare != 0) return varietyCompare;

        final classCompare =
            _str(a['class_name']).compareTo(_str(b['class_name']));
        if (classCompare != 0) return classCompare;

        final sexCompare = _str(a['sex']).compareTo(_str(b['sex']));
        if (sexCompare != 0) return sexCompare;

        return _str(a['tattoo']).compareTo(_str(b['tattoo']));
      });

      final first = exhibitorRows.first;

      final exhibitorName = _firstNonEmpty([
        _str(first['exhibitor_showing_name']),
        [
          _str(first['exhibitor_first_name']),
          _str(first['exhibitor_last_name']),
        ].where((e) => e.isNotEmpty).join(' '),
        'Unknown Exhibitor',
      ]);

      final address1 = _str(first['exhibitor_address_line1']);
      final address2 = _str(first['exhibitor_address_line2']);
      final cityStateZip = [
        _str(first['exhibitor_city']),
        _str(first['exhibitor_state']),
        _str(first['exhibitor_zip']),
      ].where((e) => e.isNotEmpty).join(' ');

      final entryRows = exhibitorRows.map((row) {
        final entryId = _str(row['entry_id']);
        final judgeRef = _str(row['judged_by_show_judge_id']);
        final awards = (awardsByEntryId[entryId] ?? const <String>{})
            .map((e) => e.toUpperCase())
            .toSet();
        final ctx = contextByEntryId[entryId];

        final showSort = _judgeOrderIndex(judgeRef);
        final showLetter = _indexToLetter(showSort);

        final primaryAwardCode = _pickPrimaryAwardCode(awards);
        final legRuleMatch = (ctx != null && primaryAwardCode.isNotEmpty)
            ? _determineLegRule(
                awardCode: primaryAwardCode,
                ctx: ctx,
              )
            : null;

        final earnedLeg = legRuleMatch != null;

        return ExhibitorEntryRow(
          showSection: showLetter,
          showSectionSort: showSort,
          tattoo: _str(row['tattoo']),
          breed: _str(row['breed']),
          variety: _str(row['variety']),
          className: _str(row['class_name']),
          sex: _str(row['sex']),
          placing: _str(row['placement']),
          classCount: ctx?.classCount,
          exhibitorCount: ctx?.exhibitorCount,
          awardsText: _formatAwards(awards),
          judgeName: judgeNamesByRef[judgeRef] ?? '',
          earnedLeg: earnedLeg,
          displayPoints: pointsByEntryId[entryId]?.displayPoints ?? 0,
          specialtyPoints: pointsByEntryId[entryId]?.specialtyPoints ?? 0,
          totalPoints: pointsByEntryId[entryId]?.totalPoints ?? 0,
        );
      }).toList();

      reports.add(
        ExhibitorReportData(
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
        ),
      );
    }

    reports.sort((a, b) => a.exhibitorName.compareTo(b.exhibitorName));
    return reports;
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

        // Current best mapping:
        // Everything goes to display unless you later confirm a specialty category.
        if (pointsCategory.contains('specialty')) {
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

  Map<String, _EntryLegContext> _buildEntryContext(List<Map<String, dynamic>> rows) {
    final byEntryId = <String, _EntryLegContext>{};

    final shownRows = rows.where((e) => e['is_shown'] == true).toList();

    final showAnimals = shownRows.length;
    final showExhibitors = shownRows
        .map((e) => _str(e['exhibitor_id']))
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;

    for (final row in shownRows) {
      final entryId = _str(row['entry_id']);
      if (entryId.isEmpty) continue;

      final breed = _str(row['breed']);
      final variety = _str(row['variety']);
      final groupName = _str(row['group_name']);
      final usesGroupAwards = row['uses_group_awards'] == true;
      final className = _str(row['class_name']);
      final sex = _str(row['sex']);

      final breedRows = shownRows.where((e) => _str(e['breed']) == breed).toList();
      final breedAnimals = breedRows.length;
      final breedExhibitors = breedRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final breedSameSexRows =
          breedRows.where((e) => _str(e['sex']) == sex).toList();
      final breedSameSexAnimals = breedSameSexRows.length;

      final varietyRows = shownRows.where((e) {
        return _str(e['breed']) == breed && _str(e['variety']) == variety;
      }).toList();
      final varietyAnimals = varietyRows.length;
      final varietyExhibitors = varietyRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      final varietySameSexRows =
          varietyRows.where((e) => _str(e['sex']) == sex).toList();
      final varietySameSexAnimals = varietySameSexRows.length;

      final groupRows = usesGroupAwards && groupName.isNotEmpty
          ? shownRows.where((e) {
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

      final groupSameSexRows =
          groupRows.where((e) => _str(e['sex']) == sex).toList();
      final groupSameSexAnimals = groupSameSexRows.length;

      final classRows = shownRows.where((e) {
        return _str(e['breed']) == breed &&
            _str(e['variety']) == variety &&
            _str(e['class_name']) == className;
      }).toList();
      final classAnimals = classRows.length;
      final classExhibitors = classRows
          .map((e) => _str(e['exhibitor_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .length;

      byEntryId[entryId] = _EntryLegContext(
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

    return byEntryId;
  }

  _LegRuleMatch? _determineLegRule({
    required String awardCode,
    required _EntryLegContext ctx,
  }) {
    final normalized = awardCode.toUpperCase();

    if ((normalized == 'BIS' || normalized == 'BEST_IN_SHOW') &&
        ctx.showAnimals >= 5 &&
        ctx.showExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 8,
        animalsCount: ctx.showAnimals,
        exhibitorsCount: ctx.showExhibitors,
      );
    }

    if ((normalized == 'RIS' || normalized == 'RESERVE_IN_SHOW') &&
        ctx.showAnimals >= 5 &&
        ctx.showExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 10,
        animalsCount: ctx.showAnimals,
        exhibitorsCount: ctx.showExhibitors,
      );
    }

    if (normalized == 'BOB' &&
        ctx.breedAnimals >= 5 &&
        ctx.breedExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 2,
        animalsCount: ctx.breedAnimals,
        exhibitorsCount: ctx.breedExhibitors,
      );
    }

    if ((normalized == 'BOSB' || normalized == 'BOS') &&
        ctx.breedSameSexAnimals >= 5 &&
        ctx.breedExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 3,
        animalsCount: ctx.breedSameSexAnimals,
        exhibitorsCount: ctx.breedExhibitors,
      );
    }

    if (normalized == 'BOG' &&
        ctx.groupAnimals >= 5 &&
        ctx.groupExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 4,
        animalsCount: ctx.groupAnimals,
        exhibitorsCount: ctx.groupExhibitors,
      );
    }

    if (normalized == 'BOSG' &&
        ctx.groupSameSexAnimals >= 5 &&
        ctx.groupExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 5,
        animalsCount: ctx.groupSameSexAnimals,
        exhibitorsCount: ctx.groupExhibitors,
      );
    }

    if (normalized == 'BOV' &&
        ctx.varietyAnimals >= 5 &&
        ctx.varietyExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 6,
        animalsCount: ctx.varietyAnimals,
        exhibitorsCount: ctx.varietyExhibitors,
      );
    }

    if (normalized == 'BOSV' &&
        ctx.varietySameSexAnimals >= 5 &&
        ctx.varietyExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 7,
        animalsCount: ctx.varietySameSexAnimals,
        exhibitorsCount: ctx.varietyExhibitors,
      );
    }

    if ((normalized == 'BEST_4_CLASS' || normalized == 'BEST_6_CLASS') &&
        ctx.classAnimals >= 5 &&
        ctx.classExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 9,
        animalsCount: ctx.classAnimals,
        exhibitorsCount: ctx.classExhibitors,
      );
    }

    if ((normalized == '1' || normalized == '1ST' || normalized == 'FIRST') &&
        ctx.classAnimals >= 5 &&
        ctx.classExhibitors >= 3) {
      return _LegRuleMatch(
        rule: 1,
        animalsCount: ctx.classAnimals,
        exhibitorsCount: ctx.classExhibitors,
      );
    }

    return null;
  }

  String _pickPrimaryAwardCode(Set<String> awards) {
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

    for (final code in preferredOrder) {
      if (awards.contains(code)) return code;
    }

    return '';
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

  int _judgeOrderIndex(String judgeRef) {
    if (judgeRef.isEmpty) return 999;

    if (!_judgeOrderMap.containsKey(judgeRef)) {
      _judgeOrderMap[judgeRef] = _judgeOrderMap.length;
    }

    return _judgeOrderMap[judgeRef]!;
  }

  String _indexToLetter(int index) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (index < 0 || index >= letters.length) return '';
    return letters[index];
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

class _LegRuleMatch {
  final int rule;
  final int animalsCount;
  final int exhibitorsCount;

  const _LegRuleMatch({
    required this.rule,
    required this.animalsCount,
    required this.exhibitorsCount,
  });
}