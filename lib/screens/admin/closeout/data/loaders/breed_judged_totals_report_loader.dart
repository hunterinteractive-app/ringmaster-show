import 'package:supabase/supabase.dart';

import '../../models/base/report_request.dart';
import '../../models/judge/breed_judged_totals_report_data.dart';

class BreedJudgedTotalsReportLoader {
  BreedJudgedTotalsReportLoader({required SupabaseClient supabase})
    : _supabase = supabase;

  final SupabaseClient _supabase;

  Future<BreedJudgedTotalsReportData> load(ReportRequest request) async {
    final show = await _loadShowInfo(request.showId);
    final sectionIds = request.sectionIds ?? const <String>[];
    if (sectionIds.isEmpty) {
      throw StateError('Breed judged totals requires scoped section IDs.');
    }
    final entryRows = await _loadAllJudgedEntryRows(request.showId, sectionIds);
    final aggregation = aggregateBreedJudgedTotals(
      entryRows,
      scope: request.scope,
      showLetter: request.showLetter,
      sectionIds: request.sectionIds,
    );
    final showBreakdowns = aggregateBreedJudgedTotalsByShow(
      entryRows,
      scope: request.scope,
      showLetter: request.showLetter,
      sectionIds: request.sectionIds,
    );

    return BreedJudgedTotalsReportData(
      show: show,
      generatedAt: DateTime.now(),
      scopeLabel: _scopeLabel(
        request.scope,
        request.showLetter,
        request.scopeLabel,
      ),
      breedRows: aggregation.breedRows,
      furRows: aggregation.furRows,
      showBreakdowns: showBreakdowns,
    );
  }

  Future<BreedJudgedTotalsReportShowInfo> _loadShowInfo(String showId) async {
    final row = await _supabase
        .from('shows')
        .select(
          'id, name, start_date, end_date, location_name, location_address, secretary_name, secretary_email, secretary_phone',
        )
        .eq('id', showId)
        .maybeSingle();

    final showRow = row ?? <String, dynamic>{};

    return BreedJudgedTotalsReportShowInfo(
      showId: _string(showRow['id']).isEmpty ? showId : _string(showRow['id']),
      showName: _string(showRow['name']).isEmpty
          ? 'Unnamed Show'
          : _string(showRow['name']),
      startDate: _date(showRow['start_date']),
      endDate: _date(showRow['end_date']),
      locationName: _location(showRow),
      secretaryName: _stringOrNull(showRow['secretary_name']),
      secretaryEmail: _stringOrNull(showRow['secretary_email']),
      secretaryPhone: _stringOrNull(showRow['secretary_phone']),
    );
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
          .select(
            '*, show_sections(id, kind, letter, display_name, sort_order)',
          )
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

  DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _location(Map<String, dynamic> row) {
    final locationName = _stringOrNull(row['location_name']);
    final locationAddress = _stringOrNull(row['location_address']);

    return [
      if (locationName != null) locationName,
      if (locationAddress != null) locationAddress,
    ].join(' • ');
  }

  String _string(Object? value) => value?.toString().trim() ?? '';

  String? _stringOrNull(Object? value) {
    final text = _string(value);
    return text.isEmpty ? null : text;
  }
}

BreedJudgedTotalsAggregation aggregateBreedJudgedTotals(
  List<Map<String, dynamic>> rows, {
  String? scope,
  String? showLetter,
  List<String>? sectionIds,
}) {
  final breedRows = <String, BreedJudgedTotalsReportRow>{};
  final furRows = <String, BreedJudgedTotalsReportRow>{};
  final selectedSectionIds = (sectionIds ?? const <String>[])
      .map(_string)
      .where((id) => id.isNotEmpty)
      .toSet();

  for (final row in rows) {
    if (!_rowMatchesReportFilters(
      row,
      selectedSectionIds: selectedSectionIds,
      scope: scope,
      showLetter: showLetter,
    )) {
      continue;
    }

    _addBreedJudgedRow(row, breedRows: breedRows, furRows: furRows);
  }

  return BreedJudgedTotalsAggregation(
    breedRows: _sortedRows(breedRows.values),
    furRows: _sortedRows(furRows.values),
  );
}

List<BreedJudgedTotalsShowBreakdown> aggregateBreedJudgedTotalsByShow(
  List<Map<String, dynamic>> rows, {
  String? scope,
  String? showLetter,
  List<String>? sectionIds,
}) {
  final selectedSectionIds = (sectionIds ?? const <String>[])
      .map(_string)
      .where((id) => id.isNotEmpty)
      .toSet();
  final groups = <String, _BreedJudgedTotalsShowAccumulator>{};

  for (final row in rows) {
    if (!_rowMatchesReportFilters(
      row,
      selectedSectionIds: selectedSectionIds,
      scope: scope,
      showLetter: showLetter,
    )) {
      continue;
    }

    final section = _sectionRow(row);
    final sectionId = _firstNonEmpty([row['section_id'], section['id']]);
    final kind = _string(section['kind']).toUpperCase();
    final letter = _string(section['letter']).toUpperCase();
    final sortOrder = _int(section['sort_order'], 9999);
    final label = _showBreakdownLabel(
      displayName: _string(section['display_name']),
      kind: kind,
      letter: letter,
      sectionId: sectionId,
    );
    final key = sectionId.isNotEmpty
        ? sectionId
        : '$sortOrder|$kind|$letter|$label';

    final group = groups.putIfAbsent(
      key,
      () => _BreedJudgedTotalsShowAccumulator(
        label: label,
        kind: kind,
        letter: letter,
        sortOrder: sortOrder,
      ),
    );

    _addBreedJudgedRow(row, breedRows: group.breedRows, furRows: group.furRows);
  }

  final sortedGroups = groups.values.toList()
    ..sort(_compareShowBreakdownGroups);

  return sortedGroups
      .map(
        (group) => BreedJudgedTotalsShowBreakdown(
          label: group.label,
          breedRows: _sortedRows(group.breedRows.values),
          furRows: _sortedRows(group.furRows.values),
        ),
      )
      .where((group) => group.breedRows.isNotEmpty || group.furRows.isNotEmpty)
      .toList();
}

bool _rowMatchesReportFilters(
  Map<String, dynamic> row, {
  required Set<String> selectedSectionIds,
  String? scope,
  String? showLetter,
}) {
  if (!_isCountableJudgedRow(row)) return false;
  if (selectedSectionIds.isNotEmpty &&
      !selectedSectionIds.contains(_string(row['section_id']))) {
    return false;
  }
  if (!_matchesScope(row, scope: scope, showLetter: showLetter)) return false;
  return true;
}

void _addBreedJudgedRow(
  Map<String, dynamic> row, {
  required Map<String, BreedJudgedTotalsReportRow> breedRows,
  required Map<String, BreedJudgedTotalsReportRow> furRows,
}) {
  final breed = _firstNonEmpty([
    row['breed'],
    row['breed_name'],
    row['animal_breed'],
    'Unknown Breed',
  ]);
  final species = _titleCase(
    _firstNonEmpty([row['species'], row['animal_species'], 'Unknown']),
  );
  final target = row['is_fur'] == true ? furRows : breedRows;
  final key = '${breed.toLowerCase()}|${species.toLowerCase()}';
  final existing = target[key];

  if (existing == null) {
    target[key] = BreedJudgedTotalsReportRow(
      breed: breed,
      species: species,
      totalJudged: 1,
    );
  } else {
    target[key] = existing.copyWith(totalJudged: existing.totalJudged + 1);
  }
}

bool _isCountableJudgedRow(Map<String, dynamic> row) {
  if (_bool(row['is_test'])) return false;
  if (_string(row['judged_by_show_judge_id']).isEmpty) return false;
  if (_string(row['scratched_at']).isNotEmpty) return false;
  if (row['is_shown'] == false) return false;

  final status = _string(row['result_status']).toLowerCase();
  final entryStatus = _string(row['status']).toLowerCase();

  return !_isNoShowStatus(status) &&
      !_isNoShowStatus(entryStatus) &&
      !_isScratchedStatus(entryStatus);
}

Map<String, dynamic> _sectionRow(Map<String, dynamic> row) {
  final section = row['show_sections'];
  if (section is Map) return Map<String, dynamic>.from(section);
  return const <String, dynamic>{};
}

bool _matchesScope(
  Map<String, dynamic> row, {
  String? scope,
  String? showLetter,
}) {
  final expectedScope = _string(scope).toUpperCase();
  final expectedLetter = _string(showLetter).toUpperCase();
  if (expectedScope.isEmpty && expectedLetter.isEmpty) return true;

  final section = row['show_sections'];
  if (section is! Map) return false;
  final sectionRow = Map<String, dynamic>.from(section);
  final sectionScope = _string(sectionRow['kind']).toUpperCase();
  final sectionLetter = _string(sectionRow['letter']).toUpperCase();

  if (expectedScope.isNotEmpty && sectionScope != expectedScope) return false;
  if (expectedLetter.isNotEmpty && sectionLetter != expectedLetter) {
    return false;
  }

  return true;
}

bool _isNoShowStatus(String value) {
  final normalized = value.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return normalized == 'noshow' || normalized == 'notshown';
}

bool _isScratchedStatus(String value) {
  final normalized = value.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return normalized == 'scratched' || normalized == 'scratch';
}

List<BreedJudgedTotalsReportRow> _sortedRows(
  Iterable<BreedJudgedTotalsReportRow> rows,
) {
  final result = rows.toList();
  result.sort((a, b) {
    final breed = a.breed.toLowerCase().compareTo(b.breed.toLowerCase());
    if (breed != 0) return breed;
    return a.species.toLowerCase().compareTo(b.species.toLowerCase());
  });
  return result;
}

int _compareShowBreakdownGroups(
  _BreedJudgedTotalsShowAccumulator a,
  _BreedJudgedTotalsShowAccumulator b,
) {
  final sortCompare = a.sortOrder.compareTo(b.sortOrder);
  if (sortCompare != 0) return sortCompare;

  final kindCompare = _showKindRank(a.kind).compareTo(_showKindRank(b.kind));
  if (kindCompare != 0) return kindCompare;

  final letterCompare = a.letter.compareTo(b.letter);
  if (letterCompare != 0) return letterCompare;

  return a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

int _showKindRank(String kind) {
  final normalized = kind.toLowerCase();
  if (normalized == 'open') return 0;
  if (normalized == 'youth') return 1;
  return 2;
}

String _showBreakdownLabel({
  required String displayName,
  required String kind,
  required String letter,
  required String sectionId,
}) {
  if (displayName.trim().isNotEmpty) return displayName.trim();

  final scope = kind.trim().isEmpty ? '' : _titleCase(kind);
  final suffix = letter.trim().isEmpty ? '' : 'Show ${letter.trim()}';
  final label = [
    scope,
    suffix,
  ].where((part) => part.trim().isNotEmpty).join(' ').trim();
  if (label.isNotEmpty) return label;
  if (sectionId.trim().isNotEmpty) return 'Show Section ${sectionId.trim()}';
  return 'Unassigned Show';
}

String _scopeLabel(String? scope, String? showLetter, String? scopeLabel) {
  final label = _string(scopeLabel);
  if (label.isNotEmpty) return label;

  final parts = [
    _string(scope).toUpperCase(),
    _string(showLetter).toUpperCase(),
  ].where((part) => part.isNotEmpty).toList();

  return parts.join(' ');
}

String _titleCase(String value) {
  final text = value.trim();
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1).toLowerCase();
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = _string(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool _bool(Object? value) {
  if (value is bool) return value;
  return value?.toString().trim().toLowerCase() == 'true';
}

int _int(Object? value, int fallback) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _string(Object? value) => value?.toString().trim() ?? '';

class _BreedJudgedTotalsShowAccumulator {
  _BreedJudgedTotalsShowAccumulator({
    required this.label,
    required this.kind,
    required this.letter,
    required this.sortOrder,
  });

  final String label;
  final String kind;
  final String letter;
  final int sortOrder;
  final Map<String, BreedJudgedTotalsReportRow> breedRows = {};
  final Map<String, BreedJudgedTotalsReportRow> furRows = {};
}
