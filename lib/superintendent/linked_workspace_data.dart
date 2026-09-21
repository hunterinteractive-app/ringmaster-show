/// Collapse only complete, authorized groups. Partial access keeps single shows.
List<Map<String, dynamic>> groupSuperintendentShows(
  List<Map<String, dynamic>> shows,
  List<Map<String, dynamic>> workspaces,
) {
  final remaining = {for (final show in shows) show['id'].toString(): show};
  final result = <Map<String, dynamic>>[];
  for (final workspace in workspaces) {
    final ids = List<String>.from(workspace['show_ids'] as List);
    if (ids.length < 2 || !ids.every(remaining.containsKey)) continue;
    final members = ids.map((id) => remaining.remove(id)!).toList();
    result.add({
      ...members.first,
      'name': workspace['name'],
      'workspace_id': workspace['id'],
      'member_shows': members,
    });
  }
  result.addAll(remaining.values);
  return result;
}

/// Count entries by species/breed, preserving show and section identity.
/// Commercial classes stay separate rather than combining meat pens/fryers.
Map<String, Map<String, int>> workspaceBreedTotals(
  List<Map<String, dynamic>> rows,
) {
  final totals = <String, Map<String, int>>{};
  for (final row in rows) {
    final breed = (row['breed'] ?? 'Unknown').toString();
    final variety = (row['variety'] ?? '').toString();
    final label =
        '${row['species'] ?? 'Rabbit'} · $breed'
        '${breed.toLowerCase() == 'commercial' && variety.isNotEmpty ? ' — $variety' : ''}';
    final sections = totals.putIfAbsent(label, () => {});
    final key = '${row['show_id']}/${row['section_id']}';
    sections[key] = (sections[key] ?? 0) + (row['entry_count'] as num).toInt();
  }
  return Map.fromEntries(
    totals.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Give duplicate show letters different labels without changing stored IDs.
Map<String, dynamic> labelWorkspaceRow(
  Map<String, dynamic> row,
  String showName,
) {
  final label = showName
      .split(' (')
      .first
      .replaceFirst(RegExp(r'\s+(Rabbit\s+)?Show$', caseSensitive: false), '')
      .trim();
  final result = Map<String, dynamic>.from(row);
  for (final key in ['show_letter', 'letter', 'section_letter']) {
    final value = row[key] ?? row['show_letter'] ?? row['letter'];
    if (value != null && value.toString().isNotEmpty) {
      result[key] = '$label · $value';
    }
  }
  return result;
}

List<Map<String, dynamic>> collapseWorkspaceMarkers(
  List<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> versions,
) {
  final markers = {
    for (final version in versions)
      version['id']: version['workspace_marker_id'],
  };
  final seen = <String>{};
  return rows.where((row) {
    final marker = markers[row['id']]?.toString();
    return marker == null || seen.add(marker);
  }).toList();
}

/// A shared table judge must be enabled in every source show.
List<Map<String, dynamic>> commonWorkspaceJudges(
  List<List<Map<String, dynamic>>> lists,
) {
  if (lists.isEmpty) return [];
  final byId = <String, Map<String, dynamic>>{};
  for (final judge in lists.first) {
    final id = judge['judge_id']?.toString();
    if (id == null || judge['is_enabled'] == false) continue;
    if (lists.every(
      (list) =>
          list.any((j) => j['judge_id'] == id && j['is_enabled'] != false),
    )) {
      byId[id] = judge;
    }
  }
  return byId.values.toList();
}
