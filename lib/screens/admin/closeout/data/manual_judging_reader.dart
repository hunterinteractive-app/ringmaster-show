import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/reporting_core/network/transient_retry.dart';
import 'report_data_reader.dart';

Future<ReportRows> loadJudgingBreedIndex(
  SupabaseClient client, {
  required String showId,
  required String sectionId,
}) async {
  final response = await retryTransient(
    () => client.rpc(
      'get_judging_breed_index',
      params: {'p_show_id': showId, 'p_section_id': sectionId},
    ),
  );
  if (response is! List) throw StateError('Invalid judging breed index.');
  return response.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

/// Null breed is reserved for an explicitly requested whole-section check.
/// Every page retains its scope and is exhausted even under a lower API cap.
/// Small pages keep large breeds from monopolizing the shared connection pool.
Future<ReportRows> loadManualJudgingRows(
  SupabaseClient client, {
  required String showId,
  String? sectionId,
  String? breed,
  String? entryId,
}) => loadReportCursorRows(
  client,
  'get_judging_entry_rows_page',
  params: {
    'p_show_id': showId,
    'p_section_id': sectionId,
    'p_breed': breed,
    'p_entry_ids': entryId == null ? null : [entryId],
    'p_page_size': 250,
  },
  cursorParameter: 'p_after_entry_id',
  idColumn: 'entry_id',
);
