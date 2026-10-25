import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/config/legal_config.dart';
import 'package:ringmaster_show/services/legal_acceptance_service.dart';

const buyer = 'aaaaaaaa-0000-4000-8000-000000000001';
const other = 'aaaaaaaa-0000-4000-8000-000000000002';

Future<void> login(SupabaseClient client, String id) async {
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String segment(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  await client.auth.recoverSession(
    jsonEncode({
      'access_token':
          '${segment({'alg': 'HS256'})}.${segment({'sub': id, 'exp': exp, 'role': 'authenticated'})}.fixture',
      'refresh_token': 'fixture',
      'token_type': 'bearer',
      'expires_at': exp,
      'user': {
        'id': id,
        'aud': 'authenticated',
        'email': 'fixture@example.invalid',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': {},
        'user_metadata': {},
      },
    }),
  );
}

class Harness {
  Harness({bool accepted = false}) {
    row = {
      'user_id': buyer,
      'display_name': 'Keep my name',
      'accepted_terms_version': LegalConfig.currentTermsVersion,
      'accepted_privacy_version': accepted
          ? LegalConfig.currentPrivacyVersion
          : '2026-09',
    };
    client = SupabaseClient(
      'http://fixture.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        http.Response response(Object body, [int status = 200]) =>
            http.Response(
              jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
              request: request,
            );
        expect(request.url.path, '/rest/v1/profiles');
        if (request.method == 'GET') {
          reads++;
          expect(request.url.queryParameters['user_id'], 'eq.$buyer');
          if (holdRead != null) await holdRead!.future;
          if (failRead) {
            return response({'code': '57014', 'message': 'unavailable'}, 503);
          }
          return response([row]);
        }
        writes++;
        final data = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        expect(data['user_id'], buyer);
        expect(data.containsKey('display_name'), false);
        expect(data.containsKey('email'), false);
        if (failWrite) {
          return response({'code': '42501', 'message': 'cannot save'}, 403);
        }
        if (commitWrite) row.addAll(data);
        if (loseResponse) throw http.ClientException('Response lost');
        return response(row);
      }),
    );
    service = LegalAcceptanceService(client, buyer);
  }
  late final SupabaseClient client;
  late final LegalAcceptanceService service;
  late Map<String, dynamic> row;
  bool failRead = false,
      failWrite = false,
      loseResponse = false,
      commitWrite = true;
  Completer<void>? holdRead;
  int reads = 0, writes = 0;
  Future<void> ready() => login(client, buyer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'saved acceptance survives a new navigation check without another prompt',
    () async {
      final h = Harness();
      await h.ready();
      addTearDown(h.client.dispose);
      var prompts = 0;
      expect(
        await h.service.ensureAccepted(
          prompt: (save) async {
            prompts++;
            await save();
            return true;
          },
        ),
        true,
      );
      final reads = h.reads;
      expect(
        await LegalAcceptanceService(h.client, buyer).ensureAccepted(
          prompt: (_) async {
            prompts++;
            return false;
          },
        ),
        true,
      );
      expect(prompts, 1);
      expect(h.writes, 1);
      expect(h.reads, greaterThan(reads));
      expect(h.row['display_name'], 'Keep my name');
    },
  );
  test(
    'concurrent startup and navigation checks share one agreement prompt',
    () async {
      final h = Harness();
      await h.ready();
      addTearDown(h.client.dispose);
      final proceed = Completer<void>();
      var prompts = 0;
      Future<bool?> prompt(Future<void> Function() save) async {
        prompts++;
        await proceed.future;
        await save();
        return true;
      }

      final a = h.service.ensureAccepted(prompt: prompt);
      final b = LegalAcceptanceService(
        h.client,
        buyer,
      ).ensureAccepted(prompt: prompt);
      proceed.complete();
      expect(await Future.wait([a, b]), [true, true]);
      expect(prompts, 1);
      expect(h.writes, 1);
    },
  );
  test('failed save never claims acceptance and can be retried', () async {
    final h = Harness()..failWrite = true;
    await h.ready();
    addTearDown(h.client.dispose);
    await expectLater(h.service.save(), throwsA(isA<PostgrestException>()));
    expect(h.row['accepted_privacy_version'], '2026-09');
    h.failWrite = false;
    await h.service.save();
    expect(LegalAcceptanceService.isCurrent(h.row), true);
  });
  test('lost save response is recovered from the server receipt', () async {
    final h = Harness()..loseResponse = true;
    await h.ready();
    addTearDown(h.client.dispose);
    await h.service.save();
    expect(h.writes, 1);
    expect(LegalAcceptanceService.isCurrent(h.row), true);
  });
  test(
    'a zero-effect or filtered write is not treated as a saved receipt',
    () async {
      final h = Harness()..commitWrite = false;
      await h.ready();
      addTearDown(h.client.dispose);
      await expectLater(h.service.save(), throwsStateError);
      expect(LegalAcceptanceService.isCurrent(h.row), false);
    },
  );
  test('a failed status read does not ask for agreement again', () async {
    final h = Harness(accepted: true)..failRead = true;
    await h.ready();
    addTearDown(h.client.dispose);
    var prompts = 0;
    await expectLater(
      h.service.ensureAccepted(
        prompt: (_) async {
          prompts++;
          return true;
        },
      ),
      throwsA(isA<PostgrestException>()),
    );
    expect(prompts, 0);
    expect(h.writes, 0);
  });
  test(
    'changing accounts during a read cannot accept for either account',
    () async {
      final h = Harness()..holdRead = Completer<void>();
      await h.ready();
      addTearDown(h.client.dispose);
      var prompts = 0;
      final check = h.service.ensureAccepted(
        prompt: (_) async {
          prompts++;
          return true;
        },
      );
      final rejected = expectLater(check, throwsStateError);
      await login(h.client, other);
      h.holdRead!.complete();
      await rejected;
      expect(prompts, 0);
      expect(h.writes, 0);
    },
  );
  test('older or missing acceptance still requires the current policy', () {
    expect(
      LegalAcceptanceService.isCurrent({
        'accepted_terms_version': '2026-05',
        'accepted_privacy_version': LegalConfig.currentPrivacyVersion,
      }),
      false,
    );
    expect(LegalAcceptanceService.isCurrent(null), false);
  });
}
