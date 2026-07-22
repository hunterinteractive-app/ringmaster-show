import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/arba_report_presentation.dart';

void main() {
  const scopeKey = 'show:r-open-a,r-open-b,r-youth-a,r-wool-d,c-open-a';
  const sectionIds = {
    'r-open-a',
    'r-open-b',
    'r-youth-a',
    'r-wool-d',
    'c-open-a',
  };
  const sections = [
    ArbaReportSectionDescriptor(
      id: 'r-open-a',
      species: {'rabbit'},
      kind: 'open',
      letter: 'A',
      displayName: 'All Breed',
      isAllBreed: true,
      sortOrder: 10,
    ),
    ArbaReportSectionDescriptor(
      id: 'r-open-b',
      species: {'rabbit'},
      kind: 'open',
      letter: 'B',
      displayName: 'All Breed',
      isAllBreed: true,
      sortOrder: 20,
    ),
    ArbaReportSectionDescriptor(
      id: 'r-youth-a',
      species: {'rabbit'},
      kind: 'youth',
      letter: 'A',
      displayName: 'All Breed',
      isAllBreed: true,
      sortOrder: 30,
    ),
    ArbaReportSectionDescriptor(
      id: 'r-wool-d',
      species: {'rabbit'},
      kind: 'open',
      letter: 'D',
      displayName: 'Wool Specialty',
      isAllBreed: false,
      sortOrder: 40,
    ),
    ArbaReportSectionDescriptor(
      id: 'c-open-a',
      species: {'cavy'},
      kind: 'open',
      letter: 'A',
      displayName: 'All Breed',
      isAllBreed: true,
      sortOrder: 50,
    ),
  ];

  ArbaArtifactDescriptor artifact(
    String id,
    String sectionId, {
    String runId = 'run-current',
    String key = scopeKey,
    String status = 'generated',
    bool current = true,
    String? path,
  }) {
    final section = sections.firstWhere((item) => item.id == sectionId);
    return ArbaArtifactDescriptor(
      id: id,
      finalizeRunId: runId,
      reportName: 'arba_report',
      artifactStatus: status,
      storageBucket: 'reports',
      storagePath: path ?? 'show/$runId/$id.pdf',
      isCurrent: current,
      metadata: {
        'scope_key': key,
        'run_scope_key': key,
        'section_ids': sectionIds.toList(),
        'section_id': sectionId,
        'scope': section.kind,
        'show_letter': section.letter,
        'section_label': section.displayName,
      },
    );
  }

  final generated = [
    artifact('a', 'r-open-a'),
    artifact('b', 'r-open-b'),
    artifact('y', 'r-youth-a'),
    artifact('w', 'r-wool-d'),
    artifact('c', 'c-open-a'),
  ];

  test('five generated artifacts produce five human-readable options', () {
    final options = buildArbaReportOptions(
      artifacts: generated,
      sections: sections,
    );

    expect(options, hasLength(5));
    expect(
      options.map((option) => option.label),
      containsAll(['All Breed', 'Wool Specialty']),
    );
  });

  test('specialty section name is retained without generic repetition', () {
    final option = buildArbaReportOptions(
      artifacts: [artifact('w', 'r-wool-d')],
      sections: sections,
    ).single;

    expect(option.label, 'Wool Specialty');
    expect(option.label, isNot(contains('All Breed')));
  });

  test('duplicate display names remain exactly as configured', () {
    const duplicateSections = [
      ArbaReportSectionDescriptor(
        id: 'one',
        species: {'rabbit'},
        kind: 'open',
        letter: 'A',
        displayName: 'All Breed',
        isAllBreed: true,
        sortOrder: 1,
      ),
      ArbaReportSectionDescriptor(
        id: 'two',
        species: {'rabbit'},
        kind: 'open',
        letter: 'A',
        displayName: 'All Breed',
        isAllBreed: true,
        sortOrder: 2,
      ),
    ];
    ArbaArtifactDescriptor duplicate(String id) => ArbaArtifactDescriptor(
      id: id,
      finalizeRunId: 'run',
      reportName: 'arba_report',
      artifactStatus: 'generated',
      storageBucket: 'reports',
      storagePath: '$id.pdf',
      isCurrent: true,
      metadata: {'section_id': id},
    );

    final labels = buildArbaReportOptions(
      artifacts: [duplicate('one'), duplicate('two')],
      sections: duplicateSections,
    ).map((option) => option.label).toList();

    expect(labels, ['All Breed', 'All Breed']);
  });

  test('individual selection resolves only its actual storage path', () {
    final options = buildArbaReportOptions(
      artifacts: generated,
      sections: sections,
    );

    expect(selectedArbaOption('a', options)?.storagePath, endsWith('/a.pdf'));
    expect(selectedArbaOption('b', options)?.storagePath, endsWith('/b.pdf'));
    expect(selectedArbaOption('a', options)?.artifactId, 'a');
  });

  test('download filename uses show and selected section names', () {
    expect(
      arbaDownloadFileName(
        showName: 'Suns Out: Buns Out',
        sectionName: 'Rabbit Open A',
      ),
      'Suns Out Buns Out - ARBA Report - Rabbit Open A.pdf',
    );
  });

  test('bundled email includes every current generated scoped artifact', () {
    final bundled = selectBundledArbaArtifacts(
      artifacts: generated,
      finalizeRunId: 'run-current',
      stableScopeKey: scopeKey,
      selectedSectionIds: sectionIds,
    );

    expect(
      bundled.map((item) => item.id),
      containsAll(['a', 'b', 'y', 'w', 'c']),
    );
    expect(bundled, hasLength(5));
  });

  test(
    'bundled email accepts canonical single-section keys in a combined scope',
    () {
      final canonical = ArbaArtifactDescriptor(
        id: 'youth-a',
        finalizeRunId: 'run-current',
        reportName: 'arba_report',
        artifactStatus: 'generated',
        storageBucket: 'show-files',
        storagePath: 'show/run-current/youth-a.pdf',
        isCurrent: true,
        metadata: {
          'section_id': 'r-youth-a',
          'section_ids': ['r-youth-a'],
          'scope_key': 'artifact-specific-youth-a-key',
          'run_scope_key': scopeKey,
        },
      );

      final bundled = selectBundledArbaArtifacts(
        artifacts: [canonical],
        finalizeRunId: 'run-current',
        stableScopeKey: scopeKey,
        selectedSectionIds: sectionIds,
      );

      expect(bundled.map((item) => item.id), ['youth-a']);
    },
  );

  test('bundled email is independent of individual dropdown selection', () {
    final options = buildArbaReportOptions(
      artifacts: generated,
      sections: sections,
    );
    final firstSelection = selectedArbaOption('a', options);
    final secondSelection = selectedArbaOption('b', options);
    final bundled = selectBundledArbaArtifacts(
      artifacts: generated,
      finalizeRunId: 'run-current',
      stableScopeKey: scopeKey,
      selectedSectionIds: sectionIds,
    );

    expect(firstSelection?.artifactId, isNot(secondSelection?.artifactId));
    expect(bundled, hasLength(5));
  });

  test(
    'bundled email excludes other scopes, old runs, and failed artifacts',
    () {
      final candidates = [
        ...generated,
        artifact('other', 'r-open-a', key: 'show:other'),
        artifact('old', 'r-open-a', runId: 'run-old'),
        artifact('failed', 'r-open-a', status: 'failed'),
        artifact('missing', 'r-open-a', path: ''),
      ];
      final bundled = selectBundledArbaArtifacts(
        artifacts: candidates,
        finalizeRunId: 'run-current',
        stableScopeKey: scopeKey,
        selectedSectionIds: sectionIds,
      );

      expect(bundled.map((item) => item.id), isNot(contains('other')));
      expect(bundled.map((item) => item.id), isNot(contains('old')));
      expect(bundled.map((item) => item.id), isNot(contains('failed')));
      expect(bundled.map((item) => item.id), isNot(contains('missing')));
      expect(bundled, hasLength(5));
    },
  );

  test('bundled email deduplicates by artifact ID and storage path', () {
    final bundled = selectBundledArbaArtifacts(
      artifacts: [
        artifact('a', 'r-open-a'),
        artifact('a', 'r-open-a'),
        artifact('copy', 'r-open-a', path: 'show/run-current/a.pdf'),
      ],
      finalizeRunId: 'run-current',
      stableScopeKey: scopeKey,
      selectedSectionIds: sectionIds,
    );

    expect(bundled, hasLength(1));
  });

  test('confirmation text contains the exact generated report count', () {
    expect(
      arbaEmailConfirmationText(
        reportCount: 5,
        scopeLabel: 'Rabbit • 5 sections',
      ),
      'Email 5 ARBA reports for Rabbit • 5 sections to ARBA?',
    );
    expect(
      arbaEmailConfirmationText(reportCount: 1, scopeLabel: 'Rabbit Open A'),
      'Email 1 ARBA report for Rabbit Open A to ARBA?',
    );
  });

  test('changing scope resets an invalid selection to the first option', () {
    final options = buildArbaReportOptions(
      artifacts: [artifact('b', 'r-open-b')],
      sections: sections,
    );

    expect(normalizedArbaSelection('a', options), 'b');
  });

  test('deferred artifact remains selectable for manual generation', () {
    final options = buildArbaReportOptions(
      artifacts: [
        artifact('deferred', 'r-open-a', status: 'warning', path: ''),
      ],
      sections: sections,
    );

    expect(options, hasLength(1));
    expect(normalizedArbaSelection('old', options), 'deferred');
  });

  test('no current ARBA artifacts yields empty options and no selection', () {
    final options = buildArbaReportOptions(
      artifacts: [artifact('old', 'r-open-a', current: false)],
      sections: sections,
    );

    expect(options, isEmpty);
    expect(normalizedArbaSelection('old', options), isNull);
  });
}
