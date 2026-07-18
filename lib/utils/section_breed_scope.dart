String normalizeBreedName(Object? value) =>
    value?.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ??
    '';

Set<String> allowedBreedNamesForSection(Map<String, dynamic> section) {
  final raw = section['allowed_breed_names'];
  if (raw is! Iterable) return const <String>{};
  return raw.map(normalizeBreedName).where((name) => name.isNotEmpty).toSet();
}

bool sectionAllowsBreed(Map<String, dynamic> section, Object? breed) {
  final scope = (section['breed_scope'] ?? 'all')
      .toString()
      .trim()
      .toLowerCase();
  if (scope == 'all' || scope == 'all_breed' || scope == 'meat_only') {
    return true;
  }
  if (scope != 'single' && scope != 'limited') return false;
  final normalizedBreed = normalizeBreedName(breed);
  return normalizedBreed.isNotEmpty &&
      allowedBreedNamesForSection(section).contains(normalizedBreed);
}

String sectionBreedScopeDescription(Map<String, dynamic> section) {
  final names = allowedBreedNamesForSection(section).toList()..sort();
  return names.isEmpty ? 'its configured breeds' : names.join(', ');
}

Future<void> attachAllowedBreedNames({
  required List<Map<String, dynamic>> sections,
  required Future<List<Map<String, dynamic>>> Function() loadBreeds,
}) async {
  final restricted = sections.where((section) {
    final scope = (section['breed_scope'] ?? 'all')
        .toString()
        .trim()
        .toLowerCase();
    return scope == 'single' || scope == 'limited';
  }).toList();
  if (restricted.isEmpty) return;

  final breeds = await loadBreeds();
  final namesById = <String, String>{
    for (final breed in breeds)
      if ((breed['id'] ?? '').toString().isNotEmpty)
        breed['id'].toString(): (breed['name'] ?? '').toString().trim(),
  };

  for (final section in restricted) {
    final ids = (section['allowed_breed_ids'] as Iterable? ?? const []).map(
      (id) => id.toString(),
    );
    section['allowed_breed_names'] = ids
        .map((id) => namesById[id])
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }
}
