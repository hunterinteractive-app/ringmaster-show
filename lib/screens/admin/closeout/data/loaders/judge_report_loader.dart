import 'package:supabase/supabase.dart';

import '../../models/base/report_request.dart';
import '../../models/judge/judge_report_data.dart';

class JudgeReportLoader {
  JudgeReportLoader({required SupabaseClient supabase}) : _supabase = supabase;

  final SupabaseClient _supabase;

  Future<JudgeReportData> load(ReportRequest request) async {
    final showId = request.showId;
    final sectionIds = request.sectionIds ?? const <String>[];
    if (sectionIds.isEmpty) {
      throw StateError('Judge report requires scoped section IDs.');
    }
    final show = await _loadShowInfo(showId);
    final judgesById = await _loadJudges(showId);
    final rowsByJudgeId = await _loadJudgedRows(showId, sectionIds);

    final judges = <JudgeReportJudge>[];

    for (final entry in rowsByJudgeId.entries) {
      final judgeId = entry.key;
      final judgeInfo = judgesById[judgeId];
      final rows = entry.value;

      rows.sort(_compareJudgeRows);

      judges.add(
        JudgeReportJudge(
          judgeId: judgeId,
          displayName: judgeInfo?.displayName ?? 'Unassigned Judge',
          arbaNumber: judgeInfo?.arbaNumber,
          email: judgeInfo?.email,
          phone: judgeInfo?.phone,
          rows: rows,
        ),
      );
    }

    judges.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    return JudgeReportData(
      show: show,
      generatedAt: DateTime.now(),
      judges: judges,
    );
  }

  Future<JudgeReportShowInfo> _loadShowInfo(String showId) async {
    final row = await _supabase
        .from('shows')
        .select(
          'id, name, start_date, end_date, location_name, location_address, secretary_name, secretary_email, secretary_phone',
        )
        .eq('id', showId)
        .single();

    return JudgeReportShowInfo(
      showId: row['id'] as String,
      showName: _string(row['name']),
      startDate: _date(row['start_date']),
      endDate: _date(row['end_date']),
      locationName: _location(row),
      secretaryName: _stringOrNull(row['secretary_name']),
      secretaryEmail: _stringOrNull(row['secretary_email']),
      secretaryPhone: _stringOrNull(row['secretary_phone']),
    );
  }

  Future<Map<String, _JudgeInfo>> _loadJudges(String showId) async {
    final result = <String, _JudgeInfo>{};

    final assignmentRows = await _supabase
        .from('judge_assignments')
        .select()
        .eq('show_id', showId);

    for (final raw in assignmentRows as List<dynamic>) {
      final row = Map<String, dynamic>.from(raw as Map);
      final assignmentId = _stringOrNull(row['id']);
      final judgeId = _stringOrNull(row['judge_id']);
      final label = _firstNonEmpty([
        row['assignment_label'],
        row['display_name'],
        row['judge_name'],
        row['name'],
        row['email'],
        'Unknown Judge',
      ]);

      final judgeInfo = _JudgeInfo(
        id: judgeId ?? assignmentId ?? '',
        displayName: _judgeDisplayNameFromAssignmentLabel(label),
        arbaNumber: _arbaNumberFromAssignmentLabel(label),
        email: _stringOrNull(row['email']),
        phone: _stringOrNull(row['phone']),
      );

      if (judgeId != null) result[judgeId] = judgeInfo;
      if (assignmentId != null) result[assignmentId] = judgeInfo;
    }

    if (result.isNotEmpty) return result;

    final rows = await _supabase
        .from('show_judges')
        .select()
        .eq('show_id', showId);

    for (final raw in rows as List<dynamic>) {
      final row = Map<String, dynamic>.from(raw as Map);
      final judgeInfo = _JudgeInfo(
        id: _firstNonEmpty([
          row['id'],
          row['show_judge_id'],
          row['judge_id'],
          row['user_id'],
        ]),
        displayName: _firstNonEmpty([
          row['display_name'],
          row['judge_name'],
          row['name'],
          row['full_name'],
          row['judge_full_name'],
          row['email'],
          'Unknown Judge',
        ]),
        arbaNumber: _stringOrNull(row['arba_number']),
        email: _stringOrNull(row['email']),
        phone: _stringOrNull(row['phone']),
      );

      for (final candidateId in <String>{
        _string(row['id']),
        _string(row['show_judge_id']),
        _string(row['judge_id']),
        _string(row['user_id']),
      }) {
        if (candidateId.isNotEmpty) {
          result[candidateId] = judgeInfo;
        }
      }
    }

    return result;
  }

  Future<Map<String, List<JudgeReportRow>>> _loadJudgedRows(
    String showId,
    List<String> sectionIds,
  ) async {
    final entryRows = await _loadAllJudgedEntryRows(showId, sectionIds);

    final entryIds = <String>[];
    final exhibitorIds = <String>[];

    for (final row in entryRows) {
      final entryId = _stringOrNull(row['id']);
      if (entryId != null) entryIds.add(entryId);

      final exhibitorId = _stringOrNull(row['exhibitor_id']);
      if (exhibitorId != null) exhibitorIds.add(exhibitorId);
    }

    final awardsByEntryId = await _loadAwardsByEntryId(entryIds);
    final exhibitorNamesById = await _loadExhibitorNamesById(exhibitorIds);
    final result = <String, List<JudgeReportRow>>{};

    for (final row in entryRows) {
      final judgeId = _stringOrNull(row['judged_by_show_judge_id']);
      final entryId = _stringOrNull(row['id']);
      if (judgeId == null || entryId == null) continue;

      final exhibitorId = _stringOrNull(row['exhibitor_id']);

      result
          .putIfAbsent(judgeId, () => <JudgeReportRow>[])
          .add(
            JudgeReportRow(
              entryId: entryId,
              sectionLabel: _sectionLabel(row['show_sections']),
              species: _string(row['species']),
              breed: _string(row['breed']),
              variety: _string(row['variety']),
              className: _string(row['class_name']),
              sex: _string(row['sex']),
              tattoo: _string(row['tattoo']),
              exhibitorName: _exhibitorName(
                row,
                fallbackName: exhibitorId == null
                    ? null
                    : exhibitorNamesById[exhibitorId],
              ),
              animalName: _stringOrNull(row['animal_name']),
              placement: _intOrNull(row['placement']),
              resultStatus: _stringOrNull(row['result_status']),
              disqualifiedReason: _stringOrNull(row['disqualified_reason']),
              awards: awardsByEntryId[entryId] ?? const <String>[],
              isFur: row['is_fur'] == true,
              furVariety: _stringOrNull(row['fur_variety']),
              notes: _stringOrNull(row['notes']),
            ),
          );
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _loadAllJudgedEntryRows(
    String showId,
    List<String> sectionIds,
  ) async {
    const pageSize = 1000;
    final allRows = <Map<String, dynamic>>[];

    for (var from = 0; ; from += pageSize) {
      final to = from + pageSize - 1;

      final page = await _supabase
          .from('entries')
          .select('*, show_sections(kind, letter, sort_order)')
          .eq('show_id', showId)
          .inFilter('section_id', sectionIds)
          .not('judged_by_show_judge_id', 'is', null)
          .filter('scratched_at', 'is', null)
          .order('id')
          .range(from, to);

      final rows = (page as List<dynamic>)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

      allRows.addAll(rows);

      if (rows.length < pageSize) break;
    }

    return allRows;
  }

  Future<Map<String, List<String>>> _loadAwardsByEntryId(
    List<String> entryIds,
  ) async {
    if (entryIds.isEmpty) return <String, List<String>>{};

    final result = <String, List<String>>{};
    const chunkSize = 100;

    for (var start = 0; start < entryIds.length; start += chunkSize) {
      final end = start + chunkSize > entryIds.length
          ? entryIds.length
          : start + chunkSize;
      final chunk = entryIds.sublist(start, end);

      final rows = await _supabase
          .from('entry_awards')
          .select('entry_id, award_code')
          .inFilter('entry_id', chunk);

      for (final raw in rows as List<dynamic>) {
        final row = Map<String, dynamic>.from(raw as Map);
        final entryId = _stringOrNull(row['entry_id']);
        if (entryId == null) continue;

        final award = _string(row['award_code']);
        if (award.isEmpty) continue;

        result.putIfAbsent(entryId, () => <String>[]).add(award);
      }
    }

    return result;
  }

  Future<Map<String, String>> _loadExhibitorNamesById(
    List<String> exhibitorIds,
  ) async {
    final ids = exhibitorIds.toSet().where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return <String, String>{};

    final result = <String, String>{};
    const chunkSize = 100;

    for (var start = 0; start < ids.length; start += chunkSize) {
      final end = start + chunkSize > ids.length
          ? ids.length
          : start + chunkSize;
      final chunk = ids.sublist(start, end);

      final rows = await _supabase
          .from('exhibitors')
          .select(
            'id, display_name, showing_name, first_name, last_name, email',
          )
          .inFilter('id', chunk);

      for (final raw in rows as List<dynamic>) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = _stringOrNull(row['id']);
        if (id == null) continue;

        final firstName = _stringOrNull(row['first_name']);
        final lastName = _stringOrNull(row['last_name']);
        final fullName = [
          if (firstName != null) firstName,
          if (lastName != null) lastName,
        ].join(' ').trim();

        final name = _firstNonEmpty([
          row['display_name'],
          row['showing_name'],
          fullName,
          row['email'],
        ]);

        if (name.isNotEmpty) result[id] = name;
      }
    }

    return result;
  }

  int _compareJudgeRows(JudgeReportRow a, JudgeReportRow b) {
    final section = a.sectionLabel.compareTo(b.sectionLabel);
    if (section != 0) return section;

    final species = a.species.compareTo(b.species);
    if (species != 0) return species;

    final breed = a.breed.compareTo(b.breed);
    if (breed != 0) return breed;

    final variety = a.varietyLabel.compareTo(b.varietyLabel);
    if (variety != 0) return variety;

    final classSort = _classRank(
      a.className,
    ).compareTo(_classRank(b.className));
    if (classSort != 0) return classSort;

    final sexSort = _sexRank(a.sex).compareTo(_sexRank(b.sex));
    if (sexSort != 0) return sexSort;

    return a.tattoo.compareTo(b.tattoo);
  }

  int _classRank(String value) {
    switch (value.trim().toLowerCase()) {
      case 'senior':
        return 1;
      case 'intermediate':
      case '6/8':
      case 'six eight':
        return 2;
      case 'junior':
        return 3;
      case 'pre junior':
      case 'pre-junior':
        return 4;
      default:
        return 99;
    }
  }

  int _sexRank(String value) {
    switch (value.trim().toLowerCase()) {
      case 'buck':
      case 'boar':
        return 1;
      case 'doe':
      case 'sow':
        return 2;
      default:
        return 99;
    }
  }

  String _sectionLabel(Object? value) {
    if (value is! Map) return '';
    final row = Map<String, dynamic>.from(value);
    final kind = _string(row['kind']);
    final letter = _string(row['letter']);
    if (kind.isEmpty && letter.isEmpty) return '';
    if (letter.isEmpty) return _titleCase(kind);
    return '${_titleCase(kind)} $letter';
  }

  String _exhibitorName(Map<String, dynamic> row, {String? fallbackName}) {
    final directName = _firstNonEmpty([
      row['exhibitor_name'],
      row['display_name'],
      row['showing_name'],
      row['owner_name'],
      fallbackName,
    ]);
    if (directName.isNotEmpty) return directName;

    final firstName = _stringOrNull(row['first_name']);
    final lastName = _stringOrNull(row['last_name']);
    final combinedName = [
      if (firstName != null) firstName,
      if (lastName != null) lastName,
    ].join(' ').trim();
    if (combinedName.isNotEmpty) return combinedName;

    final exhibitorId = _stringOrNull(row['exhibitor_id']);
    if (exhibitorId != null) return exhibitorId;

    final exhibitorUserId = _stringOrNull(row['exhibitor_user_id']);
    if (exhibitorUserId != null) return exhibitorUserId;

    return '';
  }

  String _judgeDisplayNameFromAssignmentLabel(String label) {
    return label.replaceAll(RegExp(r'\s*\(#.*?\)\s*$'), '').trim();
  }

  String? _arbaNumberFromAssignmentLabel(String label) {
    final match = RegExp(r'\(#([^\)]+)\)').firstMatch(label);
    return match?.group(1)?.trim();
  }

  String _location(Map<String, dynamic> row) {
    final locationName = _stringOrNull(row['location_name']);
    final locationAddress = _stringOrNull(row['location_address']);

    return [
      if (locationName != null) locationName,
      if (locationAddress != null) locationAddress,
    ].join(' • ');
  }

  DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  String _string(Object? value) => value?.toString().trim() ?? '';

  String? _stringOrNull(Object? value) {
    final text = _string(value);
    return text.isEmpty ? null : text;
  }

  String _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = _string(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _titleCase(String value) {
    final text = value.trim();
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}

class _JudgeInfo {
  _JudgeInfo({
    required this.id,
    required this.displayName,
    this.arbaNumber,
    this.email,
    this.phone,
  });

  final String id;
  final String displayName;
  final String? arbaNumber;
  final String? email;
  final String? phone;
}
