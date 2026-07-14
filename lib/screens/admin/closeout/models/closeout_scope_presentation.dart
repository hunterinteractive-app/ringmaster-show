import 'closeout_scope.dart';

class CloseoutScopePresentation {
  const CloseoutScopePresentation._();

  static String speciesLabel(ResolvedCloseoutScope scope) {
    if (scope.species.contains('rabbit') && scope.species.contains('cavy')) {
      return 'Rabbit + Cavy';
    }
    if (scope.species.contains('cavy')) return 'Cavy';
    if (scope.species.contains('rabbit')) return 'Rabbit';
    return 'Selected Scope';
  }

  static String compactLabel(ResolvedCloseoutScope scope) {
    final count = scope.sectionIds.length;
    final species = speciesLabel(scope);
    if (count > 2) {
      return '$species • $count sections';
    }

    final detailed = scope.displayLabel.replaceFirst(
      'Rabbit and Cavy',
      'Rabbit + Cavy',
    );
    if (detailed.startsWith('$species ')) {
      return detailed.replaceFirst('$species ', '$species • ');
    }
    return detailed;
  }

  static String primarySummary(ResolvedCloseoutScope scope) {
    return scope.sectionIds.length > 2
        ? compactLabel(scope)
        : speciesLabel(scope);
  }

  static String tooltipLabel(ResolvedCloseoutScope scope) {
    return scope.displayLabel
        .replaceFirst('Rabbit and Cavy', 'Rabbit + Cavy')
        .replaceAll(' + ', ', ');
  }
}

class CloseoutSectionPresentation {
  const CloseoutSectionPresentation._();

  static String displayLabel({
    required String kind,
    required String letter,
    required bool isAllBreed,
    required String displayName,
  }) {
    final kindLabel = _titleCase(kind, fallback: 'Section');
    final sectionType = isAllBreed
        ? 'All Breed'
        : displayName.trim().isNotEmpty
        ? displayName.trim()
        : 'Specialty';
    return '$kindLabel ${letter.trim().toUpperCase()} • $sectionType';
  }

  static String summaryLabel({
    required List<String> species,
    required bool isSpecialty,
    required int entryCount,
  }) {
    final speciesLabel = species.length == 1
        ? _titleCase(species.first, fallback: 'Section')
        : species.isEmpty
        ? 'Section'
        : 'Rabbit + Cavy';
    final typeLabel = isSpecialty ? ' Specialty' : '';
    return '$speciesLabel$typeLabel • '
        '$entryCount entr${entryCount == 1 ? 'y' : 'ies'}';
  }

  static String _titleCase(String value, {required String fallback}) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return fallback;
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}

bool closeoutScopeHasCompletedRun({
  required String selectedStableScopeKey,
  required Map<String, String> completedRunIdsByScope,
}) {
  return (completedRunIdsByScope[selectedStableScopeKey] ?? '')
      .trim()
      .isNotEmpty;
}
