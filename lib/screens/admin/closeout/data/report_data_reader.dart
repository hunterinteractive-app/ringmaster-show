import 'package:ringmaster_show/reporting_core/network/transient_retry.dart';
import 'package:supabase/supabase.dart';

typedef ReportRows = List<Map<String, dynamic>>;

/// Read to exhaustion, including when the server caps a page below pageSize.
/// The query must supply a stable order (or retain its reporting RPC's order).
/// A failed page propagates: a partial report must not look successful.
Future<ReportRows> readAllReportPages(
  Future<ReportRows> Function(int from, int to) readPage, {
  int pageSize = 1000,
}) async {
  if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
  final rows = <Map<String, dynamic>>[];
  while (true) {
    final page = await retryTransient(
      () => readPage(rows.length, rows.length + pageSize - 1),
    );
    if (page.isEmpty) return rows;
    rows.addAll(page);
  }
}

/// Keep UUID filters comfortably below gateway request-URL limits. Pagination
/// is also needed for one-to-many lookups such as awards for a set of entries.
Future<ReportRows> loadReportRowsByIds(
  SupabaseClient client, {
  required String table,
  required String columns,
  required Iterable<String> ids,
  String idColumn = 'id',
  Map<String, Object> filters = const {},
  List<String> orderColumns = const ['id'],
}) async {
  if (orderColumns.isEmpty) {
    throw ArgumentError.value(orderColumns, 'orderColumns');
  }
  final uniqueIds = ids
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  final rows = <Map<String, dynamic>>[];
  const chunkSize = 100;
  for (var start = 0; start < uniqueIds.length; start += chunkSize) {
    final chunk = uniqueIds.skip(start).take(chunkSize).toList();
    rows.addAll(
      await readAllReportPages((from, to) {
        var query = client
            .from(table)
            .select(columns)
            .inFilter(idColumn, chunk);
        for (final filter in filters.entries) {
          query = query.eq(filter.key, filter.value);
        }
        var ordered = query.order(orderColumns.first, ascending: true);
        for (final column in orderColumns.skip(1)) {
          ordered = ordered.order(column, ascending: true);
        }
        return ordered.range(from, to);
      }),
    );
  }
  return rows;
}

/// Only for read-only, set-returning reporting functions. A scalar JSON array
/// is already one response and must not be paginated. Retains the RPC ordering.
Future<ReportRows> loadReportRpcRows(
  SupabaseClient client,
  String function, {
  required Map<String, dynamic> params,
}) => readAllReportPages(
  (from, to) async => List<Map<String, dynamic>>.from(
    await client.rpc(function, params: params).range(from, to),
  ),
);

/// For RPCs that bound work internally and return rows ordered by a stable ID.
/// Removing earlier rows during check-in must not shift an offset past entries.
Future<ReportRows> loadReportCursorRows(
  SupabaseClient client,
  String function, {
  required Map<String, dynamic> params,
  required String cursorParameter,
  required String idColumn,
}) async {
  final rows = <Map<String, dynamic>>[];
  String? after;
  while (true) {
    final page = List<Map<String, dynamic>>.from(
      await retryTransient(
        () => client.rpc(
          function,
          params: {
            ...params,
            cursorParameter: after,
            'p_page_size': params['p_page_size'] ?? 1000,
          },
        ),
      ),
    );
    if (page.isEmpty) return rows;
    for (final row in page) {
      final id = row[idColumn]?.toString() ?? '';
      if (id.isEmpty || (after != null && id.compareTo(after) <= 0)) {
        throw StateError(
          'Cursor pagination did not advance in identity order.',
        );
      }
      after = id;
      rows.add(row);
    }
  }
}

/// Optional legacy fields may be absent on an older schema. Transport,
/// authorization, and query failures must not become empty report data.
bool isReportSchemaCompatibilityError(Object error) =>
    error is PostgrestException &&
    const {
      '42703',
      '42P01',
      'PGRST202',
      'PGRST204',
      'PGRST205',
    }.contains(error.code);
