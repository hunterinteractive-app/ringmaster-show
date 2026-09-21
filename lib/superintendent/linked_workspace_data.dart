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
