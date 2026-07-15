import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ringmaster_show/reporting_core/assets/report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/rendering/artifact_renderer.dart';
import 'package:ringmaster_show/reporting_core/rendering/artifact_scope.dart';
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

    test('artifact keys differ across Open and Youth A/B/C sections', () {
      final keys = <String>{};
      for (final scope in ['OPEN', 'YOUTH']) {
        for (final letter in ['A', 'B', 'C']) {
          final section = '${scope.toLowerCase()}-$letter';
          final metadata = _scopeMetadata(
            sectionId: section,
            scope: scope,
            showLetter: letter,
          );
          keys.add(
            ArtifactScope.canonicalKey(
              showId: 'show-1',
              reportName: 'arba_report',
              sectionIds: [section],
              metadata: metadata,
            ),
          );
        }
      }
      expect(keys, hasLength(6));
    });

    test('species and report dimensions participate in artifact scope', () {
      final rabbit = _scopeMetadata(species: 'rabbit', breedName: 'Dutch');
      final cavy = _scopeMetadata(species: 'cavy', breedName: 'Dutch');
      expect(
        ArtifactScope.canonicalKey(
          showId: 'show-1',
          reportName: 'sweepstakes_report',
          sectionIds: const ['section-1'],
          metadata: rabbit,
        ),
        isNot(
          ArtifactScope.canonicalKey(
            showId: 'show-1',
            reportName: 'sweepstakes_report',
            sectionIds: const ['section-1'],
            metadata: cavy,
          ),
        ),
      );
    });

    test('run-wide reports accept the canonical selected section set', () {
      final metadata = <String, dynamic>{
        'run_scope_key': 'show-1:section-1,section-2',
        'section_ids': ['section-1', 'section-2'],
        'delivery_type': 'internal',
      };
      final key = ArtifactScope.canonicalKey(
        showId: 'show-1',
        reportName: 'judge_report',
        sectionIds: const ['section-2', 'section-1'],
        metadata: metadata,
      );
      metadata['scope_key'] = key;
      expect(
        ArtifactScope.validationError(
          showId: 'show-1',
          reportName: 'judge_report',
          sectionIds: const ['section-1', 'section-2'],
          scopeKey: key,
          metadata: metadata,
        ),
        isNull,
      );
    });

    test('worker rejects the former run-wide key on a section artifact', () {
      final artifact = _artifact(scopeKey: 'show-1:section-1,section-2');
      final task = RenderTask.fromJson({
        ..._taskJson(),
        'scope_key': 'show-1:section-1,section-2',
      });
      expect(
        () => artifact.validateFor(task),
        throwsA(
          isA<RenderFailure>().having(
            (failure) => failure.category,
            'category',
            'invalid_scope',
          ),
        ),
      );
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

    test('valid X-Work-Token processes a bounded batch', () async {
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([_task()])),
        _config(workToken: 'token'),
      );
      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://x/work'),
          headers: {'x-work-token': 'token'},
        ),
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), contains('"completed":1'));
    });

    test('invalid X-Work-Token returns 403 without bearer fallback', () async {
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([_task()])),
        _config(workToken: 'token'),
      );
      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://x/work'),
          headers: {
            'x-work-token': 'wrong-token',
            'authorization': 'Bearer token',
          },
        ),
      );
      expect(response.statusCode, 403);
    });

    test('Authorization Bearer still processes a bounded batch', () async {
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

    test('dispatch rejects unauthenticated requests', () async {
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(workToken: 'token', workerBaseUrl: Uri.parse('https://worker')),
        dispatcher: _FakeDispatcher(),
      );

      final response = await handler(
        Request('POST', Uri.parse('http://x/dispatch')),
      );

      expect(response.statusCode, 403);
    });

    test('dispatch requires a configured worker base URL', () async {
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(workToken: 'token'),
        dispatcher: _FakeDispatcher(),
      );

      final response = await handler(_dispatchRequest());

      expect(response.statusCode, 503);
      expect(await response.readAsString(), contains('WORKER_BASE_URL'));
    });

    test(
      'dispatch invalid X-Work-Token does not fall back to bearer',
      () async {
        final handler = buildWorkerHandler(
          _worker(queue: _FakeQueue([])),
          _config(
            workToken: 'token',
            workerBaseUrl: Uri.parse('https://worker'),
          ),
          dispatcher: _FakeDispatcher(),
        );

        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://x/dispatch'),
            headers: {'x-work-token': 'wrong', 'authorization': 'Bearer token'},
          ),
        );

        expect(response.statusCode, 403);
      },
    );

    test('dispatch accepts Authorization Bearer fallback', () async {
      final dispatcher = _FakeDispatcher([
        [_success(claimed: 0, remaining: 0)],
      ]);
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(workToken: 'token', workerBaseUrl: Uri.parse('https://worker')),
        dispatcher: dispatcher,
      );

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://x/dispatch'),
          headers: {'authorization': 'Bearer token'},
        ),
      );

      expect(response.statusCode, 200);
      expect(dispatcher.calls, 1);
    });

    test('dispatch concurrency is capped at 25 requests per round', () async {
      expect(
        () => _config(dispatchConcurrency: 26),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _config(dispatchMaxRounds: 6),
        throwsA(isA<FormatException>()),
      );
      final dispatcher = _FakeDispatcher([
        List.generate(25, (_) => _success(claimed: 0, remaining: 1)),
      ]);
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(
          workToken: 'token',
          workerBaseUrl: Uri.parse('https://worker'),
          dispatchConcurrency: 25,
          dispatchMaxRounds: 5,
        ),
        dispatcher: dispatcher,
      );

      final response = await handler(_dispatchRequest());
      final body = jsonDecode(await response.readAsString());

      expect(response.statusCode, 200);
      expect(dispatcher.requestCounts, [25]);
      expect(body['requests'], 25);
      expect(body['rounds'], 1);
    });

    test('dispatch stops early when every response claims zero', () async {
      final dispatcher = _FakeDispatcher([
        [
          _success(claimed: 0, remaining: 7),
          _success(claimed: 0, remaining: 7),
        ],
        [
          _success(claimed: 1, remaining: 6),
          _success(claimed: 1, remaining: 6),
        ],
      ]);
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(
          workToken: 'token',
          workerBaseUrl: Uri.parse('https://worker'),
          dispatchConcurrency: 2,
          dispatchMaxRounds: 5,
        ),
        dispatcher: dispatcher,
      );

      final response = await handler(_dispatchRequest());
      final body = jsonDecode(await response.readAsString());

      expect(dispatcher.calls, 1);
      expect(body['rounds'], 1);
      expect(body['requests'], 2);
    });

    test('dispatch aggregates successful work response summaries', () async {
      final dispatcher = _FakeDispatcher([
        [
          _success(
            claimed: 3,
            completed: 2,
            failed: 1,
            recovered: 4,
            remaining: 8,
          ),
          _success(
            claimed: 2,
            completed: 2,
            failed: 0,
            recovered: 1,
            remaining: 0,
          ),
        ],
        [_success(claimed: 99, remaining: 99)],
      ]);
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(
          workToken: 'token',
          workerBaseUrl: Uri.parse('https://worker'),
          dispatchConcurrency: 2,
          dispatchMaxRounds: 3,
        ),
        dispatcher: dispatcher,
      );

      final response = await handler(_dispatchRequest());
      final body = jsonDecode(await response.readAsString());

      expect(body, {
        'rounds': 1,
        'requests': 2,
        'request_failures': 0,
        'claimed': 5,
        'completed': 4,
        'failed': 1,
        'recovered': 5,
        'remaining': 0,
      });
      expect(dispatcher.calls, 1);
    });

    test('dispatch does not sum global remaining snapshots', () async {
      final dispatcher = _FakeDispatcher([
        [
          _success(claimed: 1, remaining: 8),
          _success(claimed: 1, remaining: 5),
        ],
      ]);
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(
          workToken: 'token',
          workerBaseUrl: Uri.parse('https://worker'),
          dispatchConcurrency: 2,
        ),
        dispatcher: dispatcher,
      );

      final response = await handler(_dispatchRequest());
      final body = jsonDecode(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['remaining'], 5);
      expect(body['remaining'], isNot(13));
    });

    test(
      'dispatch reports the last round minimum remaining snapshot',
      () async {
        final dispatcher = _FakeDispatcher([
          [
            _success(claimed: 1, remaining: 9),
            _success(claimed: 1, remaining: 7),
          ],
          [
            _success(claimed: 1, remaining: 4),
            _success(claimed: 1, remaining: 2),
          ],
        ]);
        final handler = buildWorkerHandler(
          _worker(queue: _FakeQueue([])),
          _config(
            workToken: 'token',
            workerBaseUrl: Uri.parse('https://worker'),
            dispatchConcurrency: 2,
            dispatchMaxRounds: 2,
          ),
          dispatcher: dispatcher,
        );

        final response = await handler(_dispatchRequest());
        final body = jsonDecode(await response.readAsString());

        expect(response.statusCode, 200);
        expect(body['rounds'], 2);
        expect(body['requests'], 4);
        expect(body['remaining'], 2);
      },
    );

    test('dispatch returns 502 when every internal request fails', () async {
      final dispatcher = _FakeDispatcher([
        [
          WorkDispatchOutcome.failure(StateError('first failure')),
          WorkDispatchOutcome.failure(StateError('second failure')),
        ],
        [
          WorkDispatchOutcome.failure(StateError('third failure')),
          WorkDispatchOutcome.failure(StateError('fourth failure')),
        ],
      ]);
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(
          workToken: 'token',
          workerBaseUrl: Uri.parse('https://worker'),
          dispatchConcurrency: 2,
          dispatchMaxRounds: 2,
        ),
        dispatcher: dispatcher,
      );

      final response = await handler(_dispatchRequest());
      final body = jsonDecode(await response.readAsString());

      expect(response.statusCode, 502);
      expect(body, {
        'rounds': 2,
        'requests': 4,
        'request_failures': 4,
        'error': 'All dispatched work requests failed.',
      });
      expect(body, isNot(contains('remaining')));
      expect(body, isNot(contains('failed')));
    });

    test('dispatch tolerates partial request failures', () async {
      final dispatcher = _FakeDispatcher([
        [
          WorkDispatchOutcome.failure(StateError('unavailable')),
          _success(claimed: 4, completed: 1, failed: 3, remaining: 3),
        ],
      ]);
      final handler = buildWorkerHandler(
        _worker(queue: _FakeQueue([])),
        _config(
          workToken: 'token',
          workerBaseUrl: Uri.parse('https://worker'),
          dispatchConcurrency: 2,
        ),
        dispatcher: dispatcher,
      );

      final response = await handler(_dispatchRequest());
      final body = jsonDecode(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['requests'], 2);
      expect(body['request_failures'], 1);
      expect(body['claimed'], 4);
      expect(body['completed'], 1);
      expect(body['failed'], 3);
      expect(body['remaining'], 3);
    });

    test(
      'dispatch self-invocation targets only work with both tokens',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final paths = <String>[];
        String? applicationToken;
        String? iamAuthorization;
        final serverDone = Completer<void>();
        server.listen((request) async {
          paths.add(request.uri.path);
          applicationToken = request.headers.value('x-work-token');
          iamAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          await request.drain<void>();
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(_result(claimed: 0, remaining: 0).toJson()));
          await request.response.close();
          serverDone.complete();
        });
        final baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
        final handler = buildWorkerHandler(
          _worker(queue: _FakeQueue([])),
          _config(workToken: 'app-token', workerBaseUrl: baseUrl),
          dispatcher: CloudRunWorkRoundDispatcher(
            identityTokenProvider: (audience) async {
              expect(audience, baseUrl);
              return 'google-identity-token';
            },
          ),
        );

        final response = await handler(
          Request(
            'POST',
            Uri.parse('http://x/dispatch'),
            headers: {'x-work-token': 'app-token'},
          ),
        );
        await serverDone.future;

        expect(response.statusCode, 200);
        expect(paths, ['/work']);
        expect(applicationToken, 'app-token');
        expect(iamAuthorization, 'Bearer google-identity-token');
      },
    );
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
      expect(
        source,
        contains("row['payment_allocation_status'] == 'ambiguous'"),
      );
    });

    test('scoped balance RPC is hardened and never granted to anon', () {
      final sql = File(
        '../../supabase/migrations/20260715104020_closeout_final_report_failures.sql',
      ).readAsStringSync();
      expect(sql, contains('security definer'));
      expect(sql, contains("set search_path = ''"));
      expect(sql, contains('from public, anon'));
      expect(sql, contains('to authenticated, service_role'));
      expect(sql, contains("then 'ambiguous'"));
      final balanceStart = sql.indexOf(
        'create or replace function public.report_show_exhibitor_balances_scoped',
      );
      final balanceEnd = sql.indexOf(
        'comment on function public.report_show_exhibitor_balances_scoped',
        balanceStart,
      );
      final balanceRpc = sql.substring(balanceStart, balanceEnd);
      expect(balanceRpc, contains('from public.show_exhibitor_balances b'));
      expect(balanceRpc, isNot(contains('report_show_exhibitor_balances(')));
      expect(balanceRpc.toLowerCase(), isNot(contains('drop table')));
      expect(balanceRpc.toLowerCase(), isNot(contains('create temp')));
      expect(balanceRpc.toLowerCase(), isNot(contains('update ')));
      expect(balanceRpc.toLowerCase(), isNot(contains('insert into')));
    });

    test('payback RPC pushes each section into best-display evaluation', () {
      final sql = File(
        '../../supabase/migrations/20260715104020_closeout_final_report_failures.sql',
      ).readAsStringSync();
      final paybackEnd = sql.indexOf('-- Balance validation');
      final paybackRpc = sql.substring(0, paybackEnd);
      expect(paybackRpc, contains('WITH requested_sections AS'));
      expect(paybackRpc, contains('s.id = p_section_id'));
      expect(paybackRpc, contains('p_scope := requested.scope'));
      expect(paybackRpc, contains('p_show_letter := requested.show_letter'));
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

WorkerConfig _config({
  String? workToken,
  Uri? workerBaseUrl,
  int dispatchConcurrency = 1,
  int dispatchMaxRounds = 1,
}) => WorkerConfig(
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
  workerBaseUrl: workerBaseUrl,
  dispatchConcurrency: dispatchConcurrency,
  dispatchMaxRounds: dispatchMaxRounds,
);

Request _dispatchRequest() => Request(
  'POST',
  Uri.parse('http://x/dispatch'),
  headers: {'x-work-token': 'token'},
);

WorkResult _result({
  int claimed = 0,
  int completed = 0,
  int failed = 0,
  int recovered = 0,
  int remaining = 0,
}) => WorkResult(
  claimed: claimed,
  completed: completed,
  failed: failed,
  recovered: recovered,
  remaining: remaining,
);

WorkDispatchOutcome _success({
  int claimed = 0,
  int completed = 0,
  int failed = 0,
  int recovered = 0,
  int remaining = 0,
}) => WorkDispatchOutcome.success(
  _result(
    claimed: claimed,
    completed: completed,
    failed: failed,
    recovered: recovered,
    remaining: remaining,
  ),
);

final class _FakeDispatcher implements WorkRoundDispatcher {
  _FakeDispatcher([this.rounds = const []]);

  final List<List<WorkDispatchOutcome>> rounds;
  int calls = 0;
  final List<int> requestCounts = [];

  @override
  Future<List<WorkDispatchOutcome>> dispatchRound({
    required Uri workerBaseUrl,
    required String workToken,
    required int requestCount,
  }) async {
    requestCounts.add(requestCount);
    final index = calls++;
    return index < rounds.length
        ? rounds[index]
        : List.generate(
            requestCount,
            (_) => _success(claimed: 0, remaining: 0),
          );
  }
}

Map<String, dynamic> _taskJson() => {
  'id': 'task-1',
  'report_artifact_id': 'artifact-1',
  'show_id': 'show-1',
  'finalize_run_id': 'run-1',
  'scope_key': _scopeKey(),
  'attempt_count': 1,
  'max_attempts': 3,
  'payload': {
    'report_name': 'arba_report',
    'generation': 1,
    'section_ids': ['section-1'],
  },
};

RenderTask _task() => RenderTask.fromJson(_taskJson());

RenderArtifact _artifact({String? scopeKey}) {
  final metadata = _scopeMetadata();
  final resolvedScopeKey = scopeKey ?? _scopeKey(metadata);
  metadata['scope_key'] = resolvedScopeKey;
  return RenderArtifact(
    id: 'artifact-1',
    showId: 'show-1',
    finalizeRunId: 'run-1',
    scopeKey: resolvedScopeKey,
    reportName: 'arba_report',
    sectionIds: const ['section-1'],
    metadata: metadata,
    storageBucket: 'show-files',
    storagePath:
        'shows/show-1/reports/versions/run-1/artifacts/artifact-1/generation-1/report.pdf',
    generation: 1,
  );
}

Map<String, dynamic> _scopeMetadata({
  String sectionId = 'section-1',
  String scope = 'OPEN',
  String showLetter = 'A',
  String? species,
  String? breedName,
}) => <String, dynamic>{
  'run_scope_key': 'show-1:section-1,section-2',
  'section_id': sectionId,
  'section_ids': [sectionId],
  'scope': scope,
  'show_letter': showLetter,
  if (species != null) 'species': species,
  if (breedName != null) 'breed_name': breedName,
};

String _scopeKey([Map<String, dynamic>? source]) {
  final metadata = source ?? _scopeMetadata();
  return ArtifactScope.canonicalKey(
    showId: 'show-1',
    reportName: 'arba_report',
    sectionIds: const ['section-1'],
    metadata: metadata,
  );
}

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
