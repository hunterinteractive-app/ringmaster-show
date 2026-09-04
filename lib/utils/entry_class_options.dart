List<String> allowedEntryClassOptions({
  required Object? species,
  Object? classSystem,
  Object? hasPreJunior,
}) {
  final normalizedSpecies = (species ?? '').toString().trim().toLowerCase();

  if (normalizedSpecies == 'cavy') {
    return const ['Junior', 'Intermediate', 'Senior'];
  }

  if (normalizedSpecies != 'rabbit') return const [];

  final normalizedClassSystem = (classSystem ?? 'four')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final isSixClass =
      normalizedClassSystem == 'six' ||
      normalizedClassSystem == 'sixclass' ||
      normalizedClassSystem == '6' ||
      normalizedClassSystem == '6class';
  final includesPreJunior = hasPreJunior == true;

  if (isSixClass) {
    return includesPreJunior
        ? const ['Pre-Junior', 'Junior', 'Intermediate', 'Senior']
        : const ['Junior', 'Intermediate', 'Senior'];
  }

  return includesPreJunior
      ? const ['Pre-Junior', 'Junior', 'Senior']
      : const ['Junior', 'Senior'];
}
