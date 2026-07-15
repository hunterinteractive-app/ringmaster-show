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

void main() {
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
    var retryPressed = false;

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            CloseoutGenerationProgressCard(
              progress: progress,
              onRetryFailed: () => retryPressed = true,
            ),
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
    expect(find.text('112 of 588 completed'), findsOneWidget);
    expect(find.text('463 waiting • 8 rendering • 5 failed'), findsOneWidget);
    expect(find.text('5 reports failed to generate.'), findsOneWidget);
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

    await tester.tap(find.text('Retry Failed'));
    expect(retryPressed, isTrue);
  });

  test('failed tasks are excluded from completed progress', () {
    const progress = CloseoutGenerationProgress(completed: 7, failed: 3);

    expect(progress.total, 10);
    expect(progress.percentComplete, 0.7);
    expect(progress.isComplete, isFalse);
    expect(progress.hasFailures, isTrue);
  });

  test('generation is complete only after all tasks complete', () {
    const progress = CloseoutGenerationProgress(completed: 588);

    expect(progress.total, 588);
    expect(progress.percentComplete, 1);
    expect(progress.isActive, isFalse);
    expect(progress.isComplete, isTrue);
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
