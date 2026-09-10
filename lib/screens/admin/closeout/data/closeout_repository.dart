import 'package:supabase/supabase.dart';
import 'report_data_reader.dart';

/// Shared only within one report load (including its leg eligibility check).
/// Never cached across reports, so a later edit is read on the next request.
class ReportResultSnapshot {
  ReportResultSnapshot({
    required this.showId,
    required this.sections,
    required this.rowsBySection,
  });
  final String showId;
  final ReportRows sections;
  final Map<String, ReportRows> rowsBySection;
}

class CloseoutRepository {
  CloseoutRepository(this.supabase);

  final SupabaseClient supabase;

  Future<ReportResultSnapshot> loadResultSnapshot(
    String showId, {
    List<String>? sectionIds,
  }) async {
    final requested = sectionIds?.toSet() ?? const <String>{};
    final sections = await readAllReportPages(
      (from, to) => supabase
          .from('show_sections')
          .select('id,kind,letter,sort_order,judging_date')
          .eq('show_id', showId)
          .eq('is_enabled', true)
          .order('sort_order', ascending: true)
          .order('id', ascending: true)
          .range(from, to),
    );
    sections.removeWhere(
      (s) => requested.isNotEmpty && !requested.contains(s['id'].toString()),
    );
    final rowsBySection = <String, ReportRows>{};
    for (final section in sections) {
      final id = section['id'].toString();
      final letter = (section['letter'] ?? '').toString().trim().toUpperCase();
      // This legacy RPC defines the result ordering. Do not replace its
      // row shape or domain rules with a direct entries-table query.
      rowsBySection[id] = await readAllReportPages(
        (from, to) async => List<Map<String, dynamic>>.from(
          await supabase
              .rpc(
                'report_results_entry_rows',
                params: {
                  'p_show_id': showId,
                  'p_section_id': id,
                  'p_show_letter': letter.isEmpty ? null : letter,
                },
              )
              .range(from, to),
        ),
      );
    }
    return ReportResultSnapshot(
      showId: showId,
      sections: sections,
      rowsBySection: rowsBySection,
    );
  }

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
                .order('id')
                .range(from, from + pageSize - 1)
          : await supabase
                .from(table)
                .select(columns)
                .eq(filterColumn, filterValue)
                .order('id')
                .range(from, from + pageSize - 1);
      final batch = List<Map<String, dynamic>>.from(rows);
      allRows.addAll(batch);

      if (batch.isEmpty) break;
      from = allRows.length;
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
          'id,name,start_date,end_date,location_name,location_address,secretary_name,secretary_email,secretary_phone,created_by,is_national_show,national_show_section_id',
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
    return _selectAll(
      'results',
      'id,entry_id,placing_label,award',
      filterColumn: 'show_id',
      filterValue: showId,
    );
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
    String showId, {
    List<String>? sectionIds,
    bool requireExactAllocation = true,
  }) async {
    final exactSectionIds = sectionIds ?? await _loadEnabledSectionIds(showId);
    if (exactSectionIds.isEmpty) {
      throw ArgumentError.value(
        exactSectionIds,
        'sectionIds',
        'At least one enabled Closeout section is required.',
      );
    }

    const pageSize = 1000;
    final allRows = <Map<String, dynamic>>[];

    for (var from = 0; ; from = allRows.length) {
      final to = from + pageSize - 1;
      final rows = await supabase
          .rpc(
            'report_show_exhibitor_balances_scoped',
            params: {'p_show_id': showId, 'p_section_ids': exactSectionIds},
          )
          .range(from, to);

      final batch = List<Map<String, dynamic>>.from(rows);
      allRows.addAll(batch);

      if (batch.isEmpty) break;
    }

    if (requireExactAllocation) {
      final ambiguous = allRows.where(
        (row) => row['payment_allocation_status'] == 'ambiguous',
      );
      if (ambiguous.isNotEmpty) {
        throw ScopedBalanceAllocationException(
          ambiguous
              .map((row) => row['payment_allocation_ambiguity_reasons'])
              .where((value) => value != null)
              .toList(),
        );
      }
    }

    return allRows;
  }

  Future<List<String>> _loadEnabledSectionIds(String showId) async {
    final rows = await supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .eq('is_enabled', true)
        .order('id');
    return List<Map<String, dynamic>>.from(rows)
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
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

    for (var from = 0; ; from = allRows.length) {
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

      if (batch.isEmpty) break;
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
    return loadReportRowsByIds(
      supabase,
      table: 'exhibitors',
      columns: 'id,showing_name,display_name,first_name,last_name,phone,type',
      ids: exhibitorIds,
    );
  }
}

final class ScopedBalanceAllocationException implements Exception {
  const ScopedBalanceAllocationException(this.reasons);

  final List<Object?> reasons;

  @override
  String toString() =>
      'Financial payments or discounts are recorded only at the whole-show '
      'level and cannot be allocated reliably to the selected sections.';
}
