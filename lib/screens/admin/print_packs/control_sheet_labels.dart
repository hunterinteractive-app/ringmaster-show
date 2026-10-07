/// A shared heading may name a judge only when every row has that same judge.
/// In particular, one assigned cavy class must not label unassigned rabbits.
String controlSheetJudgeLabel(Iterable<String> names) {
  final labels = names.map((name) => name.trim()).toList();
  if (labels.isEmpty || labels.any((name) => name.isEmpty)) return '';
  final distinct = labels.toSet();
  return distinct.length == 1 ? distinct.single : '';
}

/// Dedicated fur entries store White/Colored separately from regular variety.
/// Keep missing classifications blank instead of guessing a competition group.
String controlSheetFurColor(Map<String, dynamic> row) {
  final explicit = (row['fur_variety'] ?? '').toString().trim();
  final value = explicit.isNotEmpty
      ? explicit
      : (row['variety'] ?? '').toString().trim();
  switch (value.toLowerCase()) {
    case 'white':
      return 'White';
    case 'colored':
    case 'coloured':
      return 'Colored';
    case 'fur':
    case 'wool':
    case 'fur / wool':
    case 'fur/wool':
      return '';
    default:
      return value;
  }
}

// Display spelling must not split the totals for the same variety or class.
String controlSheetCountLabel(Object? value) => (value ?? '')
    .toString()
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();
