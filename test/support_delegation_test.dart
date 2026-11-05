import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/config/supabase_config.dart';
import 'package:ringmaster_show/screens/create_show_screen.dart';
import 'package:ringmaster_show/services/support_delegation.dart';
import 'package:ringmaster_show/services/support_impersonation_session.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  const actor = '00000000-0000-4000-8000-000000000001';
  const target = '00000000-0000-4000-8000-000000000002';
  Map<String, dynamic> profile(String id) => {
    'id': id,
    'aud': 'authenticated',
    'email': '$id@example.invalid',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {},
    'user_metadata': {},
  };
  testWidgets(
    'delegated Create makes club, show, and sections as the selected account',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <http.Request>[];
      bool madeClub = false;
      final broker = MockClient((req) async {
        calls.add(req);
        expect(
          req.url.path,
          startsWith('/functions/v1/support-session/proxy/rest/v1/'),
        );
        expect(req.headers['authorization'], 'Bearer actor-fixture');
        expect(req.headers['x-rm-session'], 'session-fixture');
        Object data = [];
        var code = 200;
        if (req.url.path.endsWith('/get_hosting_clubs_for_user')) {
          expect(jsonDecode(req.body)['p_user_id'], target);
          data = madeClub
              ? [
                  {'id': 'club', 'name': 'Test club', 'role': 'owner'},
                ]
              : [];
        } else if (req.url.path.endsWith(
          '/has_active_secretary_license_for_user',
        )) {
          data = false;
        } else if (req.url.path.endsWith('/clubs') && req.method == 'POST') {
          expect(jsonDecode(req.body)['created_by'], target);
          madeClub = true;
          data = {'id': 'club', 'name': 'Test club', 'is_active': true};
          code = 201;
        } else if (req.url.path.endsWith('/club_members')) {
          expect(jsonDecode(req.body)['user_id'], target);
          code = 201;
        } else if (req.url.path.endsWith('/create_show_with_license')) {
          data = 'created-show';
        } else if (req.url.path.endsWith('/show_sections')) {
          expect(
            (jsonDecode(req.body) as List).single['show_id'],
            'created-show',
          );
          data = [
            {'id': 'section', 'kind': 'open', 'letter': 'A'},
          ];
        }
        return http.Response(
          jsonEncode(data),
          code,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      });
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await Supabase.initialize(
          url: 'https://actor-fixture.invalid',
          anonKey: 'test',
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage(),
          ),
          httpClient: MockClient((req) async => http.Response('{}', 200)),
        );
        await Supabase.instance.client.auth.recoverSession(
          jsonEncode({
            'access_token': 'actor-fixture',
            'token_type': 'bearer',
            'user': profile(actor),
          }),
        );
        await RingMasterData.attach({
          'id': 'session-fixture',
          'expires_at':
              DateTime.now()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch ~/
              1000,
          'user': profile(target),
        }, transportClient: broker);
        SupportImpersonationSession.start(
          const SupportImpersonatedUser(
            userId: target,
            email: 'target@example.invalid',
            displayName: 'Target',
            exhibitorName: '',
          ),
        );
      });
      addTearDown(() async {
        SupportImpersonationSession.stop();
        await RingMasterData.detach();
        await Supabase.instance.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const CreateShowScreen()),
      );
      await tester.pumpAndSettle();
      expect(Supabase.instance.client.auth.currentUser?.id, actor);
      expect(RingMasterData.client.auth.currentUser?.id, target);
      expect(find.textContaining('Creating shows is disabled'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Show name (required)'),
        'Support show',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Location (required)'),
        'Test venue',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Hosting Club Name (required)'),
        'Test club',
      );
      final button = find.widgetWithText(FilledButton, 'Create');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        calls.any((r) => r.url.path.endsWith('/create_show_with_license')),
        isTrue,
      );
      expect(calls.any((r) => r.url.path.endsWith('/show_sections')), isTrue);
      expect(Supabase.instance.client.auth.currentUser?.id, actor);
      await tester.pump(
        const Duration(minutes: 5),
      ); // Existing timezone notice timer.
    },
  );

  test(
    'unsupported destinations and expired or stopped workspaces fail closed',
    () async {
      int sends = 0;
      SupportTransport bound(int expiry) => SupportTransport(
        project: Uri.parse(SupabaseConfig.url),
        sessionId: 'fixture',
        expiresAt: expiry,
        actorBearer: () async => 'actor',
        inner: MockClient((r) async {
          sends++;
          return http.Response('{}', 200);
        }),
      );
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 100;
      final transport = bound(expiry);
      for (final url in [
        'https://example.invalid/rest/v1/shows',
        '${SupabaseConfig.url}/auth/v1/user',
      ]) {
        await expectLater(
          transport.get(Uri.parse(url)),
          throwsA(isA<http.ClientException>()),
        );
      }
      transport.close();
      final table = Uri.parse('${SupabaseConfig.url}/rest/v1/shows');
      await expectLater(
        transport.get(table),
        throwsA(isA<http.ClientException>()),
      );
      await expectLater(
        bound(expiry - 200).get(table),
        throwsA(isA<http.ClientException>()),
      );
      expect(sends, 0);
    },
  );
}
