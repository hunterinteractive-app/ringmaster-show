import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/admin_shows_screen.dart';
import 'package:ringmaster_show/services/support_impersonation_session.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  var failShows = false;
  late Completer<http.Response> counts;
  http.Response response(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
    request: http.Request(
      'GET',
      Uri.parse('http://fixture.invalid/rest/v1/test'),
    ),
  );
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
        final path = request.url.path;
        if (path.endsWith('/super_admins') ||
            path.endsWith('/role_assignments')) {
          return response([]);
        }
        if (path.endsWith('/secretary_show_entry_counts')) {
          expect(jsonDecode(request.body), {'p_show_id': 'show-1'});
          return counts.future;
        }
        if (path.endsWith('/shows')) {
          if (failShows) {
            return response({'message': 'timeout', 'code': '57014'}, 500);
          }
          return response([
            {
              'id': 'show-1',
              'name': 'Accessible Show',
              'start_date': '2026-10-12',
              'end_date': '2026-10-12',
              'is_published': true,
            },
          ]);
        }
        if (path.endsWith('/support_user_access_snapshot')) {
          return response({});
        }
        return response([]);
      }),
    );
    SupportImpersonationSession.start(
      const SupportImpersonatedUser(
        userId: 'secretary',
        email: 'secretary@example.invalid',
        displayName: 'Secretary',
        exhibitorName: 'Secretary',
      ),
    );
  });
  tearDownAll(() async {
    SupportImpersonationSession.stop();
    await Supabase.instance.dispose();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const AdminShowsScreen(allowedShowIds: ['show-1']),
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('slow or failed counts never hide shows, and retry recovers', (
    tester,
  ) async {
    counts = Completer<http.Response>();
    await open(tester);
    expect(find.text('Accessible Show'), findsOneWidget);
    expect(find.text('Loading entry counts…'), findsOneWidget);
    counts.complete(
      response({'message': 'statement timeout', 'code': '57014'}, 500),
    );
    await tester.pumpAndSettle();
    expect(find.text('Accessible Show'), findsOneWidget);
    expect(
      find.text('Entry counts unavailable. You can still open this show.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Grand Total All Active Sections: 0'),
      findsNothing,
    );
    counts = Completer<http.Response>()
      ..complete(
        response([
          {
            'display_name': 'Open A',
            'kind': 'open',
            'letter': 'A',
            'sort_order': 0,
            'entry_count': 1501,
          },
        ]),
      );
    await tester.tap(find.text('Retry counts'));
    await tester.pumpAndSettle();
    expect(find.text('Open A: 1501'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('show load failure offers a readable retry', (tester) async {
    failShows = true;
    counts = Completer<http.Response>()..complete(response([]));
    await open(tester);
    expect(
      find.text('Unable to load your shows. Please try again.'),
      findsOneWidget,
    );
    failShows = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Accessible Show'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
