@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import 'package:ringmaster_show/main.dart' as app;
import 'package:ringmaster_show/config/legal_config.dart';
import 'package:ringmaster_show/screens/legal/legal_agreement_dialog.dart';
import 'package:ringmaster_show/screens/login_screen.dart';
import 'package:ringmaster_show/screens/show_list_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

const actor = 'aaaaaaaa-0000-4000-8000-000000000001';
Map<String, dynamic> session() {
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String segment(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return {
    'access_token':
        '${segment({'alg': 'HS256'})}.${segment({'sub': actor, 'exp': exp, 'role': 'authenticated'})}.fixture',
    'refresh_token': 'fixture',
    'token_type': 'bearer',
    'expires_at': exp,
    'expires_in': 3600,
    'user': {
      'id': actor,
      'aud': 'authenticated',
      'email': 'fixture@example.invalid',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  };
}

void main() {
  var legalReads = 0, legalWrites = 0;
  final profile = <String, dynamic>{
    'user_id': actor,
    'accepted_terms_version': LegalConfig.currentTermsVersion,
    'accepted_privacy_version': '2026-09',
  };
  setUpAll(() async {
    // Flutter's browser test runner stores JSON metadata in the fragment. The
    // real app expects its normal route fragment rather than test-runner JSON.
    web.window.history.replaceState(
      null,
      '',
      '${web.window.location.pathname}${web.window.location.search}',
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        http.Response response(Object? body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        final path = request.url.path;
        if (path == '/auth/v1/token') return response(session());
        if (path.endsWith('/household_access')) {
          return response({'households': [], 'invitations': []});
        }
        if (path.endsWith('/claim_pending_licenses')) return response(null);
        if (path.endsWith('/claim-or-import-exhibitor')) {
          return response({'status': 'already_exists'});
        }
        if (path.endsWith('/profiles')) {
          if (request.method == 'POST') {
            legalWrites++;
            profile.addAll(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            return response(profile);
          }
          if ((request.url.queryParameters['select'] ?? '').contains(
            'accepted_terms',
          )) {
            legalReads++;
          }
          return response([profile]);
        }
        if (path.endsWith('/exhibitors')) {
          return response([
            {
              'id': 'fixture-exhibitor',
              'type': 'adult',
              'display_name': 'Fixture Exhibitor',
              'is_active': true,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]);
        }
        if (path.contains('/rpc/')) return response(false);
        return response([]);
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets(
    'root sign-in opens one agreement and token refresh preserves its state',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const app.Root()),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<LoginScreen>(find.byType(LoginScreen)).rootManaged,
        true,
      );
      await Supabase.instance.client.auth.recoverSession(jsonEncode(session()));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ShowListScreen), findsOneWidget);
      expect(find.byType(LegalAgreementDialog), findsOneWidget);
      expect(legalReads, 1);
      final listState = tester.state(find.byType(ShowListScreen));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump(const Duration(milliseconds: 200));
      await Supabase.instance.client.auth.refreshSession();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        identical(tester.state(find.byType(ShowListScreen)), listState),
        true,
      );
      expect(find.byType(LegalAgreementDialog), findsOneWidget);
      expect(legalReads, 1);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );
      await tester.tap(find.text('Agree & Continue'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LegalAgreementDialog), findsNothing);
      expect(legalWrites, 1);
      expect(
        profile['accepted_privacy_version'],
        LegalConfig.currentPrivacyVersion,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
