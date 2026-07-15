import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/closeout_dashboard_poller.dart';

void main() {
  testWidgets('polls every three seconds and stops when work finishes', (
    tester,
  ) async {
    var refreshes = 0;
    final poller = CloseoutDashboardPoller(onRefresh: () async => refreshes++);
    addTearDown(poller.dispose);

    poller.update(active: true, visible: true);
    expect(poller.isPolling, isTrue);

    await tester.pump(const Duration(seconds: 3));
    expect(refreshes, 1);

    poller.update(active: false, visible: true);
    expect(poller.isPolling, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(refreshes, 1);
  });

  testWidgets('dashboard counts and artifacts refresh in the same callback', (
    tester,
  ) async {
    var remaining = 8;
    var completed = 0;
    var artifactStatuses = <String>['queued', 'queued'];
    late final CloseoutDashboardPoller poller;
    poller = CloseoutDashboardPoller(
      onRefresh: () async {
        remaining = 3;
        completed = 5;
        artifactStatuses = <String>['generated', 'failed'];
        poller.update(active: true, visible: true);
      },
    );
    addTearDown(poller.dispose);

    poller.update(active: true, visible: true);
    await tester.pump(const Duration(seconds: 3));

    expect(remaining, 3);
    expect(completed, 5);
    expect(artifactStatuses, ['generated', 'failed']);
    poller.dispose();
  });

  testWidgets(
    'visibility pause cancels polling and resume refreshes immediately',
    (tester) async {
      var refreshes = 0;
      final poller = CloseoutDashboardPoller(
        onRefresh: () async => refreshes++,
      );
      addTearDown(poller.dispose);

      poller.update(active: true, visible: true);
      poller.pause();
      await tester.pump(const Duration(seconds: 6));
      expect(refreshes, 0);
      expect(poller.isPolling, isFalse);

      await poller.resumeAndRefresh();
      expect(refreshes, 1);
      poller.dispose();
    },
  );

  testWidgets('overlapping refreshes collapse into one pending refresh', (
    tester,
  ) async {
    final firstRefresh = Completer<void>();
    var refreshes = 0;
    final poller = CloseoutDashboardPoller(
      onRefresh: () async {
        refreshes++;
        if (refreshes == 1) await firstRefresh.future;
      },
    );
    addTearDown(poller.dispose);

    final first = poller.refreshNow();
    await tester.pump();
    final second = poller.refreshNow();
    final third = poller.refreshNow();
    await tester.pump();
    expect(refreshes, 1);
    expect(poller.refreshInFlight, isTrue);

    firstRefresh.complete();
    await first;
    await second;
    await third;
    expect(refreshes, 2);
    expect(poller.refreshInFlight, isFalse);
    poller.dispose();
  });

  testWidgets('dispose cancels future polling callbacks', (tester) async {
    var refreshes = 0;
    final poller = CloseoutDashboardPoller(onRefresh: () async => refreshes++);
    poller.update(active: true, visible: true);
    poller.dispose();

    await tester.pump(const Duration(seconds: 6));
    expect(refreshes, 0);
    expect(poller.isPolling, isFalse);
  });
}
