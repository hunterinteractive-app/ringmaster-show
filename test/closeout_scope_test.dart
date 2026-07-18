import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/closeout_scope.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/closeout_scope_presentation.dart';

void main() {
  const resolver = CloseoutScopeResolver();
  const sections = <CloseoutSection>[
    CloseoutSection(
      id: 'r-open-a',
      kind: 'open',
      letter: 'A',
      displayName: 'Open A',
      breedScope: 'all',
      breedIds: {},
      species: {'rabbit'},
      isEnabled: true,
    ),
    CloseoutSection(
      id: 'r-youth-a',
      kind: 'youth',
      letter: 'A',
      displayName: 'Youth A',
      breedScope: 'all',
      breedIds: {},
      species: {'rabbit'},
      isEnabled: true,
    ),
    CloseoutSection(
      id: 'r-open-b',
      kind: 'open',
      letter: 'B',
      displayName: 'Open B',
      breedScope: 'all',
      breedIds: {},
      species: {'rabbit'},
      isEnabled: true,
    ),
    CloseoutSection(
      id: 'r-specialty',
      kind: 'open',
      letter: 'A',
      displayName: 'Mini Rex Specialty',
      breedScope: 'selected',
      breedIds: {'mini-rex'},
      species: {'rabbit'},
      isEnabled: true,
    ),
    CloseoutSection(
      id: 'r-open-d',
      kind: 'open',
      letter: 'D',
      displayName: 'Open D',
      breedScope: 'all',
      breedIds: {},
      species: {'rabbit'},
      isEnabled: true,
    ),
    CloseoutSection(
      id: 'c-open-a',
      kind: 'open',
      letter: 'A',
      displayName: 'Cavy Open A',
      breedScope: 'all',
      breedIds: {},
      species: {'cavy'},
      isEnabled: true,
    ),
    CloseoutSection(
      id: 'disabled',
      kind: 'open',
      letter: 'C',
      displayName: 'Disabled',
      breedScope: 'all',
      breedIds: {},
      species: {'rabbit'},
      isEnabled: false,
    ),
  ];

  ResolvedCloseoutScope resolve(CloseoutScopeSelection selection) => resolver
      .resolve(showId: 'show', sections: sections, selection: selection);

  test('entire show returns every enabled section', () {
    expect(
      resolve(
        const CloseoutScopeSelection(kind: CloseoutScopeKind.entireShow),
      ).sectionIds,
      {
        'r-open-a',
        'r-youth-a',
        'r-open-b',
        'r-specialty',
        'r-open-d',
        'c-open-a',
      },
    );
  });

  test(
    'species, kind, letter, and specialty filters resolve exact sections',
    () {
      expect(
        resolve(
          const CloseoutScopeSelection(kind: CloseoutScopeKind.rabbits),
        ).sectionIds,
        {'r-open-a', 'r-youth-a', 'r-open-b', 'r-specialty', 'r-open-d'},
      );
      expect(
        resolve(
          const CloseoutScopeSelection(kind: CloseoutScopeKind.cavies),
        ).sectionIds,
        {'c-open-a'},
      );
      expect(
        resolve(
          const CloseoutScopeSelection(
            kind: CloseoutScopeKind.rabbits,
            showLetters: {'A'},
            sectionKinds: {'open'},
            includeSpecialty: false,
          ),
        ).sectionIds,
        {'r-open-a'},
      );
      expect(
        resolve(
          const CloseoutScopeSelection(
            kind: CloseoutScopeKind.rabbits,
            includeAllBreed: false,
          ),
        ).sectionIds,
        {'r-specialty'},
      );
    },
  );

  test('custom selection is exact and order-independent', () {
    final first = resolve(
      const CloseoutScopeSelection(
        kind: CloseoutScopeKind.custom,
        sectionIds: {'c-open-a', 'r-open-a'},
      ),
    );
    final second = resolve(
      const CloseoutScopeSelection(
        kind: CloseoutScopeKind.custom,
        sectionIds: {'r-open-a', 'c-open-a'},
      ),
    );
    expect(first.sectionIds, {'r-open-a', 'c-open-a'});
    expect(first.stableScopeKey, second.stableScopeKey);
  });

  test('artifact matching uses key then exact structured section metadata', () {
    final scope = resolve(
      const CloseoutScopeSelection(
        kind: CloseoutScopeKind.custom,
        sectionIds: {'r-open-a', 'r-youth-a'},
      ),
    );
    expect(
      scope.matchesArtifactMetadata({'scope_key': scope.stableScopeKey}),
      isTrue,
    );
    expect(
      scope.matchesArtifactMetadata({
        'section_ids': ['r-youth-a', 'r-open-a'],
      }),
      isTrue,
    );
    expect(
      scope.matchesArtifactMetadata({
        'section_ids': ['r-open-a'],
      }),
      isFalse,
    );
    expect(scope.matchesArtifactMetadata({'section_id': 'r-open-a'}), isTrue);
    expect(scope.matchesArtifactMetadata({}), isFalse);
  });

  test('five-section scope uses a compact presentation label', () {
    final scope = resolve(
      const CloseoutScopeSelection(kind: CloseoutScopeKind.rabbits),
    );

    expect(scope.sectionIds, hasLength(5));
    expect(
      CloseoutScopePresentation.compactLabel(scope),
      'Rabbit • 5 sections',
    );
    expect(
      scope.displayLabel,
      allOf(contains('Open A'), contains('Open B'), contains('Open D')),
    );
  });

  test('completion is isolated by stable scope key', () {
    final rabbit = resolve(
      const CloseoutScopeSelection(kind: CloseoutScopeKind.rabbits),
    );
    final cavy = resolve(
      const CloseoutScopeSelection(kind: CloseoutScopeKind.cavies),
    );
    final completed = {rabbit.stableScopeKey: 'rabbit-run'};

    expect(
      closeoutScopeHasCompletedRun(
        selectedStableScopeKey: rabbit.stableScopeKey,
        completedRunIdsByScope: completed,
      ),
      isTrue,
    );
    expect(
      closeoutScopeHasCompletedRun(
        selectedStableScopeKey: cavy.stableScopeKey,
        completedRunIdsByScope: completed,
      ),
      isFalse,
    );
  });

  test('mixed sections retain the explicitly selected species', () {
    const mixedSections = <CloseoutSection>[
      CloseoutSection(
        id: 'mixed-open-a',
        kind: 'open',
        letter: 'A',
        displayName: 'Open A',
        breedScope: 'all',
        breedIds: {},
        species: {'rabbit', 'cavy'},
        isEnabled: true,
      ),
    ];
    final rabbit = resolver.resolve(
      showId: 'mixed-show',
      sections: mixedSections,
      selection: const CloseoutScopeSelection(kind: CloseoutScopeKind.rabbits),
    );
    final cavy = resolver.resolve(
      showId: 'mixed-show',
      sections: mixedSections,
      selection: const CloseoutScopeSelection(kind: CloseoutScopeKind.cavies),
    );

    expect(rabbit.sectionIds, {'mixed-open-a'});
    expect(cavy.sectionIds, {'mixed-open-a'});
    expect(rabbit.species, {'rabbit'});
    expect(cavy.species, {'cavy'});
    expect(rabbit.displayLabel, startsWith('Rabbit '));
    expect(cavy.displayLabel, startsWith('Cavy '));
  });

  test('section presentation hides raw scope and species values', () {
    expect(
      CloseoutSectionPresentation.displayLabel(
        kind: 'OPEN',
        letter: 'a',
        isAllBreed: true,
        displayName: 'all',
      ),
      'Open A • All Breed',
    );
    expect(
      CloseoutSectionPresentation.summaryLabel(
        species: const ['rabbit'],
        isSpecialty: false,
        entryCount: 261,
      ),
      'Rabbit • 261 entries',
    );
  });
}
