import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/report_artifact_summary.dart';

ReportArtifactSummary artifact({
  String id = 'artifact',
  String? finalizeRunId = 'run-current',
  String reportName = 'exhibitor_report',
  String status = 'generated',
  bool isCurrent = true,
  int generation = 1,
  String? generatedAt = '2026-07-15T12:00:00Z',
  String? createdAt = '2026-07-15T11:00:00Z',
  Map<String, dynamic> metadata = const {},
}) => ReportArtifactSummary(
  id: id,
  showId: 'show',
  finalizeRunId: finalizeRunId,
  reportName: reportName,
  artifactStatus: status,
  isCurrent: isCurrent,
  generation: generation,
  generatedAt: generatedAt,
  createdAt: createdAt,
  metadata: metadata,
);

void main() {
  group('Closeout artifact parsing', () {
    test(
      'retains every dashboard identity, scope, status, and storage field',
      () {
        final parsed = ReportArtifactSummary.fromJson({
          'id': 'a1',
          'show_id': 'show',
          'finalize_run_id': 'run',
          'report_name': 'legs',
          'artifact_status': 'generated',
          'generated_at': '2026-07-15T12:00:00Z',
          'is_current': true,
          'scope_key': 'artifact-scope',
          'section_ids': ['section-a'],
          'metadata': {'exhibitor_name': 'Adalyn Cathcart'},
          'storage_bucket': 'reports',
          'storage_path': 'show/a1.pdf',
          'file_name': 'adalyn-legs.pdf',
          'error_count': 0,
          'generation': 3,
          'created_at': '2026-07-15T11:00:00Z',
        });

        expect(parsed.showId, 'show');
        expect(parsed.finalizeRunId, 'run');
        expect(parsed.scopeKey, 'artifact-scope');
        expect(parsed.sectionIds, ['section-a']);
        expect(parsed.metadata['section_ids'], ['section-a']);
        expect(parsed.storageBucket, 'reports');
        expect(parsed.storagePath, 'show/a1.pdf');
        expect(parsed.fileName, 'adalyn-legs.pdf');
        expect(parsed.generation, 3);
        expect(parsed.errorCount, 0);
      },
    );
  });

  group('Closeout status labels', () {
    test(
      'generated is Generated',
      () => expect(
        closeoutReportStatusLabel(closeoutReportUiStatus('generated')),
        'Generated',
      ),
    );
    test(
      'queued is Generating',
      () => expect(
        closeoutReportStatusLabel(closeoutReportUiStatus('queued')),
        'Generating',
      ),
    );
    test(
      'running is Generating',
      () => expect(
        closeoutReportStatusLabel(closeoutReportUiStatus('running')),
        'Generating',
      ),
    );
    test(
      'failed is Failed',
      () => expect(
        closeoutReportStatusLabel(closeoutReportUiStatus('failed')),
        'Failed',
      ),
    );
    test(
      'missing expected artifact needs attention',
      () => expect(
        closeoutReportStatusLabel(closeoutReportUiStatus(null)),
        'Needs attention',
      ),
    );
    test(
      'inapplicable target is Not applicable',
      () => expect(
        closeoutReportStatusLabel(
          closeoutReportUiStatus(null, expected: false),
        ),
        'Not applicable',
      ),
    );
  });

  group('deterministic artifact priority', () {
    test('prefers the selected finalize run', () {
      final values =
          [artifact(id: 'old', finalizeRunId: 'old'), artifact(id: 'new')]
            ..sort(
              (a, b) => compareCloseoutReportArtifacts(
                a,
                b,
                selectedFinalizeRunId: 'run-current',
              ),
            );
      expect(values.first.id, 'new');
    });

    test('prefers current artifacts', () {
      final values = [
        artifact(id: 'old', isCurrent: false),
        artifact(id: 'new'),
      ]..sort(compareCloseoutReportArtifacts);
      expect(values.first.id, 'new');
    });

    test('prefers generated then generating then failed', () {
      final values = [
        artifact(id: 'failed', status: 'failed'),
        artifact(id: 'queued', status: 'queued'),
        artifact(id: 'generated'),
      ]..sort(compareCloseoutReportArtifacts);
      expect(values.map((value) => value.id), [
        'generated',
        'queued',
        'failed',
      ]);
    });

    test('prefers generation then generated and created timestamps', () {
      final values = [
        artifact(id: 'generation-1'),
        artifact(id: 'generation-2', generation: 2),
      ]..sort(compareCloseoutReportArtifacts);
      expect(values.first.id, 'generation-2');
    });

    test('prefers the newest generated timestamp at equal generation', () {
      final values = [
        artifact(id: 'older', generatedAt: '2026-07-15T12:00:00Z'),
        artifact(id: 'newer', generatedAt: '2026-07-15T13:00:00Z'),
      ]..sort(compareCloseoutReportArtifacts);
      expect(values.first.id, 'newer');
    });

    test('prefers the newest created timestamp when generated times tie', () {
      final values = [
        artifact(id: 'older', createdAt: '2026-07-15T11:00:00Z'),
        artifact(id: 'newer', createdAt: '2026-07-15T11:30:00Z'),
      ]..sort(compareCloseoutReportArtifacts);
      expect(values.first.id, 'newer');
    });
  });

  group('artifact/report/target matching', () {
    test('selects Adalyn Cathcart exhibitor report and legs independently', () {
      final adalyn = artifact(
        metadata: const {
          'exhibitor_id': 'adalyn',
          'exhibitor_name': 'Adalyn Cathcart',
        },
      );
      expect(
        closeoutArtifactMatchesReportTarget(
          adalyn,
          reportName: 'exhibitor_report',
          exhibitorId: 'adalyn',
        ),
        isTrue,
      );
      expect(
        closeoutArtifactMatchesReportTarget(
          adalyn,
          reportName: 'legs',
          exhibitorId: 'adalyn',
        ),
        isFalse,
      );
    });

    test('selects Dutch Youth A sweepstakes without requiring species', () {
      final dutch = artifact(
        reportName: 'sweepstakes_report',
        metadata: const {
          'breed_name': 'Dutch',
          'scope': 'YOUTH',
          'show_letter': 'A',
        },
      );
      expect(
        closeoutArtifactMatchesReportTarget(
          dutch,
          reportName: 'sweepstakes_report',
          breedName: ' Dutch ',
          scope: 'youth',
          showLetter: 'a',
        ),
        isTrue,
      );
    });

    test('rejects wrong scope, letter, and superseded artifacts', () {
      final dutch = artifact(
        reportName: 'breed_results_detail_report',
        metadata: const {
          'breed_name': 'Dutch',
          'scope': 'YOUTH',
          'show_letter': 'A',
        },
      );
      expect(
        closeoutArtifactMatchesReportTarget(
          dutch,
          reportName: 'breed_results_detail_report',
          breedName: 'Dutch',
          scope: 'OPEN',
          showLetter: 'A',
        ),
        isFalse,
      );
      expect(
        closeoutArtifactMatchesReportTarget(
          artifact(
            reportName: 'breed_results_detail_report',
            isCurrent: false,
            metadata: dutch.metadata,
          ),
          reportName: 'breed_results_detail_report',
          breedName: 'Dutch',
          scope: 'YOUTH',
          showLetter: 'A',
        ),
        isFalse,
      );
    });
  });
}
