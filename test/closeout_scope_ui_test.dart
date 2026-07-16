import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/widgets/closeout_scope_widgets.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

Widget _scrollHost(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

const _reviewReports = <CloseoutReviewReport>[
  CloseoutReviewReport(
    artifactId: 'retryable-artifact',
    finalizeRunId: 'run-1',
    reportTitle: 'Exhibitor Report',
    reportName: 'exhibitor_report',
    sectionId: 'section-a',
    sectionLabel: 'Rabbit Open A',
    showLetter: 'A',
    scope: 'OPEN',
    species: 'rabbit',
    exhibitorName: 'Alex Example',
    breedName: 'Dutch',
    artifactStatus: 'failed',
    taskStatus: 'failed',
    errorCategory: 'renderer_timeout',
    errorMessage: 'The report renderer timed out.',
    taskHistoryCategory: 'worker_lease_expired',
    taskHistoryMessage: 'The worker lease expired after the render failed.',
    retryable: true,
    attemptCount: 2,
    maxAttempts: 5,
    group: CloseoutReviewGroup.retryableFailure,
  ),
  CloseoutReviewReport(
    artifactId: 'non-retryable-artifact',
    finalizeRunId: 'run-1',
    reportTitle: 'ARBA Report',
    reportName: 'arba_report',
    sectionId: 'section-b',
    sectionLabel: 'Cavy Youth B',
    showLetter: 'B',
    scope: 'YOUTH',
    species: 'cavy',
    clubName: 'County Cavy Club',
    sanctioningBody: 'ARBA',
    artifactStatus: 'failed',
    taskStatus: 'failed',
    errorCategory: 'missing_sanction_number',
    errorMessage: 'A sanction number is required for this report.',
    retryable: false,
    attemptCount: 5,
    maxAttempts: 5,
    group: CloseoutReviewGroup.nonRetryableFailure,
  ),
];

void main() {
  group('closeout failure display', () {
    test('maps the current ARBA Best In Show address error', () {
      final display = closeoutFailureDisplay(
        errorCategory: 'render_error',
        taskLastError:
            'Exception: ARBA report is blocked until required closeout data is complete: Best In Show Rabbit owner city/state.',
      );

      expect(display.title, 'Missing Best In Show Exhibitor Address');
      expect(
        display.message,
        'The Best In Show exhibitor is missing a city or state.',
      );
    });

    test('matches Best In Show address wording case-insensitively', () {
      final display = closeoutFailureDisplay(
        errorCategory: 'render_error',
        metadataLastError: 'BEST IN SHOW EXHIBITOR CITY/STATE is required',
      );

      expect(display.title, 'Missing Best In Show Exhibitor Address');
    });

    test('prefers structured missing field and label metadata', () {
      final report = CloseoutReviewReport.fromJson({
        'artifact_id': 'structured',
        'finalize_run_id': 'run',
        'report_name': 'arba_report',
        'artifact_status': 'failed',
        'task_status': 'failed',
        'error_category': 'missing_required_closeout_data',
        'retryable': false,
        'review_group': 'non_retryable_failure',
        'metadata': {
          'missing_field': 'best_in_show_exhibitor_address',
          'missing_label': 'Best In Show Exhibitor Address',
        },
      });
      final display = closeoutFailureDisplay(
        errorCategory: report.errorCategory,
        missingField: report.missingField,
        missingLabel: report.missingLabel,
      );

      expect(display.title, 'Missing Best In Show Exhibitor Address');
    });

    test('uses structured exhibitor name in the action message', () {
      final report = CloseoutReviewReport.fromJson({
        'artifact_id': 'named-structured',
        'finalize_run_id': 'run',
        'report_name': 'arba_report',
        'artifact_status': 'failed',
        'task_status': 'failed',
        'error_category': 'missing_required_closeout_data',
        'retryable': false,
        'review_group': 'non_retryable_failure',
        'metadata': {
          'missing_field': 'best_in_show_exhibitor_address',
          'missing_label': 'Best In Show Exhibitor Address',
          'exhibitor_name': 'Brielle Parker',
        },
      });
      final display = closeoutFailureDisplay(
        errorCategory: report.errorCategory,
        missingField: report.missingField,
        missingLabel: report.missingLabel,
        exhibitorName: report.exhibitorName,
      );

      expect(
        display.message,
        'Brielle Parker is missing city or state. '
        'Update the exhibitor record, then regenerate this report.',
      );
    });

    test('uses the most useful raw source for an unknown failure', () {
      final display = closeoutFailureDisplay(
        errorCategory: 'unknown',
        metadataLastError: 'Specific metadata failure',
        taskLastError: 'Less preferred task failure',
      );

      expect(display.title, 'The report could not be rendered');
      expect(display.message, 'Specific metadata failure');
    });

    test('removes a leading Exception from fallback text', () {
      final display = closeoutFailureDisplay(
        errorCategory: 'render_error',
        fallbackError: 'Exception: An unknown renderer failure occurred.',
      );

      expect(display.message, 'An unknown renderer failure occurred.');
    });

    testWidgets('actual ARBA review payload shows one actionable failure', (
      tester,
    ) async {
      final report = CloseoutReviewReport.fromJson({
        'report_name': 'arba_report',
        'artifact_status': 'failed',
        'task_status': 'failed',
        'review_group': 'non_retryable_failure',
        'retryable': false,
        'metadata': {
          'scope': 'YOUTH',
          'section_label': 'Youth A',
          'error_category': 'render_error',
          'error_message': 'The report could not be rendered.',
          'last_error':
              'Exception: ARBA report is blocked until required closeout data is complete: Best In Show Rabbit owner city/state.',
        },
      });

      expect(report.metadataLastError, contains('Best In Show Rabbit'));
      expect(report.metadataErrorMessage, 'The report could not be rendered.');

      await tester.pumpWidget(
        _scrollHost(
          CloseoutReportsNeedingReviewPanel(
            reports: [report],
            initiallyExpanded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Missing Best In Show Exhibitor Address'),
        findsOneWidget,
      );
      expect(
        find.text('The Best In Show exhibitor is missing a city or state.'),
        findsOneWidget,
      );
      final failureTitle = tester.widget<Text>(
        find.text('Missing Best In Show Exhibitor Address'),
      );
      final failureMessage = tester.widget<Text>(
        find.text('The Best In Show exhibitor is missing a city or state.'),
      );
      expect(failureTitle.style?.fontSize, 16);
      expect(failureMessage.style?.fontSize, 15);
      expect(find.text('The report could not be rendered.'), findsNothing);
    });

    test('parses flattened source-specific error fields', () {
      final report = CloseoutReviewReport.fromJson({
        'report_name': 'arba_report',
        'artifact_status': 'failed',
        'task_status': 'failed',
        'review_group': 'non_retryable_failure',
        'retryable': false,
        'metadata_last_error': 'metadata detail',
        'metadata_error_message': 'metadata message',
        'metadata_error_category': 'render_error',
        'task_error_message': 'task message',
        'task_last_error': 'task detail',
        'error_message': 'legacy fallback',
      });

      expect(report.metadataLastError, 'metadata detail');
      expect(report.metadataErrorMessage, 'metadata message');
      expect(report.errorCategory, 'render_error');
      expect(report.taskErrorMessage, 'task message');
      expect(report.taskLastError, 'task detail');
      expect(report.errorMessage, 'legacy fallback');
    });
  });

  testWidgets('completed scope disables Finalize and shows completed state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CloseoutFinalizeActionButton(
          reportsBlocked: false,
          finalized: true,
          reportsStale: false,
          tooltipScope: 'Rabbit Open A, Open B, Open D, Youth A, Youth B',
          onPressed: null,
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('closeout-finalize-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Scope Finalized'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(
      find.byTooltip(
        'Reports are finalized for Rabbit Open A, Open B, Open D, Youth A, Youth B',
      ),
      findsOneWidget,
    );
  });

  testWidgets('incomplete scope restores enabled compact Finalize action', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      _host(
        CloseoutFinalizeActionButton(
          reportsBlocked: false,
          finalized: false,
          reportsStale: true,
          tooltipScope: 'Cavy Open A',
          onPressed: () => pressed = true,
        ),
      ),
    );

    expect(find.text('Finalize Selected Scope'), findsOneWidget);
    expect(find.byTooltip('Finalize reports for Cavy Open A'), findsOneWidget);
    await tester.tap(find.text('Finalize Selected Scope'));
    expect(pressed, isTrue);
  });

  testWidgets('Generate Remaining stays disabled at zero', (tester) async {
    await tester.pumpWidget(
      _host(const CloseoutGenerateRemainingButton(count: 0, onPressed: null)),
    );

    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('closeout-generate-remaining-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Generate Remaining (0)'), findsOneWidget);
  });

  testWidgets('active generation shows scoped progress and disables queueing', (
    tester,
  ) async {
    const progress = CloseoutGenerationProgress(
      queued: 463,
      running: 8,
      completed: 112,
      failed: 5,
    );
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const CloseoutGenerationStatusBanner(progress: progress),
            const CloseoutGenerateRemainingButton(
              count: 476,
              progress: progress,
              onPressed: null,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Generating reports'), findsOneWidget);
    expect(
      find.text('463 queued • 8 running • 112 completed • 5 failed'),
      findsOneWidget,
    );
    expect(find.text('Generating Reports — 112 of 588'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('closeout-generate-remaining-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(112 / 588, 0.0001),
    );
  });

  test('failed tasks are excluded from completed progress', () {
    const progress = CloseoutGenerationProgress(completed: 7, failed: 3);

    expect(progress.total, 10);
    expect(progress.percentComplete, 0.7);
    expect(progress.isComplete, isFalse);
    expect(progress.hasFailures, isTrue);
  });

  testWidgets(
    'finished generation reports failures and hides unavailable retry',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const CloseoutGenerationStatusBanner(
            progress: CloseoutGenerationProgress(
              completed: 7,
              failed: 3,
              remaining: 3,
            ),
          ),
        ),
      );

      expect(
        find.text('Report generation is complete. 3 reports need review.'),
        findsOneWidget,
      );
      expect(find.text('7 generated • 3 failed • 3 remaining'), findsOneWidget);
      expect(find.text('Retry Failed'), findsNothing);
    },
  );

  test('generation is complete only after all tasks complete', () {
    const progress = CloseoutGenerationProgress(completed: 588);

    expect(progress.total, 588);
    expect(progress.percentComplete, 1);
    expect(progress.isActive, isFalse);
    expect(progress.isComplete, isTrue);
  });

  testWidgets('waiting banner is distinct from active rendering', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CloseoutGenerationStatusBanner(
          progress: CloseoutGenerationProgress(queued: 12),
        ),
      ),
    );

    expect(
      find.text('Reports are queued and waiting to begin.'),
      findsOneWidget,
    );
    expect(find.textContaining('12 queued'), findsOneWidget);
  });

  testWidgets('complete banner shows generated total and timestamp', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CloseoutGenerationStatusBanner(
          progress: CloseoutGenerationProgress(
            completed: 12,
            completedAt: DateTime.utc(2026, 7, 15, 12, 30),
          ),
        ),
      ),
    );

    expect(find.text('Report generation is complete.'), findsOneWidget);
    expect(find.text('12 reports generated.'), findsOneWidget);
    expect(find.textContaining('Completed:'), findsOneWidget);
  });

  testWidgets('issues banner opens reports needing review', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _host(
        CloseoutGenerationStatusBanner(
          progress: const CloseoutGenerationProgress(
            completed: 9,
            failed: 2,
            remaining: 2,
          ),
          onViewReportsNeedingReview: () => opened = true,
        ),
      ),
    );

    await tester.tap(find.text('View Reports Needing Review'));
    expect(opened, isTrue);
  });

  testWidgets('banner action opens the dedicated review panel', (tester) async {
    var reviewOpen = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _scrollHost(
          Column(
            children: [
              CloseoutGenerationStatusBanner(
                progress: const CloseoutGenerationProgress(
                  completed: 7,
                  failed: 2,
                  remaining: 2,
                ),
                onViewReportsNeedingReview: () {
                  setState(() => reviewOpen = true);
                },
              ),
              CloseoutReportsNeedingReviewPanel(
                reports: _reviewReports,
                initiallyExpanded: reviewOpen,
              ),
              const ExpansionTile(
                title: Text('Reports & Distribution'),
                children: [Text('Normal report dropdown')],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('View Reports Needing Review'));
    await tester.pumpAndSettle();

    expect(reviewOpen, isTrue);
    expect(
      find.byKey(const ValueKey('closeout-reports-needing-review-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('closeout-review-report-retryable-artifact')),
      findsOneWidget,
    );
    expect(find.text('Normal report dropdown'), findsNothing);
  });

  testWidgets(
    'review reports are grouped and show report identity and errors',
    (tester) async {
      await tester.pumpWidget(
        _scrollHost(
          const CloseoutReportsNeedingReviewPanel(
            reports: _reviewReports,
            initiallyExpanded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retryable failures'), findsOneWidget);
      expect(find.text('Non-retryable failures'), findsOneWidget);
      expect(find.text('Exhibitor Report'), findsOneWidget);
      expect(find.text('exhibitor_report'), findsOneWidget);
      expect(
        find.text('Rabbit Open A • Show A • OPEN • rabbit'),
        findsOneWidget,
      );
      expect(find.text('Exhibitor: Alex Example'), findsOneWidget);
      expect(find.text('Breed: Dutch'), findsOneWidget);
      expect(find.text('Error category: renderer_timeout'), findsOneWidget);
      expect(find.text('The report could not be rendered'), findsNWidgets(2));
      expect(find.text('The report renderer timed out.'), findsOneWidget);
      expect(
        find.text('Latest task category: worker_lease_expired'),
        findsOneWidget,
      );
      expect(find.text('Club: County Cavy Club'), findsOneWidget);
      expect(find.text('Sanctioning body: ARBA'), findsOneWidget);
      expect(find.textContaining('Retryable: Yes'), findsOneWidget);
      expect(find.textContaining('Retryable: No'), findsOneWidget);
    },
  );

  testWidgets('stalled banner is non-alarming and prevents duplicate advice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CloseoutGenerationStatusBanner(
          progress: CloseoutGenerationProgress(
            queued: 4,
            isStalled: true,
            lastActivityAt: DateTime.utc(2026, 7, 15, 12),
          ),
        ),
      ),
    );

    expect(find.text('Report generation may be delayed'), findsOneWidget);
    expect(find.textContaining('no need to queue them again'), findsOneWidget);
    expect(find.textContaining('Last activity:'), findsOneWidget);
  });

  testWidgets('detailed summary retains every selected section label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CloseoutScopeSummaryText(
          primaryLabel: 'Rabbit • 5 sections',
          detailLabel: 'Open A, Open B, Open D, Youth A, Youth B',
        ),
      ),
    );

    expect(find.text('Rabbit • 5 sections'), findsOneWidget);
    expect(
      find.text('Open A, Open B, Open D, Youth A, Youth B'),
      findsOneWidget,
    );
  });

  testWidgets('section row is fully clickable and hides raw metadata', (
    tester,
  ) async {
    bool? selected;
    await tester.pumpWidget(
      _host(
        CloseoutSectionSelectionRow(
          selected: false,
          title: 'Open A • All Breed',
          subtitle: 'Rabbit • 261 entries',
          onChanged: (value) => selected = value,
        ),
      ),
    );

    expect(find.text('Open A • All Breed'), findsOneWidget);
    expect(find.text('Rabbit • 261 entries'), findsOneWidget);
    expect(find.textContaining('all • rabbit'), findsNothing);

    await tester.tap(find.text('Rabbit • 261 entries'));
    expect(selected, isTrue);
  });

  testWidgets('responsive action area does not overflow common widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in <double>[390, 1024]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _host(
          CloseoutResponsiveActionArea(
            primaryActions: [
              CloseoutFinalizeActionButton(
                reportsBlocked: false,
                finalized: false,
                reportsStale: true,
                tooltipScope: 'Rabbit Open A, Open B, Open D',
                onPressed: () {},
              ),
              const CloseoutGenerateRemainingButton(count: 0, onPressed: null),
              Tooltip(
                message:
                    'Regenerate all reports for Rabbit Open A, Open B, Open D',
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Regenerate All Reports'),
                ),
              ),
            ],
            distributionActions: [
              Tooltip(
                message:
                    'Send generated exhibitor reports for Rabbit Open A, Open B, Open D',
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Send Exhibitor Reports'),
                ),
              ),
              Tooltip(
                message:
                    'Send generated club reports for Rabbit Open A, Open B, Open D',
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Send Club Reports'),
                ),
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'overflow at $width px');
      expect(
        find.byTooltip(
          'Send generated exhibitor reports for Rabbit Open A, Open B, Open D',
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Regenerate all reports for Rabbit Open A, Open B, Open D',
        ),
        findsOneWidget,
      );
      if (width == 390) {
        expect(
          tester
              .getSize(find.byKey(const ValueKey('closeout-finalize-button')))
              .width,
          greaterThan(300),
        );
      }
    }
  });
}
