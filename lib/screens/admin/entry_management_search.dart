bool entryManagementSearchMatches({
  required Map<String, dynamic> entry,
  required String exhibitorName,
  required String query,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;

  final fields = <String>[
    exhibitorName,
    (entry['animal_name'] ?? '').toString(),
    (entry['tattoo'] ?? '').toString(),
    (entry['coop_number'] ?? '').toString(),
    (entry['breed'] ?? '').toString(),
    (entry['variety'] ?? '').toString(),
    (entry['fur_variety'] ?? '').toString(),
    (entry['sex'] ?? '').toString(),
    (entry['class_name'] ?? '').toString(),
    (entry['notes'] ?? '').toString(),
    (entry['species'] ?? '').toString(),
    ((entry['is_fur'] == true) ? 'fur wool fur/wool' : ''),
  ].join(' ').toLowerCase();

  return fields.contains(normalizedQuery);
}
