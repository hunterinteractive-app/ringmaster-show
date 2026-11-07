import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/support_idle_controller.dart';
import 'package:ringmaster_show/widgets/support_idle_guard.dart';

void main() {
  testWidgets(
    'warns after idle, Continue preserves edits, then expires without input',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1);
      var renewals = 0;
      var exits = 0;
      final controller = SupportIdleController(
        expiresAt: now.add(const Duration(minutes: 30)),
        now: () => now,
        renew: () async {
          renewals++;
          return now.add(const Duration(minutes: 30));
        },
      );
      final text = TextEditingController(text: 'Unsaved correction');
      await tester.pumpWidget(
        MaterialApp(
          home: SupportIdleGuard(
            controller: controller,
            onExit: () async {
              exits++;
            },
            child: Scaffold(body: TextField(controller: text)),
          ),
        ),
      );
      now = now.add(const Duration(minutes: 28));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Continue Support Session'), findsOneWidget);
      expect(
        renewals,
        0,
      ); // Timer and background rebuilds never count as activity.
      await tester.tap(find.text('Continue Support Session'));
      await tester.pump();
      expect(renewals, 1);
      expect(controller.warning, false);
      expect(text.text, 'Unsaved correction');
      now = now.add(const Duration(minutes: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.expired, true);
      expect(find.text('Continue Support Session'), findsNothing);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('support-idle-content')),
            )
            .absorbing,
        true,
      );
      await controller.continueSession();
      expect(renewals, 1); // A stale tab cannot revive an expired session.
      await tester.tap(find.text('Exit Support Mode'));
      expect(exits, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      text.dispose();
    },
  );

  testWidgets(
    'foreground input is throttled, renews beyond initial deadline, and never heartbeats',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1);
      var calls = 0;
      final controller = SupportIdleController(
        expiresAt: now.add(const Duration(minutes: 30)),
        now: () => now,
        renew: () async {
          calls++;
          return now.add(const Duration(minutes: 30));
        },
      );
      for (var minute = 0; minute < 90; minute++) {
        now = now.add(const Duration(minutes: 1));
        controller.activity();
        await tester.pump();
        controller.activity();
        controller.activity();
        await tester.pump();
        expect(controller.expired, false);
      }
      expect(calls, 90);
      now = now.add(const Duration(seconds: 30));
      await tester.pump(
        const Duration(seconds: 30),
      ); // One trailing input update.
      expect(calls, 91);
      now = now.add(const Duration(minutes: 29));
      await tester.pump(const Duration(minutes: 29));
      expect(calls, 91);
      expect(controller.warning, true);
      controller.dispose();
    },
  );

  testWidgets('a suspended tab cannot renew later from stale queued input', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 1, 1);
    var calls = 0;
    final controller = SupportIdleController(
      expiresAt: now.add(const Duration(minutes: 30)),
      now: () => now,
      renew: () async {
        calls++;
        return now.add(const Duration(minutes: 30));
      },
    );
    controller.activity();
    await tester.pump();
    controller
        .activity(); // Trailing input is pending when the browser suspends.
    now = now.add(const Duration(minutes: 29));
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    expect(controller.warning, true);
    controller.dispose();
  });

  testWidgets(
    'failed renewal keeps the deadline and ignores completion after Exit',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1);
      final pending = Completer<DateTime>();
      var fail = true;
      final controller = SupportIdleController(
        expiresAt: now.add(const Duration(minutes: 30)),
        now: () => now,
        renew: () {
          if (fail) return Future.error(StateError('offline'));
          return pending.future;
        },
      );
      final original = controller.remaining;
      await controller.continueSession();
      expect(controller.remaining, original);
      expect(controller.error, isNotNull);
      fail = false;
      final result = controller.continueSession();
      controller.stop();
      pending.complete(now.add(const Duration(hours: 1)));
      await result;
      expect(controller.remaining, original);
      controller.dispose();
    },
  );
}
