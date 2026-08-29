/// Returns whether [species] identifies a cavy entry.
bool isCavySpecies(Object? species) {
  final normalized = (species ?? '').toString().trim().toLowerCase();
  return normalized == 'cavy' || normalized == 'cavies';
}

/// Returns the canonical display label for an animal's sex.
///
/// Legacy cavy records may contain the rabbit labels `Buck` and `Doe`.
/// Those values are intentionally left unchanged in storage, but every cavy
/// presentation surface must render them as `Boar` and `Sow`.
String displaySexForSpecies({
  required Object? species,
  required Object? sex,
  Object? className,
}) {
  final raw = (sex ?? '').toString().trim();
  if (!isCavySpecies(species)) return raw;

  String? fromWords(String value) {
    final words = RegExp(
      r'[a-z]+',
    ).allMatches(value.toLowerCase()).map((match) => match.group(0)!).toSet();

    if (words.any(const {'boar', 'buck', 'male'}.contains)) return 'Boar';
    if (words.any(const {'sow', 'doe', 'female'}.contains)) return 'Sow';
    return null;
  }

  final rawLabel = fromWords(raw);
  if (rawLabel != null) return rawLabel;

  switch (raw.toLowerCase()) {
    case 'b':
    case 'm':
      return 'Boar';
    case 's':
    case 'd':
    case 'f':
      return 'Sow';
    default:
      return fromWords((className ?? '').toString()) ?? raw;
  }
}

/// Rewrites rabbit sex terms embedded in a cavy class label.
String displayClassNameForSpecies({
  required Object? species,
  required Object? className,
}) {
  final raw = (className ?? '').toString().trim();
  if (!isCavySpecies(species) || raw.isEmpty) return raw;

  return raw
      .replaceAllMapped(
        RegExp(r'\bbucks\b', caseSensitive: false),
        (_) => 'Boars',
      )
      .replaceAllMapped(
        RegExp(r'\bbuck\b', caseSensitive: false),
        (_) => 'Boar',
      )
      .replaceAllMapped(
        RegExp(r'\bdoes\b', caseSensitive: false),
        (_) => 'Sows',
      )
      .replaceAllMapped(RegExp(r'\bdoe\b', caseSensitive: false), (_) => 'Sow');
}

/// Normalizes display-facing fields on a copied report or entry row.
void normalizeSpeciesSexPresentation(
  Map<String, dynamic> row, {
  Object? speciesOverride,
}) {
  final overrideText = (speciesOverride ?? '').toString().trim();
  final species = overrideText.isNotEmpty
      ? speciesOverride
      : row['species'] ?? row['animal_species'] ?? row['entry_species'];
  row['sex'] = displaySexForSpecies(
    species: species,
    sex: row['sex'],
    className: row['class_name'],
  );
  row['class_name'] = displayClassNameForSpecies(
    species: species,
    className: row['class_name'],
  );
}
