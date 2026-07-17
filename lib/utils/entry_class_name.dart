String canonicalEntryClassName(String raw) {
  final value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (value.isEmpty) return '';

  final normalized = value
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final ageOnly = normalized.replaceFirst(
    RegExp(r'\s+(buck|doe|boar|sow|male|female)s?$'),
    '',
  );

  return switch (ageOnly) {
    'sr' || 'senior' => 'Senior',
    'int' || 'intermediate' => 'Intermediate',
    'jr' || 'junior' => 'Junior',
    'pre jr' || 'pre junior' => 'Pre-Junior',
    _ => value,
  };
}
