/// Auto Fill requires a known judge type for every species in an assignment.
/// Unknown types are not assumed to be rabbit or dual qualifications.
bool lineupJudgeSupportsSpecies(
  Map<String, dynamic> judge,
  Iterable<String> species,
) {
  if (judge['is_enabled'] == false) return false;
  final type = (judge['judge_type'] ?? '').toString().trim().toLowerCase();
  final required = species.map((s) => s.trim().toLowerCase()).toSet();
  if (required.isEmpty || required.any((s) => s != 'rabbit' && s != 'cavy')) {
    return false;
  }
  if (type == 'dual') return true;
  return (type == 'rabbit' || type == 'cavy') &&
      required.every((s) => s == type);
}
