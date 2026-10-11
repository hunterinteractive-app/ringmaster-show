/// COD breeds/varieties may receive class placements, BOV, and BOSV, but no higher awards or legs. Match a whole
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
    'COD entries may receive class placements, BOV, and BOSV only, and cannot earn legs.';

bool codAwardsDisallowed(Iterable<String> awards) => awards.any(
  (award) => !const {'BOV', 'BOSV'}.contains(award.trim().toUpperCase()),
);
