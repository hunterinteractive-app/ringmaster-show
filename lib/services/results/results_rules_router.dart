import 'cavy_results_rules.dart';
import 'rabbit_results_rules.dart';
import 'results_rules.dart';

const RabbitResultsRules _rabbitRules = RabbitResultsRules();
const CavyResultsRules _cavyRules = CavyResultsRules();

ResultsRules rulesForSpecies(Object? species) {
  return switch (normalizeResultsSpeciesStrict(species)) {
    'rabbit' => _rabbitRules,
    'cavy' => _cavyRules,
    _ => throw UnsupportedResultsSpecies((species ?? '').toString()),
  };
}

ResultsRules rulesForEntry(Map<String, dynamic> entry) {
  return rulesForSpecies(entry['species']);
}
