// Chrome is required because the page shell imports web payment screens.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/superintendent/linked_superintendent_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
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
        Object result = [];
        final path = request.url.path;
        if (path.endsWith('/superintendent_workspaces')) {
          result = {'id': 'shared'};
        }
        if (path.endsWith('/show_sections')) {
          final id = request.url.queryParameters['show_id']!.substring(3);
          result = [
            for (final name
                in id == 'sala'
                    ? ['Open A', 'Open B', 'Youth A', 'Youth B']
                    : ['Open A', 'Youth A'])
              {'id': '$id-$name', 'show_id': id, 'display_name': name},
          ];
        }
        if (path.endsWith('/get_show_lineup_breed_counts')) {
          final id = jsonDecode(request.body)['p_show_id'];
          result = [
            {
              'show_id': id,
              'section_id': '$id-Open A',
              'breed': 'Havana',
              'species': 'rabbit',
              'entry_count': id == 'sala' ? 5 : 7,
            },
          ];
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  testWidgets('six sections and combined counts render on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const LinkedSuperintendentScreen(
          workspaceId: 'shared',
          name: 'Miss Sala Bash & Fall Duneabash',
          shows: [
            {'id': 'sala', 'name': 'Miss Sala Bash Rabbit Show'},
            {'id': 'dune', 'name': 'Fall Duneabash Show'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Both shows · 6 sections'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('All breeds — 12 total'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('All breeds — 12 total'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
