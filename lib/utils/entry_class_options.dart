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

/// Uses the same age thresholds as exhibitor entry suggestions.
String? suggestEntryClassFromDob({
  required Map<String, dynamic> animal,
  required Map<String, dynamic> breed,
  required DateTime? showDate,
}) {
  if (showDate == null || animal['is_dob_unknown'] == true || breed.isEmpty) {
    return null;
  }
  final dob = DateTime.tryParse((animal['birth_date'] ?? '').toString());
  if (dob == null) return null;
  final days = DateTime(
    showDate.year,
    showDate.month,
    showDate.day,
  ).difference(DateTime(dob.year, dob.month, dob.day)).inDays;
  if (days < 0) return null;
  final months = days / 30.4375;
  final species = (animal['species'] ?? '').toString().toLowerCase();
  if (species == 'cavy') {
    return months < 4
        ? 'Junior'
        : months < 6
        ? 'Intermediate'
        : 'Senior';
  }
  if (species != 'rabbit') return null;
  if (breed['has_prejunior'] == true) {
    final sex = (animal['sex'] ?? '').toString().toLowerCase();
    final key =
        (breed['name'] ?? '').toString().toLowerCase() == 'giant chinchilla'
        ? 'prejunior_${sex}_age_max_months'
        : 'prejunior_age_max_months';
    final maximum = breed[key] as num?;
    if (maximum != null && months < maximum) return 'Pre-Junior';
  }
  if (months < 6) return 'Junior';
  final options = allowedEntryClassOptions(
    species: species,
    classSystem: breed['class_system'],
  );
  return options.contains('Intermediate') && months <= 8
      ? 'Intermediate'
      : 'Senior';
}
