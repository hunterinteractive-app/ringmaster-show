import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/animal_sync_service.dart';
import 'package:ringmaster_show/widgets/animal_sync_panel.dart';

Map<String, dynamic> provider(String key, {bool ready = true, String? at}) => {
  'key': key,
  'name': key,
  'can_refresh': ready,
  'last_refreshed_at': at,
  if (!ready) 'unavailable_reason': 'Refresh integration pending',
};

void main() {
  testWidgets('unlinked accounts have no refresh button', (tester) async {
    final controller = AnimalSyncController(
      'owner',
      transport: (_) async => {'providers': []},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimalSyncPanel(
            ownerId: 'owner',
            controller: controller,
            onRefreshed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Refresh linked animals'), findsNothing);
  });

  testWidgets(
    'linked but unconfigured provider is visible without claiming success',
    (tester) async {
      final controller = AnimalSyncController(
        'owner',
        transport: (_) async => {
          'providers': [provider('HerdMaster', ready: false)],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimalSyncPanel(
              ownerId: 'owner',
              controller: controller,
              onRefreshed: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Not refreshed yet'), findsOneWidget);
      expect(
        find.textContaining('Refresh integration pending'),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    },
  );

  test(
    'refresh supports all registered providers and suppresses duplicate clicks',
    () async {
      final gate = Completer<void>();
      final calls = <String>[];
      var at = '2026-10-15T10:00:00Z';
      final controller = AnimalSyncController(
        'owner',
        transport: (body) async {
          expect(body['owner_id'], 'owner');
          if (body['action'] == 'status') {
            return {
              'providers': [
                provider('Breeder', at: at),
                provider('Future provider', at: at),
              ],
            };
          }
          calls.add(body['provider_key']);
          await gate.future;
          at = '2026-10-15T11:00:00Z';
          return {'refreshed': true};
        },
      );
      await controller.load();
      final first = controller.refresh();
      expect(await controller.refresh(), false);
      expect(calls, ['Breeder']);
      gate.complete();
      expect(await first, true);
      expect(calls, ['Breeder', 'Future provider']);
      expect(
        controller.providers.every(
          (p) => p.lastRefreshedAt == DateTime.parse(at),
        ),
        true,
      );
    },
  );

  test(
    'one provider failure preserves its successful timestamp and allows others',
    () async {
      const old = '2026-10-15T10:00:00Z';
      var success = false;
      final controller = AnimalSyncController(
        'owner',
        transport: (body) async {
          if (body['action'] == 'status') {
            return {
              'providers': [
                provider('Breeder', at: success ? '2026-10-15T11:00:00Z' : old),
                provider('HerdMaster', at: old),
              ],
            };
          }
          if (body['provider_key'] == 'HerdMaster') throw StateError('offline');
          success = true;
          return {'refreshed': true};
        },
      );
      await controller.load();
      expect(await controller.refresh(), true);
      expect(controller.providers.last.lastRefreshedAt, DateTime.parse(old));
      expect(controller.error, contains('HerdMaster could not refresh'));
    },
  );

  testWidgets('both screens share the same confirmed refresh status', (
    tester,
  ) async {
    var at = '2026-10-15T10:00:00Z';
    var reloads = 0;
    final controller = AnimalSyncController(
      'owner',
      transport: (body) async {
        if (body['action'] == 'refresh') {
          at = '2026-10-15T11:00:00Z';
          return {'refreshed': true};
        }
        return {
          'providers': [provider('Breeder', at: at)],
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < 2; i++)
                AnimalSyncPanel(
                  ownerId: 'owner',
                  controller: controller,
                  onRefreshed: () async {
                    reloads++;
                  },
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh linked animals').first);
    await tester.pumpAndSettle();
    expect(reloads, 1);
    expect(find.textContaining('Last refreshed'), findsNWidgets(2));
    expect(controller.providers.single.lastRefreshedAt, DateTime.parse(at));
  });
}
