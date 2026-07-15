// lib/screens/admin/closeout/data/loaders/payback_report_loader.dart

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:supabase/supabase.dart';

import '../../models/base/report_request.dart';
import '../../models/exhibitor/payback_report_data.dart';

typedef PaybackSectionRowsFetcher =
    Future<List<Map<String, dynamic>>> Function(
      String showId,
      String sectionId,
    );
typedef PaybackTimingSink = void Function(Map<String, Object?> event);

class PaybackSectionBatchLoader {
  const PaybackSectionBatchLoader({required this.fetchRows, this.timingSink});

  final PaybackSectionRowsFetcher fetchRows;
  final PaybackTimingSink? timingSink;

  Future<List<Map<String, dynamic>>> load({
    required String showId,
    required Iterable<String> sectionIds,
  }) async {
    final allRows = <Map<String, dynamic>>[];

    // One exact section per request is the bounded unit. Keeping this
    // sequential avoids competing statement-timeout queries in one worker.
    for (final sectionId in sectionIds) {
      final watch = Stopwatch()..start();
      try {
        final rows = await fetchRows(showId, sectionId);
        allRows.addAll(rows);
        watch.stop();
        _log({
          'event': 'payback_section_loaded',
          'show_id': showId,
          'section_id': sectionId,
          'row_count': rows.length,
          'duration_ms': watch.elapsedMilliseconds,
        });
      } catch (error) {
        watch.stop();
        _log({
          'event': 'payback_section_load_failed',
          'show_id': showId,
          'section_id': sectionId,
          'duration_ms': watch.elapsedMilliseconds,
          'error_type': error.runtimeType.toString(),
        });
        rethrow;
      }
    }
    return allRows;
  }

  void _log(Map<String, Object?> event) {
    if (timingSink != null) {
      timingSink!(event);
      return;
    }
    developer.log(jsonEncode(event), name: 'closeout.payback');
  }
}

class PaybackReportLoader {
  final SupabaseClient supabase;
  final PaybackSectionBatchLoader? sectionBatchLoader;

  PaybackReportLoader({required this.supabase, this.sectionBatchLoader});

  Future<PaybackReportData> loadRequest(ReportRequest request) async {
    final sectionIds = request.sectionIds ?? const <String>[];
    if (sectionIds.isEmpty) {
      throw StateError('Payback report requires scoped section IDs.');
    }
    final show = await _loadShow(request.showId);
    final rawRows = await _loadSections(request.showId, sectionIds);
    return _buildReport(show: show, showId: request.showId, rawRows: rawRows);
  }

  Future<PaybackReportData> load({
    required String showId,
    String? sectionId,
  }) async {
    final show = await _loadShow(showId);

    final rawRows = await _loadPaybackRows(
      showId: showId,
      sectionId: sectionId,
    );

    return _buildReport(show: show, showId: showId, rawRows: rawRows);
  }

  PaybackReportData _buildReport({
    required Map<String, dynamic> show,
    required String showId,
    required List<Map<String, dynamic>> rawRows,
  }) {
    final breakdownRows = rawRows
        .map(PaybackBreakdownRow.fromJson)
        .where((row) => row.amountCents > 0)
        .toList();

    final grouped = <String, List<PaybackBreakdownRow>>{};
    final rawByEntryId = <String, Map<String, dynamic>>{
      for (final row in rawRows)
        if ((row['entry_id'] ?? '').toString().isNotEmpty)
          row['entry_id'].toString(): row,
    };

    for (final row in breakdownRows) {
      final exhibitorId = rawByEntryId[row.entryId]?['exhibitor_id']
          ?.toString();

      final key = exhibitorId ?? 'unknown:${row.entryId}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(row);
    }

    final exhibitors = <PaybackExhibitorSummary>[];

    for (final entry in grouped.entries) {
      final rowsForExhibitor = entry.value;

      final matchingRaw =
          rawByEntryId[rowsForExhibitor.first.entryId] ?? const {};

      final total = rowsForExhibitor.fold<int>(
        0,
        (sum, row) => sum + row.amountCents,
      );

      exhibitors.add(
        PaybackExhibitorSummary(
          exhibitorId: entry.key,
          exhibitorNumber: (matchingRaw['exhibitor_number'] ?? '').toString(),
          exhibitorName: (matchingRaw['exhibitor_name'] ?? 'Unknown Exhibitor')
              .toString(),
          mailingAddress: _formatMailingAddress(matchingRaw),
          totalCents: total,
          rows: rowsForExhibitor,
        ),
      );
    }

    exhibitors.sort((a, b) {
      final nameCompare = a.exhibitorName.toLowerCase().compareTo(
        b.exhibitorName.toLowerCase(),
      );
      if (nameCompare != 0) return nameCompare;

      return a.exhibitorNumber.compareTo(b.exhibitorNumber);
    });

    final grandTotal = exhibitors.fold<int>(
      0,
      (sum, exhibitor) => sum + exhibitor.totalCents,
    );

    return PaybackReportData(
      showId: showId,
      showName: (show['name'] ?? 'Show').toString(),
      showDate: _formatShowDate(show),
      showLocation: _formatShowLocation(show),
      exhibitors: exhibitors,
      grandTotalCents: grandTotal,
    );
  }

  Future<List<Map<String, dynamic>>> _loadPaybackRows({
    required String showId,
    String? sectionId,
  }) async {
    if (sectionId != null && sectionId.trim().isNotEmpty) {
      return _loadPaybackRowsForSection(showId: showId, sectionId: sectionId);
    }

    final sectionIds = await _loadEnabledSectionIds(showId);
    return _loadSections(showId, sectionIds);
  }

  Future<List<Map<String, dynamic>>> _loadSections(
    String showId,
    Iterable<String> sectionIds,
  ) {
    final loader =
        sectionBatchLoader ??
        PaybackSectionBatchLoader(
          fetchRows: (showId, sectionId) =>
              _loadPaybackRowsForSection(showId: showId, sectionId: sectionId),
        );
    return loader.load(showId: showId, sectionIds: sectionIds);
  }

  Future<List<Map<String, dynamic>>> _loadPaybackRowsForSection({
    required String showId,
    required String sectionId,
  }) async {
    final rows = await supabase.rpc(
      'report_payback_rows',
      params: {'p_show_id': showId, 'p_section_id': sectionId},
    );

    return (rows as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<String>> _loadEnabledSectionIds(String showId) async {
    final rows = await supabase
        .from('show_sections')
        .select('id')
        .eq('show_id', showId)
        .neq('is_enabled', false)
        .order('sort_order')
        .order('letter');

    return (rows as List? ?? [])
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> _loadShow(String showId) async {
    final result = await supabase
        .from('shows')
        .select('id, name, start_date, end_date, location_name')
        .eq('id', showId)
        .maybeSingle();

    return Map<String, dynamic>.from(result ?? {});
  }

  String _formatMailingAddress(Map<String, dynamic> row) {
    final line1 = row['address_line1']?.toString().trim() ?? '';
    final line2 = row['address_line2']?.toString().trim() ?? '';
    final city = row['city']?.toString().trim() ?? '';
    final state = row['state']?.toString().trim() ?? '';
    final zip = row['zip']?.toString().trim() ?? '';

    final cityStateZip = [
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
      if (zip.isNotEmpty) zip,
    ].join(', ');

    return [
      if (line1.isNotEmpty) line1,
      if (line2.isNotEmpty) line2,
      if (cityStateZip.isNotEmpty) cityStateZip,
    ].join(' • ');
  }

  String? _formatShowDate(Map<String, dynamic> show) {
    final start = show['start_date']?.toString();
    final end = show['end_date']?.toString();

    if (start == null || start.isEmpty) return null;
    if (end == null || end.isEmpty || end == start) return start;

    return '$start – $end';
  }

  String? _formatShowLocation(Map<String, dynamic> show) {
    final locationName = show['location_name']?.toString().trim() ?? '';
    return locationName.isEmpty ? null : locationName;
  }
}
