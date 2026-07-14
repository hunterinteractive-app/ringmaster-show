import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/closeout_scope.dart';

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
      {'r-open-a', 'r-youth-a', 'r-open-b', 'r-specialty', 'c-open-a'},
    );
  });

  test(
    'species, kind, letter, and specialty filters resolve exact sections',
    () {
      expect(
        resolve(
          const CloseoutScopeSelection(kind: CloseoutScopeKind.rabbits),
        ).sectionIds,
        {'r-open-a', 'r-youth-a', 'r-open-b', 'r-specialty'},
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
}
