/// Labels and stored values shared by Results Entry and control-sheet review.
enum ResultStatus {
  shown('Shown'),
  noShow('No Show'),
  scratched('Scratched'),
  wrongSex('Disqualified - Wrong Sex'),
  wrongVariety('Disqualified - Wrong Variety'),
  wrongClass('Disqualified - Wrong Class'),
  overweight('Disqualified - Overweight', label: 'Disqualified - Weight'),
  wrongTattoo('Disqualified - Wrong Tattoo'),
  otherDq('Disqualified - Other'),
  unworthy('Unworthy of Award');

  const ResultStatus(this.storedValue, {String? label})
    : label = label ?? storedValue;

  final String storedValue;
  final String label;

  bool get isDq => storedValue.startsWith('Disqualified - ');
  bool get isShown => this != noShow && this != scratched;
}

// Scratching an entry uses the existing entry-management action.
final List<ResultStatus> resultEntryStatuses = List.unmodifiable(
  ResultStatus.values.where((status) => status != ResultStatus.scratched),
);

final List<String> kResultStatuses = List.unmodifiable(
  resultEntryStatuses.map((status) => status.storedValue),
);

String resultStatusLabel(String storedValue) =>
    ResultStatus.values
        .where((status) => status.storedValue == storedValue)
        .firstOrNull
        ?.label ??
    storedValue;
