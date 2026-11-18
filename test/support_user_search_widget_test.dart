// flutter test --platform chrome test/support_user_search_widget_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/super_admin/superadmin_home_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final queries = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/search_support_users');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        queries.add(body);
        final q = body['p_query'];
        return http.Response(
          jsonEncode(
            q == '' || q == 'missing'
                ? []
                : [
                    {
                      'user_id': 'target',
                      'email': 'fixture-kim@example.invalid',
                      'display_name': '',
                      'exhibitor_name': 'Joseph Wyatt, Cody Kapacziewski',
                    },
                  ],
          ),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final width in [430.0, 1400.0]) {
    testWidgets('support search uses linked account lookup at width $width', (
      tester,
    ) async {
      queries.clear();
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SupportImpersonationScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(queries.single, {'p_query': '', 'p_limit': 100});
      final field = find.byType(TextField);
      for (final query in [
        'fixture-kim@example.invalid',
        'Joseph Wyatt, Cody Kapacziewski',
        'Kapacziewski Joseph',
      ]) {
        await tester.enterText(field, query);
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        expect(queries.last, {'p_query': query, 'p_limit': 200});
        expect(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text('Joseph Wyatt, Cody Kapacziewski'),
          ),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '),
        );
        expect(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text('fixture-kim@example.invalid'),
          ),
          findsOneWidget,
        );
        expect(find.text('View As'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(field, 'missing');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.text('No matching users found.'), findsOneWidget);
      expect(find.text('View As'), findsNothing);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(queries.last, {'p_query': '', 'p_limit': 100});
      expect(tester.takeException(), isNull);
    });
  }
}
