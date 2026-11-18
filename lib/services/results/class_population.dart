/// Whether a judged animal contributes to its entered class's competition
/// population. This is separate from eligibility to receive a placement/award.
bool countsTowardClassPopulation(Map<String, dynamic> entry) {
  if ((entry['scratched_at'] ?? '').toString().trim().isNotEmpty ||
      entry['is_shown'] == false) {
    return false;
  }
  final outcome =
      '${entry['result_status'] ?? ''} '
              '${entry['disqualified_reason'] ?? ''}'
          .toLowerCase()
          .replaceAll(RegExp(r'[_-]+'), ' ');
  return !outcome.contains('no show') &&
      !outcome.contains('noshow') &&
      !outcome.contains('scratch') &&
      !outcome.contains('wrong sex') &&
      !outcome.contains('wrong variety') &&
      !outcome.contains('wrong class');
}
