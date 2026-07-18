import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final closeoutSource = File(
    'lib/screens/admin/show_closeout.dart',
  ).readAsStringSync();
  final closeoutWidgetsSource = File(
    'lib/screens/admin/closeout/widgets/closeout_scope_widgets.dart',
  ).readAsStringSync();
  final arbaLoaderSource = File(
    'lib/screens/admin/closeout/data/loaders/arba_report_loader.dart',
  ).readAsStringSync();
  final migration = File(
    'supabase/migrations/20260714055153_closeout_read_only_dashboard_and_render_queue.sql',
  ).readAsStringSync();
  final artifactScopeMigration = File(
    'supabase/migrations/20260715012121_fix_closeout_artifact_scope.sql',
  ).readAsStringSync();
  final generationStatusMigration = File(
    'supabase/migrations/20260715031210_closeout_generation_status_timestamps.sql',
  ).readAsStringSync();
  final reviewReportMigration = File(
    'supabase/migrations/20260715102607_closeout_review_report_details.sql',
  ).readAsStringSync();
  final finalFailureMigration = File(
    'supabase/migrations/20260715104020_closeout_final_report_failures.sql',
  ).readAsStringSync();
  final artifactDashboardMigration = File(
    'supabase/migrations/20260716014542_fix_closeout_dashboard_artifact_scope.sql',
  ).readAsStringSync();
  final artifactIdentityRepairMigration = File(
    'supabase/migrations/20260716044748_fix_closeout_artifact_scope_duplicate_identity.sql',
  ).readAsStringSync();
  final paybackSpeciesMigration = File(
    'supabase/migrations/20260717175551_fix_payback_schedule_species_matching.sql',
  ).readAsStringSync();
  final deferredArbaMigration = File(
    'supabase/migrations/20260717202959_defer_arba_until_report_delivery.sql',
  ).readAsStringSync();
  final deferredArbaProgressMigration = File(
    'supabase/migrations/20260717204006_exclude_deferred_arba_from_closeout_progress.sql',
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
    test('manual report generation retains canonical run identity', () {
      expect(closeoutSource, isNot(contains("'manual-run'")));

      final createBody = methodBody(
        'Future<ReportArtifactSummary> _createManualReportArtifact({',
        'List<String> _metadataSectionIds(',
      );
      expect(createBody, contains('_finalizeRunIdForSelectedScope'));
      expect(createBody, contains("'finalize_run_id': finalizeRunId"));

      final generateBody = methodBody(
        'Future<void> _generateReportByName(',
        'Future<void> _downloadReportByName(',
      );
      expect(
        generateBody,
        contains('.where((r) => r.finalizeRunId == finalizeRunId)'),
      );
      expect(
        generateBody,
        contains('r.scopeKey == _resolvedCloseoutScope.stableScopeKey'),
      );
      expect(generateBody, contains('finalizeRunId: finalizeRunId'));
    });

    test('bulk regeneration and dashboards preserve species scope', () {
      final closeoutSource = File(
        'lib/screens/admin/show_closeout.dart',
      ).readAsStringSync();
      final runnerSource = File(
        'supabase/functions/run-closeout/index.ts',
      ).readAsStringSync();
      final migration = File(
        'supabase/migrations/20260718224839_species_scoped_closeout_regeneration.sql',
      ).readAsStringSync();

      expect(
        closeoutSource,
        contains("'get_closeout_dashboard_scoped_for_species'"),
      );
      expect(closeoutSource, contains("'species_filter':"));
      expect(
        runnerSource,
        contains('"requeue_closeout_render_tasks_for_species"'),
      );
      expect(runnerSource, contains('p_species_filter: speciesFilter'));
      expect(
        migration,
        contains("lower(a.metadata ->> 'species') = v_species"),
      );
      expect(migration, contains('get_closeout_dashboard_scoped_for_species'));
    });

    test('cavy reports use fixed award scoring and stored download names', () {
      final closeoutSource = File(
        'lib/screens/admin/show_closeout.dart',
      ).readAsStringSync();
      final sweepstakesLoader = File(
        'lib/screens/admin/closeout/data/loaders/sweepstakes_report_loader.dart',
      ).readAsStringSync();
      final detailLoader = File(
        'lib/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart',
      ).readAsStringSync();
      final migration = File(
        'supabase/migrations/20260718230151_fix_cavy_sweepstakes_points_and_report_download_names.sql',
      ).readAsStringSync();

      expect(
        sweepstakesLoader,
        contains("'calculate_cavy_sweepstakes_for_section'"),
      );
      expect(
        detailLoader,
        contains("'calculate_cavy_sweepstakes_for_section'"),
      );
      expect(
        closeoutSource,
        contains('fileName: _downloadFileNameForArtifact'),
      );
      expect(migration, isNot(contains("when 'BOV' then 'BOV'")));
      expect(migration, contains("when 'BOG' then 'BOV'"));
      expect(migration, contains("'cavy-fixed-v1'"));
      expect(migration, contains("cavy_award_points"));

      final routingMigration = File(
        'supabase/migrations/20260718231616_route_cavy_through_fixed_sweepstakes_calculator.sql',
      ).readAsStringSync();
      expect(
        routingMigration,
        contains('calculate_sweepstakes_for_breed_legacy'),
      );
      expect(
        routingMigration,
        contains('calculate_cavy_sweepstakes_for_section'),
      );
      expect(
        routingMigration,
        contains("calculation_version = 'cavy-fixed-v1'"),
      );
    });

    test('regeneration reuses the finalize-run artifact identity owner', () {
      final createBody = methodBody(
        'Future<ReportArtifactSummary> _createManualReportArtifact({',
        'List<String> _metadataSectionIds(',
      );
      expect(createBody, contains("'closeout_artifact_identity'"));
      expect(createBody, contains("'p_metadata': scopedMetadata"));
      expect(createBody, contains(".eq('finalize_run_id', finalizeRunId)"));
      expect(createBody, contains(".eq('report_name', reportName)"));
      expect(createBody, contains('if (identityOwner != null)'));
      expect(createBody, contains(".eq('id', identityOwner['id'])"));
      expect(
        createBody.indexOf('if (identityOwner != null)'),
        lessThan(createBody.indexOf('.insert({')),
      );
    });

    test('Paybacks Generate creates or renders before queueing', () {
      final body = methodBody(
        'Future<void> _queueReportByName(',
        'Future<void> _downloadReportByName(',
      );
      expect(body, contains("'payback_report'"));
      expect(body, contains('await _generateReportByName('));
      expect(
        body.indexOf('await _generateReportByName('),
        lessThan(body.indexOf('await _queueExistingArtifacts(')),
      );
      expect(
        body.indexOf('return;', body.indexOf('await _generateReportByName(')),
        lessThan(body.indexOf('await _queueExistingArtifacts(')),
      );
    });

    test('Paybacks only joins schedules for the entry species', () {
      expect(
        paybackSpeciesMigration,
        contains('lower(trim(r.applies_to_species)) = se.species_key'),
      );
    });

    test('bulk generation defers ARBA until report delivery', () {
      expect(
        deferredArbaMigration,
        contains("a.report_name <> 'arba_report'::public.report_type"),
      );
      expect(deferredArbaMigration, contains('deferred_until_report_delivery'));
      expect(
        deferredArbaMigration,
        contains(
          'enqueue_report_render_tasks(p_show_id, p_finalize_run_id, true)',
        ),
      );
      expect(
        deferredArbaProgressMigration,
        contains("'deferred_until_report_delivery', true"),
      );
      expect(
        deferredArbaProgressMigration,
        contains("review.value ->> 'report_name' <> 'arba_report'"),
      );
      expect(
        deferredArbaProgressMigration,
        contains("#- '{by_report,arba_report}'"),
      );
    });

    test('ARBA uses exhibitor and club sent dates, not generation dates', () {
      expect(arbaLoaderSource, contains(".from('show_closeout_state')"));
      expect(arbaLoaderSource, contains('exhibitor_emails_sent_at'));
      expect(arbaLoaderSource, contains('club_reports_sent_at'));
      expect(arbaLoaderSource, isNot(contains('_loadGeneratedAt(')));
    });

    test('state club sanction email remains a species-neutral fallback', () {
      final body = methodBody(
        'Future<List<_ClubEmailTarget>> _loadClubEmailTargets() async',
        'Future<Map<String, String>> _loadSpeciesByBreedName(',
      );
      expect(body, contains('if (email.isEmpty) continue;'));
      expect(
        body,
        contains(
          "final species = sanctioningBody == 'STATE CLUB'\n"
          "          ? 'combined'",
        ),
      );
      expect(body, contains('species: contact.species'));
    });

    for (final report in const <(String, String)>[
      ('Ribbon Report', 'ribbon_payout_report'),
      ('Judge Report', 'judge_report'),
      ('Breed Judged Totals Report', 'breed_judged_totals_report'),
    ]) {
      test('${report.$1} Generate creates or renders before queueing', () {
        final body = methodBody(
          'Future<void> _queueReportByName(',
          'Future<void> _downloadReportByName(',
        );
        expect(body, contains("'${report.$2}'"));
        final generateIndex = body.indexOf('await _generateReportByName(');
        final returnIndex = body.indexOf('return;', generateIndex);
        final queueIndex = body.indexOf('await _queueExistingArtifacts(');
        expect(generateIndex, isNonNegative);
        expect(returnIndex, greaterThan(generateIndex));
        expect(returnIndex, lessThan(queueIndex));
      });
    }

    test('initial load uses the scoped dashboard and performs no writes', () {
      final body = methodBody(
        'Future<void> _loadData()',
        'Future<void> _saveArbaDetails()',
      );

      expect(body, contains('_loadDashboardSummary('));
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

      expect(body, contains('_loadDashboardSummary('));
      expect(body, isNot(contains('show_results_readiness')));
      expect(body, isNot(contains('_ensureReportsLoaded')));
      expect(body, isNot(contains('.insert(')));
      expect(body, isNot(contains('.update(')));
    });

    test('dashboard query is scoped, bounded, and has no storage calls', () {
      final body = methodBody(
        'Future<CloseoutDashboard> _loadDashboardSummary({',
        'Future<void> _ensureReportsLoaded',
      );

      expect(body, contains("'get_closeout_dashboard_scoped_for_species'"));
      expect(body, contains("'p_scope_key'"));
      expect(body, contains("'p_section_ids'"));
      expect(body, contains("'p_artifact_limit': pageSize"));
      expect(body, contains('while (artifactPage.hasMore)'));
      expect(body, contains('reportsById[artifact.id] = artifact'));
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
      expect(body, contains('counts.queued + counts.running > 0'));
      expect(body, contains('counts.remaining > 0'));
      expect(body, contains('_dashboardPoller.update'));
      expect(body, contains('_closeoutScreenIsVisible'));
      expect(closeoutSource, contains('_dashboardRefreshPending'));
      expect(closeoutSource, contains('_dashboardRefreshInFlight'));
      expect(closeoutSource, contains('_dashboardPoller.dispose()'));
    });

    test(
      'queue confirmation refreshes the parent dashboard before polling',
      () {
        final body = methodBody(
          'Future<void> _showReportsQueuedDialog',
          'Future<void> _retryFailedReports',
        );
        expect(body, contains('await showDialog<void>'));
        expect(
          body,
          contains('await _refreshDashboardOnly(includeReports: true)'),
        );
        expect(body, contains('_scheduleDashboardPolling()'));
      },
    );

    test(
      'one refresh updates counts and the current artifact caches together',
      () {
        final body = methodBody(
          'Future<void> _refreshDashboardOnly',
          'void _markDashboardContextChanged()',
        );
        expect(body, contains('_dashboard = dashboard'));
        expect(body, contains('_rebuildReportCaches()'));
        expect(body, contains('_scheduleDashboardPolling()'));
      },
    );

    test(
      'stale scope responses are ignored and a replacement read is retained',
      () {
        final body = methodBody(
          'Future<void> _refreshDashboardOnly',
          'void _markDashboardContextChanged()',
        );
        expect(body, contains('requestRevision != _dashboardContextRevision'));
        expect(body, contains('requestedScopeKey !='));
        expect(body, contains('_dashboardRefreshPending = true'));
        expect(body, contains('while (_dashboardRefreshPending && mounted)'));
      },
    );

    test('visibility resume performs an immediate parent refresh', () {
      final body = methodBody(
        'void didChangeAppLifecycleState',
        'bool get _closeoutScreenIsVisible',
      );
      expect(body, contains('_dashboardPoller.resumeAndRefresh()'));
      expect(body, contains('_dashboardPoller.pause()'));
    });

    test('dashboard response is rejected unless show and scope match', () {
      final body = methodBody(
        'Future<CloseoutDashboard> _loadDashboardSummary({',
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

  group('Closeout artifact status UI contract', () {
    test('pagination merges every page by artifact ID', () {
      final body = methodBody(
        'Future<CloseoutDashboard> _loadDashboardSummary({',
        'Future<void> _ensureReportsLoaded',
      );
      expect(body, contains('while (artifactPage.hasMore)'));
      expect(body, contains('reportsById[artifact.id] = artifact'));
      expect(body, contains('candidateOffset <= nextOffset'));
    });

    test('Other and ARBA reports can regenerate generated artifacts', () {
      final body = methodBody(
        'Widget _buildArtifactActions({',
        'List<Widget> _buildReportStatusAndActions()',
      );
      expect(
        body,
        contains(
          'if (isArbaReport ||\n'
          '            uiStatus != CloseoutReportUiStatus.generated ||\n'
          '            _selectedGroupAllowsRegeneration)',
        ),
      );
      expect(
        body,
        contains("final isArbaReport = reportName == 'arba_report';"),
      );
      expect(
        closeoutSource,
        contains(
          "bool get _selectedGroupAllowsRegeneration => _selectedGroup == 'other';",
        ),
      );
      expect(body, contains("CloseoutReportUiStatus.failed => 'Retry'"));
      expect(
        body,
        contains("CloseoutReportUiStatus.generating => 'Generating'"),
      );
      expect(body, contains('canDownload'));
      expect(body, contains('_selectedReportCanEmail'));
    });

    test('exhibitor choices come from scoped artifacts, not all entries', () {
      final body = methodBody(
        'Future<void> _loadExhibitors() async',
        'Future<void> _loadBreedsForBreedScopedReports() async',
      );
      expect(body, contains('widget.reports.where'));
      expect(body, contains('artifact.reportName == reportName'));
      expect(body, contains('artifact.isCurrent'));
      expect(body, isNot(contains(".from('entries')")));
      expect(body, contains(".from('exhibitors')"));
      expect(body, contains(".select('id, email')"));
    });
  });

  group('database manifest and queue contract', () {
    test('review details retain latest task history behind artifact cause', () {
      expect(finalFailureMigration, contains("'task_history_category'"));
      expect(finalFailureMigration, contains("'task_history_message'"));
      expect(finalFailureMigration, contains("then 'statement_timeout'"));
      expect(finalFailureMigration, contains("then 'read_only_violation'"));
      expect(finalFailureMigration, contains("task.failed_at"));
      expect(finalFailureMigration, contains("task.id desc"));
      expect(
        finalFailureMigration,
        contains("a.metadata ->> 'error_category' = 'invalid_scope'"),
      );
    });

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
      'artifact scope repair preserves finalize-run identity uniqueness',
      () {
        expect(
          artifactIdentityRepairMigration,
          contains('if v_artifact.artifact_key = v_scope.artifact_key then'),
        );
        expect(
          artifactIdentityRepairMigration,
          contains('and a.artifact_key = v_scope.artifact_key'),
        );
        expect(
          artifactIdentityRepairMigration,
          isNot(contains('and a.is_current = true and a.id <>')),
        );
        expect(
          artifactIdentityRepairMigration,
          contains('if v_replacement_id is not null then'),
        );
        expect(
          artifactIdentityRepairMigration,
          contains('insert into public.show_report_artifacts'),
        );
        expect(artifactIdentityRepairMigration, isNot(contains('drop index')));
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

    test('dashboard follows the selected run, not artifact scope keys', () {
      expect(
        artifactDashboardMigration,
        contains('join selected_run r on r.id = a.finalize_run_id'),
      );
      expect(
        artifactDashboardMigration,
        isNot(contains('a.scope_key = p_scope_key')),
      );
      expect(
        artifactDashboardMigration,
        contains("'storage_path', a.storage_path"),
      );
      expect(
        artifactDashboardMigration,
        contains("'section_ids', to_jsonb(a.section_ids)"),
      );
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

    test(
      'generation timestamps remain in the same scoped dashboard response',
      () {
        expect(
          generationStatusMigration,
          contains('create function public.get_closeout_dashboard_scoped'),
        );
        expect(generationStatusMigration, contains("'{task_counts}'"));
        expect(generationStatusMigration, contains("'last_activity_at'"));
        expect(generationStatusMigration, contains("'completed_at'"));
        expect(generationStatusMigration, contains('a.is_current = true'));
        expect(
          generationStatusMigration,
          contains('f.scope_key = p_scope_key'),
        );
        expect(
          generationStatusMigration,
          contains('f.section_ids = p_section_ids'),
        );
      },
    );

    test('applied generation timestamp migration has no review changes', () {
      expect(generationStatusMigration, isNot(contains('review_reports')));
      expect(generationStatusMigration, isNot(contains('review_rows as')));
      expect(
        generationStatusMigration,
        contains('rename to get_closeout_dashboard_scoped_without_activity'),
      );
    });

    test('review reports exclude historical runs, artifacts, and tasks', () {
      expect(
        reviewReportMigration,
        contains('join selected_run r on r.id = a.finalize_run_id'),
      );
      expect(reviewReportMigration, contains("'{review_reports}'"));
      expect(reviewReportMigration, contains("'review_group'"));
      expect(reviewReportMigration, contains('a.is_current = true'));
      expect(reviewReportMigration, contains('task.report_artifact_id = a.id'));
      expect(
        reviewReportMigration,
        contains('order by task.created_at desc, task.id desc'),
      );
      expect(reviewReportMigration, contains("'retryable_failure'"));
      expect(reviewReportMigration, contains("'non_retryable_failure'"));
      expect(reviewReportMigration, contains("'missing'"));
      expect(reviewReportMigration, contains("'active'"));
    });

    test('review action scrolls to its dedicated panel key', () {
      expect(closeoutSource, contains('final GlobalKey _reviewPanelKey'));
      expect(
        closeoutSource,
        contains('final reviewContext = _reviewPanelKey.currentContext'),
      );
      expect(closeoutSource, contains('Scrollable.ensureVisible('));
      expect(closeoutSource, contains('reviewContext,'));
      expect(
        closeoutSource,
        isNot(
          contains('final reportsContext = _reportsSectionKey.currentContext'),
        ),
      );
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
