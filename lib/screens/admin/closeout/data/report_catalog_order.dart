import 'package:supabase/supabase.dart';

import 'report_data_reader.dart';

/// Adds catalog ranks to raw entry queries that do not use the reporting RPC.
/// Case-insensitive matching also covers historical free-typed labels.
Future<List<Map<String, dynamic>>> withReportCatalogOrder(
  SupabaseClient client,
  String showId,
  List<Map<String, dynamic>> rows, {
  Iterable<String> additionalShowIds = const [],
}) async {
  if (rows.isEmpty) return rows;
  String key(Object? value) => (value ?? '').toString().trim().toLowerCase();
  final wanted = rows
      .map((row) => '${key(row['species'])}|${key(row['breed'])}')
      .toSet();
  final scopes = {
    showId,
    ...additionalShowIds,
  }.where((id) => id.isNotEmpty).toList();
  final breeds = await readAllReportPages(
    (from, to) => client
        .from('breeds')
        .select('id,name,species,local_show_id')
        .or(
          scopes.isEmpty
              ? 'local_show_id.is.null'
              : 'local_show_id.is.null,local_show_id.in.(${scopes.join(',')})',
        )
        .order('id')
        .range(from, to),
  );
  final selected = <String, Map<String, dynamic>>{};
  for (final breed in breeds) {
    final k = '${key(breed['species'])}|${key(breed['name'])}';
    if (!wanted.contains(k)) continue;
    selected.putIfAbsent('$k|${key(breed['local_show_id'])}', () => breed);
  }
  final varieties = await loadReportRowsByIds(
    client,
    table: 'varieties',
    columns: 'id,breed_id,name,sort_order,group_id',
    ids: selected.values.map((b) => b['id'].toString()),
    idColumn: 'breed_id',
  );
  final groups = await loadReportRowsByIds(
    client,
    table: 'variety_groups',
    columns: 'id,name,sort_order',
    ids: varieties.map((v) => v['group_id']?.toString() ?? ''),
  );
  final groupsById = {for (final group in groups) group['id']: group};
  final varietiesByKey = <String, Map<String, dynamic>>{};
  for (final variety in varieties) {
    varietiesByKey.putIfAbsent(
      '${variety['breed_id']}|${key(variety['name'])}',
      () => variety,
    );
  }
  return rows.map((row) {
    final scope = key(row['show_id']).isEmpty
        ? key(showId)
        : key(row['show_id']);
    final breedKey = '${key(row['species'])}|${key(row['breed'])}';
    final breed = selected['$breedKey|$scope'] ?? selected['$breedKey|'];
    final variety = varietiesByKey['${breed?['id']}|${key(row['variety'])}'];
    final group = groupsById[variety?['group_id']];
    return <String, dynamic>{
      ...row,
      if (variety != null) 'variety_sort_order': variety['sort_order'],
      if (group != null) ...{
        'group_sort_order': group['sort_order'],
        'group_name': group['name'],
      },
    };
  }).toList();
}
