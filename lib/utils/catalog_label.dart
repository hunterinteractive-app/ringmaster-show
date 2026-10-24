/// Resolve typed text to the catalog's spelling, without guessing at typos.
/// A selected ID also prevents a stale breed selection from being saved.
String? canonicalCatalogLabel(
  String typed,
  Iterable<Map<String, dynamic>> options, {
  String? selectedId,
}) {
  final key = typed.trim().toLowerCase();
  if (key.isEmpty) return null;
  final labels = options
      .where(
        (option) =>
            (selectedId == null || option['id']?.toString() == selectedId) &&
            (option['name'] ?? '').toString().trim().toLowerCase() == key,
      )
      .map((option) => option['name'].toString())
      .toSet();
  return labels.length == 1 ? labels.single : null;
}
