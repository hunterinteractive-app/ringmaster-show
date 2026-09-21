import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/superintendent/superintendent_lineup_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final mutations = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        Object? result = [];
        final path = request.url.path;
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        final show =
            body['p_show_id'] ??
            request.url.queryParameters['show_id']?.substring(3);
        final names = show == 'sala'
            ? ['Open A', 'Open B', 'Youth A', 'Youth B']
            : ['Open A', 'Youth A'];
        if (path.endsWith('/superintendent_workspaces')) {
          result = {'id': 'shared'};
        }
        if (path.endsWith('/shows')) {
          result = {'superintendent_judge_order_published': false};
        }
        if (path.endsWith('/show_sections')) {
          result = [
            for (final name in names)
              {
                'id': '$show-$name',
                'display_name': name,
                'kind': name.startsWith('Open') ? 'open' : 'youth',
                'letter': name.split(' ').last,
              },
          ];
        }
        if (path.endsWith('/get_show_lineup_breed_counts')) {
          result = [
            for (final name in names)
              {
                'show_id': show,
                'section_id': '$show-$name',
                'show_letter': name.split(' ').last,
                'section_label': name,
                'breed': 'Havana',
                'species': 'rabbit',
                'entry_count': 2,
              },
          ];
        }
        if (path.endsWith('/get_show_lineup_judges')) {
          result = [
            {
              'judge_id': 'judge1',
              'judge_name': 'Shared Judge',
              'is_enabled': true,
            },
          ];
        }
        if (path.endsWith('/mutate_workspace_lineup')) mutations.add(body);
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  Future<void> open(WidgetTester tester) async {
    mutations.clear();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const SuperintendentLineupScreen(
          showId: 'sala',
          showName: 'Both shows',
          workspaceId: 'shared',
          linkedShows: {'sala': 'Sala', 'dune': 'Dune'},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one table pool and Auto Fill includes all six separate sections',
    (tester) async {
      await open(tester);
      expect(find.text('Table 1'), findsOneWidget);
      expect(find.text('Table 2'), findsNothing);
      expect(find.text('0/12'), findsOneWidget);
      await tester.tap(find.text('Auto Fill').first);
      await tester.pumpAndSettle();
      final replacement = mutations.singleWhere(
        (m) => m['p_action'] == 'replace',
      );
      final rows = List<Map<String, dynamic>>.from(
        replacement['p_payload']['rows'],
      );
      expect(rows.where((r) => r['p_is_judge_change'] == true).length, 1);
      expect(
        rows
            .where((r) => r['p_section_id'] != null)
            .map((r) => r['p_section_id'])
            .toSet(),
        {
          'sala-Open A',
          'sala-Open B',
          'sala-Youth A',
          'sala-Youth B',
          'dune-Open A',
          'dune-Youth A',
        },
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('one shared sync and one publishing control', (tester) async {
    await open(tester);
    await tester.tap(find.text('Sync Judges'));
    await tester.pumpAndSettle();
    expect(mutations.single['p_action'], 'sync');
    expect(mutations.single['p_workspace_id'], 'shared');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // Empty lineup needs confirmation before publishing.
    final publish = find.text('Publish anyway');
    if (publish.evaluate().isNotEmpty) {
      await tester.tap(publish);
      await tester.pumpAndSettle();
    }
    expect(mutations.where((m) => m['p_action'] == 'publish').length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'breed picker lists matching letters from both shows separately',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Breed').first);
      await tester.pumpAndSettle();
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(text, contains('Sala'));
      expect(text, contains('Dune'));
      expect(tester.takeException(), isNull);
    },
  );
}
