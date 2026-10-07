import 'package:supabase_flutter/supabase_flutter.dart';
import '../closeout/data/report_data_reader.dart';

String _key(Object? value) => (value ?? '').toString().trim().toLowerCase();

/// Only actual breed assignments establish a printable judging order.
class ControlSheetJudgingOrder {
  ControlSheetJudgingOrder(List<Map<String, dynamic>> assignments)
    : rows = assignments
          .where(
            (row) =>
                _key(row['breed_id']).isNotEmpty &&
                !_key(row['breed_id']).startsWith('__') &&
                _key(row['judge_id']).isNotEmpty &&
                _key(row['table_number']).isNotEmpty,
          )
          .toList() {
    rows.sort((a, b) {
      final at = _key(a['table_number']);
      final bt = _key(b['table_number']);
      final an = int.tryParse(at);
      final bn = int.tryParse(bt);
      final table = an != null && bn != null
          ? an.compareTo(bn)
          : at.compareTo(bt);
      if (table != 0) return table;
      final order = ((a['sort_order'] as num?) ?? 0).compareTo(
        (b['sort_order'] as num?) ?? 0,
      );
      return order != 0 ? order : _key(a['id']).compareTo(_key(b['id']));
    });
  }

  final List<Map<String, dynamic>> rows;
  bool get isAvailable => rows.isNotEmpty;

  int rank(Map<String, dynamic> page) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (_key(row['section_id']) != _key(page['sectionId'])) continue;
      if (_key(row['breed_id']) != _key(page['breed'])) continue;
      if (_key(row['species']).isNotEmpty &&
          _key(row['species']) != _key(page['species'])) {
        continue;
      }
      final variety = _key(row['variety_key']);
      if (variety.isNotEmpty && variety != _key(page['color'])) continue;
      return i;
    }
    return rows.length; // Unassigned sheets are retained at the end.
  }
}

Future<ControlSheetJudgingOrder> loadControlSheetJudgingOrder(
  SupabaseClient client,
  String showId,
) async => ControlSheetJudgingOrder(
  await readAllReportPages(
    (from, to) async => List<Map<String, dynamic>>.from(
      await client
          .from('show_judging_assignments')
          .select(
            'id,section_id,breed_id,species,variety_key,judge_id,table_number,sort_order',
          )
          .eq('show_id', showId)
          .order('id')
          .range(from, to),
    ),
  ),
);
