// lib/screens/admin/closeout/data/loaders/coop_cards_report_loader.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/coop_cards/coop_cards_report_data.dart';

class CoopCardsReportLoader {
  final SupabaseClient supabase;

  CoopCardsReportLoader({SupabaseClient? supabase})
      : supabase = supabase ?? Supabase.instance.client;

  static const int _rpcPageSize = 1000;
  static const int _queryChunkSize = 500;

  Future<CoopCardsReportData> load({
    required String showId,
    String? scope,
  }) async {
    final normalizedShowId = showId.trim();
    if (normalizedShowId.isEmpty) {
      throw ArgumentError.value(showId, 'showId', 'Show ID is required.');
    }

    final show = await supabase
        .from('shows')
        .select(
          'id,name,start_date,end_date,location_name,coop_numbering_mode',
        )
        .eq('id', normalizedShowId)
        .maybeSingle();

    if (show == null) {
      throw StateError('The selected show could not be found.');
    }

    final numberingMode =
        (show['coop_numbering_mode'] ?? 'separate')
            .toString()
            .trim()
            .toLowerCase();

    final sections = await _loadSections(normalizedShowId);
    final sectionById = <String, Map<String, dynamic>>{
      for (final section in sections)
        _safe(section, 'id'): section,
    };

    final reportRows = await _loadCheckInRows(normalizedShowId);
    await _attachAnimalIds(reportRows);
    await _attachExhibitorDetails(reportRows);

    final assignments = await _loadAssignments(
      normalizedShowId,
      scope: scope,
    );

    final activeRows = reportRows.where((row) {
      return _safe(row, 'animal_id').isNotEmpty;
    }).toList();

    final rowsByAnimalId = <String, List<Map<String, dynamic>>>{};
    for (final row in activeRows) {
      final animalId = _safe(row, 'animal_id');
      rowsByAnimalId.putIfAbsent(animalId, () => []).add(row);
    }

    final classStats = _buildClassStats(
      activeRows,
      sectionById,
      numberingMode,
    );

    final cards = <CoopCardRow>[];

    for (final assignment in assignments) {
      final animalId = _safe(assignment, 'animal_id');
      final assignmentScope =
          _safe(assignment, 'scope').toLowerCase();
      final coopNumber = _safe(assignment, 'coop_number');

      if (animalId.isEmpty || coopNumber.isEmpty) continue;

      final animalRows = rowsByAnimalId[animalId] ?? const [];
      final scopedRows = animalRows.where((row) {
        if (assignmentScope == 'all') return true;

        final sectionId = _safe(row, 'section_id');
        final section = sectionById[sectionId];
        final sectionKind = section == null
            ? _safe(row, 'section_kind').toLowerCase()
            : _safe(section, 'kind').toLowerCase();

        return sectionKind == assignmentScope;
      }).toList();

      if (scopedRows.isEmpty) continue;

      scopedRows.sort((a, b) {
        final aSection = sectionById[_safe(a, 'section_id')];
        final bSection = sectionById[_safe(b, 'section_id')];

        final sortCmp = _asInt(aSection?['sort_order'])
            .compareTo(_asInt(bSection?['sort_order']));
        if (sortCmp != 0) return sortCmp;

        return _safe(aSection ?? const {}, 'letter')
            .compareTo(_safe(bSection ?? const {}, 'letter'));
      });

      final first = scopedRows.first;
      final showLetters = <String>[];
      final sectionLabels = <String>[];

      for (final row in scopedRows) {
        final section = sectionById[_safe(row, 'section_id')];
        if (section == null) continue;

        final letter = _safe(section, 'letter').toUpperCase();
        if (letter.isNotEmpty && !showLetters.contains(letter)) {
          showLetters.add(letter);
        }

        final displayName = _safe(section, 'display_name');
        final kind = _safe(section, 'kind');
        final fallbackLabel = [
          if (kind.isNotEmpty) _titleCase(kind),
          if (letter.isNotEmpty) letter,
        ].join(' ');
        final label = displayName.isNotEmpty ? displayName : fallbackLabel;

        if (label.isNotEmpty && !sectionLabels.contains(label)) {
          sectionLabels.add(label);
        }
      }

      final statKey = _classKeyForRow(
        first,
        assignmentScope,
        sectionById,
        numberingMode,
      );
      final stats = classStats[statKey] ?? _ClassStats();

      cards.add(
        CoopCardRow(
          coopNumber: coopNumber,
          scope: assignmentScope,
          species: _safe(first, 'species'),
          animalId: animalId,
          animalName: _safe(first, 'animal_name'),
          tattoo: _safe(first, 'tattoo'),
          breed: _safe(first, 'breed').isNotEmpty
              ? _safe(first, 'breed')
              : _safe(first, 'breed_name'),
          variety: _safe(first, 'variety').isNotEmpty
              ? _safe(first, 'variety')
              : _safe(first, 'variety_name'),
          groupName: _safe(first, 'group_name'),
          className: _displayAgeClassOnly(_safe(first, 'class_name')),
          sex: _safe(first, 'sex'),
          exhibitorId: _safe(first, 'exhibitor_id'),
          exhibitorName: _safe(first, 'exhibitor_label'),
          exhibitorCity: _safe(first, 'city'),
          exhibitorState: _safe(first, 'state'),
          exhibitorNumber: _safe(first, 'exhibitor_number'),
          showLetters: showLetters,
          sectionLabels: sectionLabels,
          classEntryCount: stats.animalIds.length,
          classExhibitorCount: stats.exhibitorIds.length,
        ),
      );
    }

    cards.sort((a, b) {
      final prefixCmp = a.coopPrefix.compareTo(b.coopPrefix);
      if (prefixCmp != 0) return prefixCmp;

      final sequenceCmp =
          a.coopSequenceValue.compareTo(b.coopSequenceValue);
      if (sequenceCmp != 0) return sequenceCmp;

      return a.coopNumber.compareTo(b.coopNumber);
    });

    return CoopCardsReportData(
      showId: normalizedShowId,
      showName: _safe(show, 'name').isEmpty
          ? 'RingMaster Show'
          : _safe(show, 'name'),
      showDateLabel: _dateRangeLabel(
        show['start_date'],
        show['end_date'],
      ),
      showLocationLabel: _safe(show, 'location_name'),
      coopNumberingMode: numberingMode,
      generatedAt: DateTime.now(),
      cards: cards,
    );
  }

  Future<List<Map<String, dynamic>>> _loadSections(String showId) async {
    final rows = await supabase
        .from('show_sections')
        .select('id,kind,letter,display_name,sort_order')
        .eq('show_id', showId)
        .order('sort_order')
        .order('letter');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _loadCheckInRows(
    String showId,
  ) async {
    final rows = <Map<String, dynamic>>[];

    for (var from = 0;; from += _rpcPageSize) {
      final to = from + _rpcPageSize - 1;
      final result = await supabase
          .rpc(
            'report_checkin_entries',
            params: {
              'p_show_id': showId,
              'p_section_id': null,
              'p_include_scratched': false,
            },
          )
          .range(from, to);

      final page = List<Map<String, dynamic>>.from(result as List);
      rows.addAll(page);

      if (page.length < _rpcPageSize) break;
    }

    return rows;
  }

  Future<void> _attachAnimalIds(
    List<Map<String, dynamic>> rows,
  ) async {
    final entryIds = rows
        .map((row) {
          final entryId = _safe(row, 'entry_id');
          return entryId.isNotEmpty ? entryId : _safe(row, 'id');
        })
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final animalIdByEntryId = <String, String>{};

    for (var i = 0; i < entryIds.length; i += _queryChunkSize) {
      final chunk = entryIds.skip(i).take(_queryChunkSize).toList();
      if (chunk.isEmpty) continue;

      final result = await supabase
          .from('entries')
          .select('id,animal_id')
          .inFilter('id', chunk);

      for (final raw in result as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final entryId = _safe(row, 'id');
        final animalId = _safe(row, 'animal_id');
        if (entryId.isNotEmpty && animalId.isNotEmpty) {
          animalIdByEntryId[entryId] = animalId;
        }
      }
    }

    for (final row in rows) {
      final entryId = _safe(row, 'entry_id').isNotEmpty
          ? _safe(row, 'entry_id')
          : _safe(row, 'id');
      row['animal_id'] = animalIdByEntryId[entryId] ?? '';
    }
  }

  Future<void> _attachExhibitorDetails(
    List<Map<String, dynamic>> rows,
  ) async {
    final exhibitorIds = rows
        .map((row) => _safe(row, 'exhibitor_id'))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final exhibitorById = <String, Map<String, dynamic>>{};

    for (var i = 0; i < exhibitorIds.length; i += _queryChunkSize) {
      final chunk = exhibitorIds.skip(i).take(_queryChunkSize).toList();
      if (chunk.isEmpty) continue;

      final result = await supabase
          .from('exhibitors')
          .select('id,exhibitor_number,city,state')
          .inFilter('id', chunk);

      for (final raw in result as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = _safe(row, 'id');
        if (id.isNotEmpty) exhibitorById[id] = row;
      }
    }

    for (final row in rows) {
      final exhibitor = exhibitorById[_safe(row, 'exhibitor_id')];
      if (exhibitor == null) continue;

      final exhibitorNumber = _safe(exhibitor, 'exhibitor_number');
      final city = _safe(exhibitor, 'city');
      final state = _safe(exhibitor, 'state');

      if (exhibitorNumber.isNotEmpty) {
        row['exhibitor_number'] = exhibitorNumber;
      }
      if (_safe(row, 'city').isEmpty && city.isNotEmpty) {
        row['city'] = city;
      }
      if (_safe(row, 'state').isEmpty && state.isNotEmpty) {
        row['state'] = state;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAssignments(
    String showId, {
    String? scope,
  }) async {
    final rows = <Map<String, dynamic>>[];
    final normalizedScope = scope?.trim().toLowerCase() ?? '';

    for (var from = 0;; from += _rpcPageSize) {
      final to = from + _rpcPageSize - 1;

      var query = supabase
          .from('show_animal_coop_numbers')
          .select('animal_id,scope,coop_number')
          .eq('show_id', showId);

      if (normalizedScope.isNotEmpty) {
        query = query.eq('scope', normalizedScope);
      }

      final result = await query.range(from, to);
      final page = List<Map<String, dynamic>>.from(result);
      rows.addAll(page);

      if (page.length < _rpcPageSize) break;
    }

    return rows;
  }

  Map<String, _ClassStats> _buildClassStats(
    List<Map<String, dynamic>> rows,
    Map<String, Map<String, dynamic>> sectionById,
    String numberingMode,
  ) {
    final stats = <String, _ClassStats>{};

    for (final row in rows) {
      final sectionId = _safe(row, 'section_id');
      final section = sectionById[sectionId];
      final sectionKind = section == null
          ? _safe(row, 'section_kind').toLowerCase()
          : _safe(section, 'kind').toLowerCase();
      final scope = numberingMode == 'combined' ? 'all' : sectionKind;
      final key = _classKeyForRow(
        row,
        scope,
        sectionById,
        numberingMode,
      );

      final stat = stats.putIfAbsent(key, _ClassStats.new);
      final animalId = _safe(row, 'animal_id');
      final exhibitorId = _safe(row, 'exhibitor_id');

      if (animalId.isNotEmpty) stat.animalIds.add(animalId);
      if (exhibitorId.isNotEmpty) stat.exhibitorIds.add(exhibitorId);
    }

    return stats;
  }

  String _classKeyForRow(
    Map<String, dynamic> row,
    String requestedScope,
    Map<String, Map<String, dynamic>> sectionById,
    String numberingMode,
  ) {
    final sectionId = _safe(row, 'section_id');
    final section = sectionById[sectionId];
    final sectionKind = section == null
        ? _safe(row, 'section_kind').toLowerCase()
        : _safe(section, 'kind').toLowerCase();
    final scope = numberingMode == 'combined'
        ? 'all'
        : requestedScope.isNotEmpty
            ? requestedScope
            : sectionKind;

    final breed = _safe(row, 'breed').isNotEmpty
        ? _safe(row, 'breed')
        : _safe(row, 'breed_name');
    final variety = _safe(row, 'variety').isNotEmpty
        ? _safe(row, 'variety')
        : _safe(row, 'variety_name');

    return [
      scope,
      breed,
      _safe(row, 'group_name'),
      variety,
      _displayAgeClassOnly(_safe(row, 'class_name')),
      _safe(row, 'sex'),
    ].map((value) => value.trim().toLowerCase()).join('|');
  }

  static String _safe(Map<String, dynamic> row, String key) {
    return (row[key] ?? '').toString().trim();
  }

  static int _asInt(dynamic value, [int fallback = 999999]) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _displayAgeClassOnly(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('pre junior') || lower.contains('pre-junior')) {
      return 'Pre-Junior';
    }
    if (lower.contains('senior')) return 'Senior';
    if (lower.contains('intermediate')) return 'Intermediate';
    if (lower.contains('junior')) return 'Junior';
    return raw.trim();
  }

  static String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
  }

  static String _dateRangeLabel(dynamic startValue, dynamic endValue) {
    final start = DateTime.tryParse(startValue?.toString() ?? '');
    final end = DateTime.tryParse(endValue?.toString() ?? '');

    if (start == null && end == null) return '';
    if (start != null && end == null) return _formatDate(start);
    if (start == null && end != null) return _formatDate(end);

    final startDate = start!;
    final endDate = end!;

    if (startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day) {
      return _formatDate(startDate);
    }

    return '${_formatDate(startDate)} – ${_formatDate(endDate)}';
  }

  static String _formatDate(DateTime value) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}

class _ClassStats {
  final Set<String> animalIds = <String>{};
  final Set<String> exhibitorIds = <String>{};

  _ClassStats();
}
