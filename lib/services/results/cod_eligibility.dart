/// COD breeds/varieties may receive variety and breed awards, but no final
/// awards or legs. Match a whole
/// marker, not arbitrary names containing the letters "cod".
final _codMarker = RegExp(r'\bCOD\b', caseSensitive: false);

bool _hasCodMarker(Map<String, dynamic> entry) => const [
  'breed',
  'breed_name',
  'variety',
  'variety_name',
  'rabbit_variety_name',
  'rabbit_group_name',
].any((key) => _codMarker.hasMatch((entry[key] ?? '').toString()));

const codAwardIneligibilityReason =
    'COD entries may receive class placements, BOV, BOSV, BOB, and BOSB, but cannot earn legs or final awards.';

bool codAwardsDisallowed(Iterable<String> awards) => awards.any(
  (award) => !const {
    'BOV',
    'BOSV',
    'BOB',
    'BOSB',
  }.contains(award.trim().toUpperCase()),
);

// Server-resolved status is authoritative even when legacy names retain COD.
String entryRecognitionStatus(Map<String, dynamic> entry) {
  final status = entry['recognition_status']?.toString();
  if (const {'cod', 'recognized', 'retired', 'unrecognized'}.contains(status)) {
    return status!;
  }
  return _hasCodMarker(entry) ? 'cod' : 'recognized';
}

bool isCodEntry(Map<String, dynamic> entry) =>
    entryRecognitionStatus(entry) == 'cod';
bool isRecognitionRestricted(Map<String, dynamic> entry) =>
    entryRecognitionStatus(entry) != 'recognized';
bool recognitionAwardsDisallowed(
  Map<String, dynamic> entry,
  Iterable<String> awards,
) {
  final status = entryRecognitionStatus(entry);
  return status == 'cod'
      ? codAwardsDisallowed(awards)
      : status != 'recognized' && awards.isNotEmpty;
}

String recognitionIneligibilityReason(Map<String, dynamic> entry) =>
    isCodEntry(entry)
    ? codAwardIneligibilityReason
    : 'This breed or variety is retired or has no judging date. Awards and legs are not allowed.';
