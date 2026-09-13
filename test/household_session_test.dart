import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/app_session.dart';
import 'package:ringmaster_show/services/household_session.dart';

void main() {
  var shared = true;
  Future<void> login(String id) async {
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    String segment(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${segment({'alg': 'HS256'})}.${segment({'sub': id, 'exp': exp, 'role': 'authenticated'})}.fixture';
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_at': exp,
        'user': {
          'id': id,
          'aud': 'authenticated',
          'email': '$id@example.invalid',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'households': [
              {
                'owner_user_id': Supabase.instance.client.auth.currentUser!.id,
                'label': 'My household',
                'is_owner': true,
              },
              if (shared)
                {
                  'owner_user_id': 'owner',
                  'label': 'Shared household',
                  'is_owner': false,
                },
            ],
            'invitations': [],
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  test(
    'household switching never changes the authenticated permissions identity',
    () async {
      await login('member');
      await HouseholdSession.refresh();
      HouseholdSession.select('owner');
      expect(AppSession.householdOwnerUserId, 'owner');
      expect(AppSession.effectiveUserId, 'member');
      expect(Supabase.instance.client.auth.currentUser!.id, 'member');
      expect(AppSession.isSupportMode, false);
      expect(() => HouseholdSession.select('stranger'), throwsStateError);
      shared = false;
      await HouseholdSession.refresh();
      expect(AppSession.householdOwnerUserId, 'member');
      expect(() => HouseholdSession.select('owner'), throwsStateError);
      shared = true;
      await HouseholdSession.refresh();
      HouseholdSession.select('owner');
      await login('another-login');
      expect(AppSession.householdOwnerUserId, 'another-login');
      expect(AppSession.effectiveUserId, 'another-login');
    },
  );
}
