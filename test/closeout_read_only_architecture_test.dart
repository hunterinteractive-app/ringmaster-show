import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final closeoutSource = File(
    'lib/screens/admin/show_closeout.dart',
  ).readAsStringSync();
  final closeoutWidgetsSource = File(
    'lib/screens/admin/closeout/widgets/closeout_scope_widgets.dart',
  ).readAsStringSync();
  final migration = File(
    'supabase/migrations/20260714055153_closeout_read_only_dashboard_and_render_queue.sql',
  ).readAsStringSync();
  final artifactScopeMigration = File(
    'supabase/migrations/20260715012121_fix_closeout_artifact_scope.sql',
  ).readAsStringSync();
  final edgeFunction = File(
    'supabase/functions/run-closeout/index.ts',
  ).readAsStringSync();

  String methodBody(String signature, String nextSignature) {
    final start = closeoutSource.indexOf(signature);
    final end = closeoutSource.indexOf(nextSignature, start + signature.length);
    expect(start, isNonNegative, reason: 'missing $signature');
    expect(
      end,
      greaterThan(start),
      reason: 'missing end marker $nextSignature',
    );
    return closeoutSource.substring(start, end);
  }

  group('read-only Closeout query path', () {
    test('initial load uses the scoped dashboard and performs no writes', () {
      final body = methodBody(
        'Future<void> _loadData()',
        'Future<void> _saveArbaDetails()',
      );

      expect(body, contains('_loadDashboardSummary()'));
      expect(body, isNot(contains('.insert(')));
      expect(body, isNot(contains('.update(')));
      expect(body, isNot(contains('functions.invoke')));
      expect(body, isNot(contains('_ensureReportsLoaded')));
      expect(body, isNot(contains('_loadMissingJudges')));
      expect(body, isNot(contains('_loadDuplicateFinalAwards')));
    });

    test('manual refresh is one scoped read and performs no writes', () {
      final body = methodBody(
        'Future<void> _refreshDashboardOnly',
        '@override\n  void initState()',
      );

      expect(body, contains('_loadDashboardSummary()'));
      expect(body, isNot(contains('show_results_readiness')));
      expect(body, isNot(contains('_ensureReportsLoaded')));
      expect(body, isNot(contains('.insert(')));
      expect(body, isNot(contains('.update(')));
    });

    test('dashboard query is scoped, bounded, and has no storage calls', () {
      final body = methodBody(
        'Future<CloseoutDashboard> _loadDashboardSummary()',
        'Future<void> _ensureReportsLoaded',
      );

      expect(body, contains("'get_closeout_dashboard_scoped'"));
      expect(body, contains("'p_scope_key'"));
      expect(body, contains("'p_section_ids'"));
      expect(body, contains("'p_artifact_limit': 100"));
      expect(body, isNot(contains('.storage')));
      expect(body, isNot(contains('ReportLoader')));
      expect(body, isNot(contains('.insert(')));
      expect(body, isNot(contains('.update(')));
    });

    test('scope controls only refresh the read model', () {
      final cardStart = closeoutSource.indexOf('_CloseoutScopeCard(');
      final cardEnd = closeoutSource.indexOf('if (reportsBlocked)', cardStart);
      final body = closeoutSource.substring(cardStart, cardEnd);

      expect(body, contains('_refreshDashboardOnly()'));
      expect(body, isNot(contains('_syncClubDeliveryMetadata')));
      expect(body, isNot(contains('_ensureCombinedCavyClubReportArtifacts')));
      expect(body, isNot(contains('_runGenerateAllReportsLive')));
    });

    test('polling is three-second, visibility-aware, and non-overlapping', () {
      final body = methodBody(
        'void _scheduleDashboardPolling()',
        'Future<int> _finalizeShow',
      );
      expect(body, contains('counts.queued + counts.running == 0'));
      expect(body, contains('Timer.periodic(const Duration(seconds: 3)'));
      expect(body, contains('_closeoutScreenIsVisible'));
      expect(body, contains('_dashboardRefreshInFlight'));
      expect(body, contains('_loadingReports'));
      expect(body, contains('_dashboardPollTimer?.cancel()'));
    });

    test('dashboard response is rejected unless show and scope match', () {
      final body = methodBody(
        'Future<CloseoutDashboard> _loadDashboardSummary()',
        'Future<void> _ensureReportsLoaded',
      );

      expect(body, contains('dashboard.dashboard.showId != widget.showId'));
      expect(body, contains('dashboard.latestFinalize.scopeKey'));
      expect(body, contains('dashboard.latestFinalize.sectionIds'));
      expect(body, contains('_sameStringList'));
      expect(closeoutSource, contains('_dashboardScopeKey'));
    });

    test(
      'completion transition refreshes artifacts and announces completion',
      () {
        final observation = methodBody(
          'int? _observeGenerationProgress(',
          'void _announceGenerationComplete(int failedCount)',
        );
        final refresh = methodBody(
          'Future<void> _refreshDashboardOnly',
          '@override\n  void initState()',
        );

        expect(
          observation,
          contains("final generationKey = '\$scopeKey|\$runId'"),
        );
        expect(observation, contains('_observedActiveGeneration = true'));
        expect(observation, contains('return counts.failed'));
        expect(refresh, contains('_rebuildReportCaches()'));
        expect(refresh, contains('_announceGenerationComplete'));
        expect(
          closeoutSource,
          contains('Generation finished with \$failedCount failed report'),
        );
      },
    );

    test(
      'queue commands are guarded against active work in the same scope',
      () {
        final queue = methodBody(
          'Future<int> _queueScopedRenderTasks',
          'Future<void> _showReportsQueuedDialog',
        );
        final finalize = methodBody(
          'Future<int> _finalizeShow',
          'Future<int> _queueScopedRenderTasks',
        );
        final artifactQueue = methodBody(
          'Future<void> _queueExistingArtifacts',
          'Duration _reportGenerationTimeoutFor',
        );

        for (final body in [queue, finalize, artifactQueue]) {
          expect(body, contains('_generationProgress.isActive'));
        }
        expect(
          closeoutWidgetsSource,
          contains(
            'Generating Reports — \${progress.completed} of \${progress.total}',
          ),
        );
      },
    );

    test('queue completion language does not imply rendering finished', () {
      expect(closeoutSource, contains('reports queued for generation'));
      expect(closeoutSource, isNot(contains('reports processed')));
    });
  });

  group('database manifest and queue contract', () {
    test('new manifests have unique artifact and task identities', () {
      expect(migration, contains('show_report_artifacts_run_identity_uidx'));
      expect(migration, contains('(finalize_run_id, artifact_key)'));
      expect(migration, contains('show_task_queue_artifact_type_uidx'));
      expect(migration, contains('(report_artifact_id, task_type)'));
      expect(
        migration,
        contains('on conflict (report_artifact_id, task_type)'),
      );
    });

    test('finalization reuses only the exact immutable manifest', () {
      expect(migration, contains("f.summary ->> 'manifest_version' = '2'"));
      expect(migration, contains('f.scope_key = v_scope_key'));
      expect(migration, contains('f.section_ids = v_section_ids'));
      expect(migration, contains('f.results_version = v_results_version'));
      expect(migration, contains("'reused', v_reused"));
    });

    test('empty targets are filtered before artifact insertion', () {
      expect(migration, contains('e.is_shown = true'));
      expect(migration, contains('e.scratched_at is null'));
      expect(migration, contains('where exists ('));
      expect(migration, contains("array['exhibitor_report','checkin_sheet']"));
    });

    test('every renderable artifact is enqueued idempotently', () {
      expect(migration, contains('public.enqueue_report_render_tasks'));
      expect(migration, contains("'render_report'::public.show_task_type"));
      expect(migration, contains("'artifact_id', a.id"));
      expect(migration, contains("'generation', a.generation"));
    });

    test('claiming is atomic, bounded, and concurrency-safe', () {
      expect(migration, contains('for update skip locked'));
      expect(migration, contains('limit greatest(1, least'));
      expect(migration, contains("task_status = 'running'"));
      expect(migration, contains('attempt_count = q.attempt_count + 1'));
    });

    test('retry state uses bounded attempts and backoff', () {
      expect(migration, contains('q.attempt_count < q.max_attempts'));
      expect(migration, contains('available_at = now() + v_backoff'));
      expect(migration, contains('least(3600'));
      expect(migration, contains('last_error'));
    });

    test('remaining and regenerate commands are exact-scope only', () {
      expect(
        artifactScopeMigration,
        contains('a.finalize_run_id = p_finalize_run_id'),
      );
      expect(artifactScopeMigration, contains('f.scope_key = p_scope_key'));
      expect(artifactScopeMigration, contains('p_regenerate_all'));
      expect(
        artifactScopeMigration,
        contains("or (a.artifact_status in ('queued','failed')"),
      );
    });

    test(
      'artifact scope repair is canonical, bounded, and history preserving',
      () {
        expect(
          artifactScopeMigration,
          contains('resolve_closeout_artifact_scope'),
        );
        expect(artifactScopeMigration, contains('closeout_artifact_scope_key'));
        expect(
          artifactScopeMigration,
          contains("'exhibitor_has_no_qualifying_entries'"),
        );
        expect(artifactScopeMigration, contains("artifact_status = 'failed'"));
        expect(artifactScopeMigration, contains("'invalid_scope'"));
        expect(
          artifactScopeMigration,
          contains('insert into public.show_report_artifacts'),
        );
        expect(artifactScopeMigration, isNot(contains('delete from')));
      },
    );

    test(
      'enqueue refuses noncanonical scope and prevents duplicate active tasks',
      () {
        expect(
          artifactScopeMigration,
          contains('a.scope_key = public.closeout_artifact_scope_key'),
        );
        expect(
          artifactScopeMigration,
          contains('on conflict (report_artifact_id, task_type)'),
        );
        expect(
          artifactScopeMigration,
          contains("a.metadata ->> 'scope_key' = a.scope_key"),
        );
      },
    );

    test('dashboard uses aggregate counts and a bounded artifact page', () {
      expect(migration, contains('get_closeout_dashboard_scoped'));
      expect(migration, contains('artifact_counts as'));
      expect(migration, contains('task_counts as'));
      expect(
        migration,
        contains('least(coalesce(p_artifact_limit, 100), 200)'),
      );
      expect(migration, isNot(contains('storage.objects')));
    });

    test('dashboard task counts are exact show, run, and scope only', () {
      expect(artifactScopeMigration, contains('q.show_id = p_show_id'));
      expect(
        artifactScopeMigration,
        contains('join current_artifacts a on a.id = q.report_artifact_id'),
      );
      expect(artifactScopeMigration, contains('f.section_ids = p_section_ids'));
      expect(artifactScopeMigration, contains("'retryable_failed'"));
    });

    test('historical data is never deleted or broadly backfilled', () {
      expect(migration, isNot(contains('delete from')));
      expect(migration, isNot(contains('truncate')));
      expect(migration, isNot(contains('set artifact_key =')));
      expect(migration, contains('Historical rows keep a null artifact_key'));
    });
  });

  group('authenticated command boundary', () {
    test('Edge Function authorizes every queue command', () {
      expect(edgeFunction, contains('supabase.auth.getUser'));
      expect(edgeFunction, contains('user_can_finalize_show'));
      expect(edgeFunction, contains('generate_remaining'));
      expect(edgeFunction, contains('regenerate_all'));
      expect(edgeFunction, contains('requeue_closeout_render_tasks'));
    });

    test('page load and refresh have no email invocation', () {
      final load = methodBody(
        'Future<void> _loadData()',
        'Future<void> _saveArbaDetails()',
      );
      final refresh = methodBody(
        'Future<void> _refreshDashboardOnly',
        '@override\n  void initState()',
      );
      expect('$load$refresh', isNot(contains('send-closeout-report-email')));
      expect('$load$refresh', isNot(contains('_sendAllExhibitorReports')));
      expect('$load$refresh', isNot(contains('_sendAllClubReports')));
    });
  });
}
