import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/utils/species_sex.dart';

import '../report_data_reader.dart';
import '../../models/base/report_request.dart';
import '../../models/exhibitor/check_in_sheet_report_data.dart';

class CheckInSheetReportLoader {
  CheckInSheetReportLoader(this.supabase);

  final SupabaseClient supabase;

  Future<CheckInSheetReportData> load(ReportRequest request) async {
    final exhibitorId = (request.exhibitorId ?? '').trim();
    if (exhibitorId.isEmpty) {
      throw StateError('Check-in sheet requires an exhibitor.');
    }

    final showContact =
        await supabase
            .from('shows')
            .select(
              'id, secretary_name, secretary_phone, secretary_email, coop_numbering_mode',
            )
            .eq('id', request.showId)
            .maybeSingle() ??
        <String, dynamic>{};

    final sectionIds = request.sectionIds ?? const <String>[];
    if (sectionIds.isEmpty) {
      throw StateError('Check-in sheet requires scoped section IDs.');
    }
    final entries = await _fetchEntries(
      request.showId,
      exhibitorId,
      sectionIds,
    );
    if (entries.isEmpty) {
      throw StateError('No entries found for this exhibitor.');
    }

    await _enrichExhibitor(entries, exhibitorId);
    await _enrichEntryFields(entries);
    await _enrichCoopNumbers(
      showId: request.showId,
      entries: entries,
      coopNumberingMode: (showContact['coop_numbering_mode'] ?? 'separate')
          .toString(),
    );

    for (final entry in entries) {
      normalizeSpeciesSexPresentation(entry);
    }

    entries.sort(_compareEntries);

    return CheckInSheetReportData(
      showName: request.showName ?? '',
      sectionLabel: 'All Sections',
      entries: entries,
      showContact: Map<String, dynamic>.from(showContact),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchEntries(
    String showId,
    String exhibitorId,
    List<String> sectionIds,
  ) async {
    const pageSize = 1000;
    final list = <Map<String, dynamic>>[];

    for (var from = 0; ; from = list.length) {
      final to = from + pageSize - 1;
      final rows = await supabase
          .rpc(
            'report_closeout_checkin_entries',
            params: {
              'p_show_id': showId,
              'p_exhibitor_id': exhibitorId,
              'p_section_ids': sectionIds,
              'p_include_scratched': false,
            },
          )
          .range(from, to);

      final page = (rows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      list.addAll(page);
      if (rows.isEmpty) break;
    }

    return list;
  }

  Future<void> _enrichExhibitor(
    List<Map<String, dynamic>> entries,
    String exhibitorId,
  ) async {
    final row = await supabase
        .from('exhibitors')
        .select(
          'id, exhibitor_number, first_name, last_name, display_name, showing_name',
        )
        .eq('id', exhibitorId)
        .maybeSingle();

    if (row == null) return;

    final exhibitor = Map<String, dynamic>.from(row);
    final exhibitorNumber = (exhibitor['exhibitor_number'] ?? '')
        .toString()
        .trim();
    final first = (exhibitor['first_name'] ?? '').toString().trim();
    final last = (exhibitor['last_name'] ?? '').toString().trim();
    final displayName = (exhibitor['display_name'] ?? '').toString().trim();
    final showingName = (exhibitor['showing_name'] ?? '').toString().trim();

    for (final entry in entries) {
      if (exhibitorNumber.isNotEmpty) {
        entry['exhibitor_number'] = exhibitorNumber;
      }
      if (first.isNotEmpty) entry['exhibitor_first_name'] = first;
      if (last.isNotEmpty) entry['exhibitor_last_name'] = last;
      if (displayName.isNotEmpty) entry['exhibitor_display_name'] = displayName;
      if (showingName.isNotEmpty) entry['exhibitor_showing_name'] = showingName;
    }
  }

  Future<void> _enrichEntryFields(List<Map<String, dynamic>> entries) async {
    final entryIds = entries
        .map((entry) {
          final entryId = (entry['entry_id'] ?? '').toString().trim();
          if (entryId.isNotEmpty) return entryId;
          return (entry['id'] ?? '').toString().trim();
        })
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final animalIdByEntryId = <String, String>{};
    final furByEntryId = <String, bool>{};
    final rows = await loadReportRowsByIds(
      supabase,
      table: 'entries',
      columns: 'id, animal_id, is_fur, class_name',
      ids: entryIds,
    );
    for (final raw in rows) {
      final entryId = (raw['id'] ?? '').toString().trim();
      if (entryId.isEmpty) continue;
      final animalId = (raw['animal_id'] ?? '').toString().trim();
      if (animalId.isNotEmpty) animalIdByEntryId[entryId] = animalId;
      final className = (raw['class_name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      furByEntryId[entryId] =
          _truthy(raw['is_fur']) || className.contains('fur');
    }

    for (final entry in entries) {
      final entryId = (entry['entry_id'] ?? '').toString().trim().isNotEmpty
          ? (entry['entry_id'] ?? '').toString().trim()
          : (entry['id'] ?? '').toString().trim();

      entry['animal_id'] = animalIdByEntryId[entryId] ?? '';
      if (entryId.isNotEmpty) {
        entry['is_fur'] =
            _truthy(entry['is_fur']) || (furByEntryId[entryId] ?? false);
      }
    }
  }

  Future<void> _enrichCoopNumbers({
    required String showId,
    required List<Map<String, dynamic>> entries,
    required String coopNumberingMode,
  }) async {
    final animalIds = entries
        .map((entry) => (entry['animal_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final coopNumberByAnimalAndScope = <String, String>{};
    final rows = await loadReportRowsByIds(
      supabase,
      table: 'show_animal_coop_numbers',
      columns: 'animal_id, scope, coop_number',
      ids: animalIds,
      idColumn: 'animal_id',
      filters: {'show_id': showId},
      orderColumns: ['animal_id', 'scope', 'coop_number'],
    );
    for (final raw in rows) {
      final animalId = (raw['animal_id'] ?? '').toString().trim();
      final scope = (raw['scope'] ?? '').toString().trim().toLowerCase();
      final coopNumber = (raw['coop_number'] ?? '').toString().trim();
      if (animalId.isEmpty || scope.isEmpty) continue;
      coopNumberByAnimalAndScope['$animalId|$scope'] = coopNumber;
    }

    final mode = coopNumberingMode.trim().toLowerCase();
    for (final entry in entries) {
      final animalId = (entry['animal_id'] ?? '').toString().trim();
      final sectionKind = (entry['section_kind'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final scope = mode == 'combined' ? 'all' : sectionKind;

      entry['coop_number'] = animalId.isEmpty || scope.isEmpty
          ? ''
          : (coopNumberByAnimalAndScope['$animalId|$scope'] ?? '');
    }
  }

  int _compareEntries(Map<String, dynamic> a, Map<String, dynamic> b) {
    int toInt(dynamic value, [int fallback = 9999]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? fallback;
    }

    int kindRank(String kind) {
      switch (kind.toLowerCase()) {
        case 'open':
          return 0;
        case 'youth':
          return 1;
        default:
          return 99;
      }
    }

    final kindCmp = kindRank(
      _safe(a, 'section_kind'),
    ).compareTo(kindRank(_safe(b, 'section_kind')));
    if (kindCmp != 0) return kindCmp;

    final sectionCmp = toInt(
      a['section_sort_order'],
    ).compareTo(toInt(b['section_sort_order']));
    if (sectionCmp != 0) return sectionCmp;

    final letterCmp = _safe(
      a,
      'section_letter',
    ).toUpperCase().compareTo(_safe(b, 'section_letter').toUpperCase());
    if (letterCmp != 0) return letterCmp;

    final breedCmp = _safe(
      a,
      'breed',
    ).toLowerCase().compareTo(_safe(b, 'breed').toLowerCase());
    if (breedCmp != 0) return breedCmp;

    final classCmp = toInt(
      a['class_sort_order'],
    ).compareTo(toInt(b['class_sort_order']));
    if (classCmp != 0) return classCmp;

    final sexCmp = _safe(
      a,
      'sex',
    ).toLowerCase().compareTo(_safe(b, 'sex').toLowerCase());
    if (sexCmp != 0) return sexCmp;

    return _safe(
      a,
      'tattoo',
    ).toLowerCase().compareTo(_safe(b, 'tattoo').toLowerCase());
  }

  String _safe(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim();

  bool _truthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final text = value.toString().trim().toLowerCase();
    return text == 'true' ||
        text == 't' ||
        text == 'yes' ||
        text == 'y' ||
        text == '1' ||
        text == 'x';
  }
}
