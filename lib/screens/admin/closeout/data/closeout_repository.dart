import 'package:supabase_flutter/supabase_flutter.dart';

class CloseoutRepository {
  CloseoutRepository(this.supabase);

  final SupabaseClient supabase;

  Future<List<Map<String, dynamic>>> _selectAll(
    String table,
    String columns, {
    required String filterColumn,
    required Object filterValue,
    String? orderColumn,
  }) async {
    const pageSize = 1000;
    final allRows = <Map<String, dynamic>>[];
    var from = 0;

    while (true) {
      final rows = orderColumn != null && orderColumn.isNotEmpty
          ? await supabase
                .from(table)
                .select(columns)
                .eq(filterColumn, filterValue)
                .order(orderColumn)
                .range(from, from + pageSize - 1)
          : await supabase
                .from(table)
                .select(columns)
                .eq(filterColumn, filterValue)
                .range(from, from + pageSize - 1);
      final batch = List<Map<String, dynamic>>.from(rows);
      allRows.addAll(batch);

      if (batch.length < pageSize) break;
      from += pageSize;
    }

    return allRows;
  }

  // ---------------------------
  // EXISTING METHODS
  // ---------------------------

  Future<Map<String, dynamic>> loadShowBasics(String showId) async {
    return await supabase
        .from('shows')
        .select(
          'id,name,start_date,end_date,location_name,location_address,secretary_name,secretary_email,secretary_phone,created_by,is_national_show',
        )
        .eq('id', showId)
        .single();
  }

  Future<List<Map<String, dynamic>>> loadShowJudges(String showId) async {
    final rows = await supabase
        .from('show_judges')
        .select('judge_id,sort_order')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .order('sort_order');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadResults(String showId) async {
    final rows = await supabase
        .from('results')
        .select('id,entry_id,placing_label,award')
        .eq('show_id', showId);

    return List<Map<String, dynamic>>.from(rows);
  }

  // ---------------------------
  // NEW METHODS FOR UNPAID REPORT
  // ---------------------------

  Future<Map<String, dynamic>?> loadShowFeeSettings(String showId) async {
    final row = await supabase
        .from('show_fee_settings')
        .select(
          'show_id,currency,fee_per_entry,fee_per_show,'
          'multi_show_discount_enabled,multi_show_discount_type,multi_show_discount_value',
        )
        .eq('show_id', showId)
        .maybeSingle();

    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> loadShowSectionFeeSettings(
    String showId,
  ) async {
    final sectionRows = await supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId);

    final sectionIds = List<Map<String, dynamic>>.from(sectionRows)
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (sectionIds.isEmpty) return [];

    final allRows = <Map<String, dynamic>>[];
    const chunkSize = 100;

    for (var start = 0; start < sectionIds.length; start += chunkSize) {
      final end = start + chunkSize > sectionIds.length
          ? sectionIds.length
          : start + chunkSize;
      final chunk = sectionIds.sublist(start, end);

      final rows = await supabase
          .from('show_section_fee_settings')
          .select('section_id,fee_per_entry,fee_per_show,fur_fee')
          .inFilter('section_id', chunk);

      allRows.addAll(List<Map<String, dynamic>>.from(rows));
    }

    return allRows;
  }

  Future<List<Map<String, dynamic>>> loadShowExhibitorBalances(
    String showId,
  ) async {
    return loadShowExhibitorBalancesReport(showId);
  }

  Future<List<Map<String, dynamic>>> loadShowExhibitorBalancesReport(
    String showId,
  ) async {
    const pageSize = 1000;
    final allRows = <Map<String, dynamic>>[];

    for (var from = 0; ; from += pageSize) {
      final to = from + pageSize - 1;
      final rows = await supabase
          .rpc('report_show_exhibitor_balances', params: {'p_show_id': showId})
          .range(from, to);

      final batch = List<Map<String, dynamic>>.from(rows);
      allRows.addAll(batch);

      if (batch.length < pageSize) break;
    }

    return allRows;
  }

  Future<List<Map<String, dynamic>>> loadShowSections(String showId) async {
    return _selectAll(
      'show_sections',
      'id,display_name,kind,letter,sort_order,is_enabled',
      filterColumn: 'show_id',
      filterValue: showId,
      orderColumn: 'sort_order',
    );
  }

  Future<List<Map<String, dynamic>>> loadEntriesForBalanceReport(
    String showId,
  ) async {
    const pageSize = 1000;
    final allRows = <Map<String, dynamic>>[];

    for (var from = 0; ; from += pageSize) {
      final to = from + pageSize - 1;
      final rows = await supabase
          .rpc(
            'report_checkin_entries',
            params: {
              'p_show_id': showId,
              'p_section_id': null,
              'p_include_scratched': false,
            },
          )
          .range(from, to);

      final batch = List<Map<String, dynamic>>.from(rows);
      allRows.addAll(batch);

      if (batch.length < pageSize) break;
    }

    return allRows
        .map((row) {
          final mapped = Map<String, dynamic>.from(row);

          // The check-in RPC uses entry_id. The unpaid balance builder expects id.
          mapped['id'] ??= mapped['entry_id'];

          // Keep these defaults so the existing balance-report filters/calculations
          // can safely consume the RPC rows.
          mapped['status'] ??= 'submitted';
          mapped['is_test'] ??= false;
          mapped['is_disqualified'] ??= false;

          return mapped;
        })
        .where((row) {
          final status = (row['status'] ?? '').toString().trim().toLowerCase();
          final isTest = row['is_test'] == true;
          final scratchedAt = row['scratched_at'];

          return !isTest && scratchedAt == null && status != 'scratched';
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadExhibitorsByIds(
    List<String> exhibitorIds,
  ) async {
    if (exhibitorIds.isEmpty) return [];

    final allRows = <Map<String, dynamic>>[];
    const chunkSize = 500;

    for (var i = 0; i < exhibitorIds.length; i += chunkSize) {
      final chunk = exhibitorIds.skip(i).take(chunkSize).toList();
      final rows = await supabase
          .from('exhibitors')
          .select(
            'id,showing_name,display_name,first_name,last_name,phone,type',
          )
          .inFilter('id', chunk);

      allRows.addAll(List<Map<String, dynamic>>.from(rows));
    }

    return allRows;
  }
}
