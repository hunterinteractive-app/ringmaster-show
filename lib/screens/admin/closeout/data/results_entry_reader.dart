import 'package:supabase/supabase.dart';
import 'report_data_reader.dart';

/// The SQL page bounds the entries BEFORE expensive report joins. Cursoring
/// by the last actual ID also handles an API cap below the requested page size.
Future<ReportRows> loadResultsEntryRows(
  SupabaseClient client, {
  required Map<String, dynamic> params,
  Iterable<String>? entryIds,
}) async {
  final ids = entryIds
      ?.map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  if (ids != null && ids.isEmpty) return [];
  final chunks = ids == null
      ? <List<String>?>[null]
      : <List<String>?>[
          for (var start = 0; start < ids.length; start += 100)
            ids.skip(start).take(100).toList(),
        ];
  final rows = <String, Map<String, dynamic>>{};
  for (final chunk in chunks) {
    final page = await loadReportCursorRows(
      client,
      'report_results_entry_rows_dated_page',
      params: {...params, 'p_entry_ids': chunk},
      cursorParameter: 'p_after_entry_id',
      idColumn: 'entry_id',
    );
    for (final row in page) {
      rows[row['entry_id'].toString()] = row;
    }
  }
  final ordered = rows.keys.toList()..sort();
  return [for (final id in ordered) rows[id]!];
}

/// The printed QR link scopes public judging access to one show/section/breed.
/// Staff report RPCs intentionally cannot serve this account-free workflow.
Future<ReportRows> loadQrResultsEntryRows(
  SupabaseClient client, {
  required String showId,
  required String sectionId,
  required String breed,
}) => loadReportCursorRows(
  client,
  'get_qr_results_entry_rows',
  params: {
    'p_show_id': showId,
    'p_section_id': sectionId,
    'p_breed': breed.trim(),
  },
  cursorParameter: 'p_after_entry_id',
  idColumn: 'entry_id',
);
