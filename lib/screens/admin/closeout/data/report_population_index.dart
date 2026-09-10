/// Counts a population once rather than scanning a section for every entry.
/// Callers own the qualification and grouping rules; records make composite
/// keys safe even when breed/variety names contain separators.
class ReportPopulationIndex {
  final _populations = <Object, ReportPopulation>{};
  static final _empty = ReportPopulation._();

  void add(Object key, String exhibitorId) {
    final population = _populations.putIfAbsent(key, ReportPopulation._);
    population._animals++;
    if (exhibitorId.isNotEmpty) population._exhibitors.add(exhibitorId);
  }

  ReportPopulation operator [](Object key) => _populations[key] ?? _empty;
}

class ReportPopulation {
  ReportPopulation._();
  int _animals = 0;
  final _exhibitors = <String>{};
  int get animals => _animals;
  int get exhibitors => _exhibitors.length;
}
