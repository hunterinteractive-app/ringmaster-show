import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/rendering/artifact_renderer.dart';
import 'package:ringmaster_show/reporting_core/rendering/closeout_worker.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_queue.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_task.dart';
import 'package:ringmaster_show/reporting_core/rendering/structured_log.dart';
import 'package:ringmaster_show/reporting_core/rendering/worker_config.dart';
import 'package:ringmaster_show/reporting_core/rendering/worker_http.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('task and scope contract', () {
    test('parses a claimed task', () {
      expect(RenderTask.fromJson(_taskJson()).artifactId, 'artifact-1');
    });

    test('rejects a mismatched artifact scope', () {
      final artifact = _artifact(scopeKey: 'other');
      expect(
        () => artifact.validateFor(_task()),
        throwsA(isA<RenderFailure>()),
      );
    });

    test('rejects a stale generation', () {
      final task = RenderTask.fromJson({
        ..._taskJson(),
        'payload': {
          'report_name': 'arba_report',
          'generation': 2,
          'section_ids': ['section-1'],
        },
      });
      expect(
        () => _artifact().validateFor(task),
        throwsA(isA<RenderFailure>()),
      );
    });

    test('rejects a configured bucket mismatch', () {
      expect(
        () => _artifact().validateFor(_task(), configuredBucket: 'wrong'),
        throwsA(isA<RenderFailure>()),
      );
    });

    test('accepts exact structured scope', () {
      expect(() => _artifact().validateFor(_task()), returnsNormally);
    });
  });

  group('asset loading', () {
    test('loads an asset from the filesystem', () async {
      final root = await Directory.systemTemp.createTemp('renderer-assets');
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/fonts').create();
      await File('${root.path}/fonts/font.ttf').writeAsBytes([1, 2, 3]);
      final bytes = await FileSystemReportAssetLoader(
        root,
      ).loadBytes('assets/fonts/font.ttf');
      expect(bytes, [1, 2, 3]);
    });

    test('missing asset reports the precise path', () async {
      final root = await Directory.systemTemp.createTemp('renderer-assets');
      addTearDown(() => root.delete(recursive: true));
      expect(
        FileSystemReportAssetLoader(root).loadBytes('assets/missing.png'),
        throwsA(
          isA<ReportAssetException>().having(
            (error) => error.assetPath,
            'assetPath',
            'assets/missing.png',
          ),
        ),
      );
    });

    test('path traversal is rejected', () async {
      final root = await Directory.systemTemp.createTemp('renderer-assets');
      addTearDown(() => root.delete(recursive: true));
      expect(
        FileSystemReportAssetLoader(root).loadBytes('../secret'),
        throwsA(isA<ReportAssetException>()),
      );
    });
  });

  group('worker lifecycle', () {
    test('successful render uploads and completes', () async {
      final queue = _FakeQueue([_task()]);
      final result = await _worker(queue: queue).workOnce();
      expect(result.completed, 1);
      expect(queue.uploaded, 1);
      expect(queue.completed, 1);
    });

    test('upload failure never completes', () async {
      final queue = _FakeQueue([_task()])..uploadError = StateError('storage');
      final result = await _worker(queue: queue).workOnce();
      expect(result.failed, 1);
      expect(queue.completed, 0);
      expect(queue.failures, 1);
    });

    test('retryable render failure is recorded retryable', () async {
      final queue = _FakeQueue([_task()]);
      await _worker(
        queue: queue,
        renderer: _FakeRenderer(
          error: const RenderFailure('data_load', 'Retry later.', 'timeout'),
        ),
      ).workOnce();
      expect(queue.lastFailure?.retryable, isTrue);
    });

    test('permanent failure is recorded non-retryable', () async {
      final queue = _FakeQueue([_task()]);
      await _worker(
        queue: queue,
        renderer: _FakeRenderer(
          error: const RenderFailure.permanent(
            'unsupported_renderer',
            'Unsupported.',
          ),
        ),
      ).workOnce();
      expect(queue.lastFailure?.retryable, isFalse);
    });

    test('one-shot with no work exits cleanly', () async {
      final result = await _worker(queue: _FakeQueue([])).workOnce();
      expect(result.claimed, 0);
    });

    test('stale recovery runs before claim', () async {
      final queue = _FakeQueue([])..recovered = 2;
      expect((await _worker(queue: queue).workOnce()).recovered, 2);
    });

    test('a process rejects overlapping batches', () async {
      final queue = _FakeQueue([_task()])..claimGate = true;
      final worker = _worker(queue: queue);
      final first = worker.workOnce();
      await Future<void>.delayed(Duration.zero);
      expect(worker.workOnce(), throwsStateError);
      queue.releaseClaim();
      await first;
    });

    test('service-role key is never written to structured logs', () async {
      final lines = <String>[];
      await _worker(
        queue: _FakeQueue([_task()]),
        log: StructuredLog(workerId: 'worker', sink: lines.add),
      ).workOnce();
      expect(lines.join(), isNot(contains('service-role-secret')));
    });
  });

  group('HTTP', () {
    test('health returns the build version', () async {
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(workToken: 'token'),
      );
      final response = await handler(
        Request('GET', Uri.parse('http://x/health')),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), contains('test-version'));
    });

    test('work rejects unauthenticated requests', () async {
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(workToken: 'token'),
      );
      final response = await handler(
        Request('POST', Uri.parse('http://x/work')),
      );
      expect(response.statusCode, 403);
    });

    test('authorized work processes a bounded batch', () async {
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([_task()])),
        _config(workToken: 'token'),
      );
      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://x/work'),
          headers: {'authorization': 'Bearer token'},
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), contains('"completed":1'));
    });
  });

  group('architecture', () {
    test('migration contains lease heartbeat and stale recovery', () {
      final sql = File(
        '../../supabase/migrations/20260714055153_closeout_read_only_dashboard_and_render_queue.sql',
      ).readAsStringSync();
      expect(sql, contains('heartbeat_report_render_task'));
      expect(sql, contains('recover_stale_report_render_tasks'));
    });

    test('migration preserves immutable generation paths', () {
      final sql = File(
        '../../supabase/migrations/20260714055153_closeout_read_only_dashboard_and_render_queue.sql',
      ).readAsStringSync();
      expect(sql, contains('/generation-%s/report.pdf'));
      expect(sql, contains('previous_versions'));
    });

    test('worker imports the shared report registry', () {
      final source = File(
        '../../lib/reporting_core/rendering/artifact_renderer.dart',
      ).readAsStringSync();
      expect(source, contains('closeout/registry/report_registry.dart'));
      expect(source, isNot(contains('rootBundle')));
    });

    test('all manifest report types are explicit registry keys', () {
      const types = {
        'arba_report',
        'legs',
        'checkin_sheet',
        'exhibitor_report',
        'sweepstakes_report',
        'breed_results_detail_report',
        'details_by_breed',
        'exh_by_breed',
        'unpaid_balances_report',
        'paid_exhibitor_report',
        'entered_exhibitors_contact_report',
        'ribbon_payout_report',
        'payback_report',
        'judge_report',
        'breed_judged_totals_report',
        'best_display_report',
      };
      final registry = File(
        '../../lib/screens/admin/closeout/registry/report_registry.dart',
      ).readAsStringSync();
      for (final type in types) {
        expect(registry, contains("'$type': ReportDefinition"), reason: type);
      }
    });

    test('balance loaders pass the exact artifact section scope', () {
      for (final path in const [
        '../../lib/screens/admin/closeout/data/loaders/paid_exhibitor_report_loader.dart',
        '../../lib/screens/admin/closeout/data/loaders/unpaid_balances_report_loader.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('sectionIds: request.sectionIds'),
          reason: path,
        );
        expect(source, isNot(contains("'report_show_exhibitor_balances'")));
      }
    });

    test('worker retains a permanent ambiguous-allocation safety failure', () {
      final source = File(
        '../../lib/reporting_core/rendering/artifact_renderer.dart',
      ).readAsStringSync();
      expect(source, contains('report_show_exhibitor_balances_scoped'));
      expect(source, contains('unsupported_scoped_balance_report'));
      expect(source, contains("row['payment_allocation_status'] == 'ambiguous'"));
    });

    test('scoped balance RPC is hardened and never granted to anon', () {
      final sql = File(
        '../../supabase/migrations/20260714112117_closeout_scoped_financial_balances.sql',
      ).readAsStringSync();
      expect(sql, contains('security definer'));
      expect(sql, contains("set search_path = ''"));
      expect(sql, contains('from public, anon'));
      expect(sql, contains('to authenticated, service_role'));
      expect(sql, contains("then 'ambiguous'"));
    });
  });
}

CloseoutWorker _worker({
  required _FakeQueue queue,
  _FakeRenderer? renderer,
  StructuredLog? log,
}) => CloseoutWorker(
  config: _config(),
  queue: queue,
  renderer: renderer ?? _FakeRenderer(),
  log: log ?? StructuredLog(workerId: 'worker', sink: (_) {}),
);

WorkerConfig _config({String? workToken}) => WorkerConfig(
  supabaseUrl: 'http://localhost',
  serviceRoleKey: 'service-role-secret',
  workerId: 'worker',
  batchSize: 5,
  pollInterval: const Duration(milliseconds: 1),
  maxConcurrentRenders: 2,
  assetRoot: Directory('../../assets'),
  continuous: false,
  dryRun: false,
  port: 8080,
  buildVersion: 'test-version',
  workToken: workToken,
);

Map<String, dynamic> _taskJson() => {
  'id': 'task-1',
  'report_artifact_id': 'artifact-1',
  'show_id': 'show-1',
  'finalize_run_id': 'run-1',
  'scope_key': 'show-1:section-1',
  'attempt_count': 1,
  'max_attempts': 3,
  'payload': {
    'report_name': 'arba_report',
    'generation': 1,
    'section_ids': ['section-1'],
  },
};

RenderTask _task() => RenderTask.fromJson(_taskJson());

RenderArtifact _artifact({
  String scopeKey = 'show-1:section-1',
}) => RenderArtifact(
  id: 'artifact-1',
  showId: 'show-1',
  finalizeRunId: 'run-1',
  scopeKey: scopeKey,
  reportName: 'arba_report',
  sectionIds: const ['section-1'],
  metadata: {
    'scope_key': scopeKey,
    'section_ids': ['section-1'],
  },
  storageBucket: 'show-files',
  storagePath:
      'shows/show-1/reports/versions/run-1/artifacts/artifact-1/generation-1/report.pdf',
  generation: 1,
);

final class _FakeRenderer implements ArtifactRenderer {
  _FakeRenderer({this.error});

  final Object? error;

  @override
  Set<String> get supportedReportTypes => const {'arba_report'};

  @override
  Future<RenderedArtifact> render(RenderArtifact artifact) async {
    if (error case final error?) throw error;
    return RenderedArtifact(
      bytes: Uint8List.fromList([37, 80, 68, 70]),
      fileName: 'report.pdf',
      mimeType: 'application/pdf',
      checksum: 'checksum',
      dataLoadDuration: const Duration(milliseconds: 2),
      pdfBuildDuration: const Duration(milliseconds: 3),
    );
  }
}

final class _FakeQueue implements RenderQueue {
  _FakeQueue(this.tasks);

  final List<RenderTask> tasks;
  int uploaded = 0;
  int completed = 0;
  int failures = 0;
  int recovered = 0;
  Object? uploadError;
  RenderFailure? lastFailure;
  bool claimGate = false;
  final _claimCompleter = Completer<void>();

  void releaseClaim() => _claimCompleter.complete();

  @override
  Future<List<RenderTask>> claim(String workerId, int batchSize) async {
    if (claimGate) await _claimCompleter.future;
    return tasks.take(batchSize).toList();
  }

  @override
  Future<int> countReady() async => 0;

  @override
  Future<void> complete(
    RenderTask task,
    RenderArtifact artifact,
    String workerId, {
    required String fileName,
    required int byteSize,
    required String checksum,
  }) async {
    completed++;
  }

  @override
  Future<void> fail(
    RenderTask task,
    String workerId,
    RenderFailure failure,
  ) async {
    failures++;
    lastFailure = failure;
  }

  @override
  Future<void> heartbeat(String taskId, String workerId) async {}

  @override
  Future<RenderArtifact> loadArtifact(String artifactId) async => _artifact();

  @override
  Future<int> recoverStale(int limit) async => recovered;

  @override
  Future<void> upload(
    RenderArtifact artifact,
    Uint8List bytes, {
    required String checksum,
  }) async {
    if (uploadError case final error?) throw error;
    uploaded++;
  }
}
