/// Keeps an animal's sections together, independent of creation order or edits.
String entryAnimalKey(Map<String, dynamic> row) {
  String value(String key) => (row[key] ?? '').toString().trim().toLowerCase();
  final identity = value('meat_pen_id').isNotEmpty
      ? 'pen:${value('meat_pen_id')}'
      : value('animal_id').isNotEmpty
      ? 'animal:${value('animal_id')}'
      : value('tattoo').isNotEmpty
      ? 'legacy:${value('species')}:${value('breed')}:${value('tattoo')}'
      : 'entry:${value('id')}';
  return '${value('show_id')}:${value('exhibitor_id')}:$identity';
}

int compareEntrySections(Map<String, dynamic> a, Map<String, dynamic> b) {
  String value(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim().toUpperCase();
  int kind(Map<String, dynamic> row) => switch (value(row, 'kind')) {
    'OPEN' => 0,
    'YOUTH' => 1,
    _ => 2,
  };
  final category = kind(a).compareTo(kind(b));
  if (category != 0) return category;
  final letter = value(a, 'letter').compareTo(value(b, 'letter'));
  if (letter != 0) return letter;
  final rank = (int.tryParse('${a['sort_order']}') ?? 9999).compareTo(
    int.tryParse('${b['sort_order']}') ?? 9999,
  );
  if (rank != 0) return rank;
  return value(a, 'display_name').compareTo(value(b, 'display_name'));
}

List<List<Map<String, dynamic>>> groupExhibitorEntries(
  Iterable<Map<String, dynamic>> rows,
  Map<String, Map<String, dynamic>> sections,
) {
  final buckets = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    buckets.putIfAbsent(entryAnimalKey(row), () => []).add(row);
  }
  final groups = buckets.values.toList();
  for (final group in groups) {
    group.sort((a, b) {
      final section = compareEntrySections(
        sections['${a['section_id']}'] ?? {},
        sections['${b['section_id']}'] ?? {},
      );
      if (section != 0) return section;
      final sectionId = '${a['section_id']}'.compareTo('${b['section_id']}');
      if (sectionId != 0) return sectionId;
      if ((a['is_fur'] == true) != (b['is_fur'] == true)) {
        return a['is_fur'] == true ? 1 : -1;
      }
      return '${a['id']}'.compareTo('${b['id']}');
    });
  }
  String label(List<Map<String, dynamic>> group) {
    final row = group.first;
    return '${row['species'] ?? ''}|${row['breed'] ?? ''}|${row['tattoo'] ?? ''}|${entryAnimalKey(row)}'
        .toLowerCase();
  }

  groups.sort((a, b) => label(a).compareTo(label(b)));
  return groups;
}
