/// COD breeds/varieties compete for class placements only. Match a whole
/// marker, not arbitrary names containing the letters "cod".
final _codMarker = RegExp(r'\bCOD\b', caseSensitive: false);

bool isCodEntry(Map<String, dynamic> entry) => const [
  'breed',
  'breed_name',
  'variety',
  'variety_name',
  'rabbit_variety_name',
  'rabbit_group_name',
].any((key) => _codMarker.hasMatch((entry[key] ?? '').toString()));

const codAwardIneligibilityReason =
    'COD entries are eligible for class placements only, not higher awards.';
