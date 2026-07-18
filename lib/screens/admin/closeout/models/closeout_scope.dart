enum CloseoutSpecies { all, rabbit, cavy }

enum CloseoutScopeKind { entireShow, rabbits, cavies, custom }

class CloseoutSection {
  const CloseoutSection({
    required this.id,
    required this.kind,
    required this.letter,
    required this.displayName,
    required this.breedScope,
    required this.breedIds,
    required this.species,
    required this.isEnabled,
  });

  final String id;
  final String kind;
  final String letter;
  final String displayName;
  final String breedScope;
  final Set<String> breedIds;
  final Set<String> species;
  final bool isEnabled;

  bool get isAllBreed => breedScope.trim().toLowerCase() == 'all';
  bool get isSpecialty => !isAllBreed || breedIds.isNotEmpty;
}

class CloseoutScopeSelection {
  const CloseoutScopeSelection({
    required this.kind,
    this.sectionIds = const <String>{},
    this.showLetters = const <String>{},
    this.sectionKinds = const <String>{},
    this.breedIds = const <String>{},
    this.includeAllBreed = true,
    this.includeSpecialty = true,
  });

  final CloseoutScopeKind kind;
  final Set<String> sectionIds;
  final Set<String> showLetters;
  final Set<String> sectionKinds;
  final Set<String> breedIds;
  final bool includeAllBreed;
  final bool includeSpecialty;
}

class ResolvedCloseoutScope {
  const ResolvedCloseoutScope({
    required this.showId,
    required this.sectionIds,
    required this.species,
    required this.showLetters,
    required this.displayLabel,
    required this.stableScopeKey,
  });

  final String showId;
  final Set<String> sectionIds;
  final Set<String> species;
  final Set<String> showLetters;
  final String displayLabel;
  final String stableScopeKey;

  bool get isEmpty => sectionIds.isEmpty;

  bool matchesArtifactMetadata(Map<String, dynamic> metadata) {
    final runScopeKey = (metadata['run_scope_key'] ?? '').toString().trim();
    if (runScopeKey.isNotEmpty) return runScopeKey == stableScopeKey;

    final artifactKey = (metadata['scope_key'] ?? '').toString().trim();
    if (artifactKey == stableScopeKey) return true;

    final rawIds = metadata['section_ids'];
    if (rawIds is List) {
      final ids = rawIds
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();
      if (ids.isNotEmpty) {
        return ids.length == sectionIds.length && ids.containsAll(sectionIds);
      }
    }

    final sectionId = (metadata['section_id'] ?? '').toString().trim();
    return sectionId.isNotEmpty && sectionIds.contains(sectionId);
  }
}

class CloseoutScopeResolver {
  const CloseoutScopeResolver();

  ResolvedCloseoutScope resolve({
    required String showId,
    required Iterable<CloseoutSection> sections,
    required CloseoutScopeSelection selection,
  }) {
    final enabled = sections.where((section) => section.isEnabled).toList();
    final requestedIds = selection.sectionIds;
    final selected = enabled.where((section) {
      if (selection.kind == CloseoutScopeKind.custom) {
        return requestedIds.contains(section.id);
      }

      if (selection.kind == CloseoutScopeKind.rabbits &&
          !section.species.contains('rabbit')) {
        return false;
      }
      if (selection.kind == CloseoutScopeKind.cavies &&
          !section.species.contains('cavy')) {
        return false;
      }
      if (selection.showLetters.isNotEmpty &&
          !selection.showLetters.contains(section.letter.toUpperCase())) {
        return false;
      }
      if (selection.sectionKinds.isNotEmpty &&
          !selection.sectionKinds.contains(section.kind.toLowerCase())) {
        return false;
      }
      if (!selection.includeAllBreed && section.isAllBreed) return false;
      if (!selection.includeSpecialty && section.isSpecialty) return false;
      if (selection.breedIds.isNotEmpty &&
          section.breedIds.intersection(selection.breedIds).isEmpty) {
        return false;
      }
      return true;
    }).toList();

    final sectionIds = selected.map((section) => section.id).toSet();
    final species = switch (selection.kind) {
      CloseoutScopeKind.rabbits => <String>{'rabbit'},
      CloseoutScopeKind.cavies => <String>{'cavy'},
      _ => selected.expand((section) => section.species).toSet(),
    };
    final letters = selected
        .map((section) => section.letter.trim().toUpperCase())
        .where((letter) => letter.isNotEmpty)
        .toSet();
    final sortedIds = sectionIds.toList()..sort();

    return ResolvedCloseoutScope(
      showId: showId,
      sectionIds: sectionIds,
      species: species,
      showLetters: letters,
      displayLabel: _displayLabel(selected, species),
      stableScopeKey: '$showId:${sortedIds.join(',')}',
    );
  }

  String _displayLabel(List<CloseoutSection> sections, Set<String> species) {
    if (sections.isEmpty) return 'No sections selected';
    final speciesLabel = species.length > 1
        ? 'Rabbit and Cavy'
        : species.contains('cavy')
        ? 'Cavy'
        : species.contains('rabbit')
        ? 'Rabbit'
        : 'Selected';
    final labels =
        sections
            .map(
              (section) =>
                  '${_title(section.kind)} ${section.letter.toUpperCase()}',
            )
            .toSet()
            .toList()
          ..sort();
    return species.length > 1
        ? '$speciesLabel • ${sections.length} sections selected'
        : '$speciesLabel ${labels.join(' + ')}';
  }

  String _title(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 'Section';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}
