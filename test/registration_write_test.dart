import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/services/registration_write.dart';

void main() {
  test(
    'recovering a cart through lookup releases its draft for the next purchase',
    () async {
      final bodies = <List<dynamic>>[];
      var unavailable = true;
      final client = SupabaseClient(
        'http://localhost',
        'local-test',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('[]', 200, request: request);
          }
          bodies.add(jsonDecode(request.body) as List);
          return unavailable
              ? http.Response(
                  jsonEncode({'code': 'PGRST003', 'message': 'pool busy'}),
                  504,
                  request: request,
                )
              : http.Response(request.body, 201, request: request);
        }),
      );
      addTearDown(client.dispose);
      final draft = RegistrationWrite();
      final values = [
        {'show_id': 'show', 'user_id': 'owner', 'status': 'active'},
      ];
      await expectLater(
        draft.save(client, 'entry_carts', values, wait: (_) async {}),
        throwsA(isA<PostgrestException>()),
      );
      final priorId = bodies.first.single['id'] as String;
      expect(() => draft.acknowledgeExistingRow('unrelated'), throwsStateError);
      draft.acknowledgeExistingRow(priorId);
      unavailable = false;
      final next = await draft.save(client, 'entry_carts', values);
      expect(next.single['id'], isNot(priorId));
    },
  );
  test('a validation rejection allows correcting the form', () async {
    var reject = true;
    final client = SupabaseClient(
      'http://localhost',
      'local-test',
      httpClient: MockClient((request) async {
        return reject
            ? http.Response(
                jsonEncode({'code': '23514', 'message': 'invalid field'}),
                400,
                request: request,
              )
            : http.Response(request.body, 201, request: request);
      }),
    );
    addTearDown(client.dispose);
    final draft = RegistrationWrite();
    await expectLater(
      draft.save(client, 'animals', [
        {'tattoo': 'invalid'},
      ]),
      throwsA(isA<PostgrestException>()),
    );
    reject = false;
    final saved = await draft.save(client, 'animals', [
      {'tattoo': 'corrected'},
    ]);
    expect(saved.single['tattoo'], 'corrected');
  });

  test(
    'a committed insert with a lost response is recovered by ID without another insert',
    () async {
      final stored = <Map<String, dynamic>>[];
      var writes = 0;
      final client = SupabaseClient(
        'http://localhost',
        'local-test',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            stored.addAll(
              (jsonDecode(request.body) as List).cast<Map<String, dynamic>>(),
            );
            throw http.ClientException('Response lost after commit');
          }
          return http.Response(jsonEncode(stored), 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      final result = await RegistrationWrite().save(client, 'animals', [
        {'tattoo': 'ONE', 'owner_user_id': 'owner'},
      ], wait: (_) async {});
      expect(writes, 1);
      expect(stored, hasLength(1));
      expect(result.single['tattoo'], 'ONE');
    },
  );

  test('pool exhaustion retries the same payload and inserts once', () async {
    final bodies = <String>[];
    var stored = <Map<String, dynamic>>[];
    final client = SupabaseClient(
      'http://localhost',
      'local-test',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(stored), 200, request: request);
        }
        bodies.add(request.body);
        if (bodies.length == 1) {
          return http.Response(
            jsonEncode({'code': 'PGRST003', 'message': 'pool busy'}),
            504,
            request: request,
          );
        }
        stored = (jsonDecode(request.body) as List)
            .cast<Map<String, dynamic>>();
        return http.Response(jsonEncode(stored), 201, request: request);
      }),
    );
    addTearDown(client.dispose);
    await RegistrationWrite().save(client, 'entry_cart_items', [
      {'cart_id': 'cart', 'tattoo': 'TWO'},
    ], wait: (_) async {});
    expect(bodies, hasLength(2));
    expect(bodies.first, bodies.last);
    expect(stored, hasLength(1));
  });

  test('an exhausted form keeps its ID for a later manual retry', () async {
    final bodies = <String>[];
    var unavailable = true;
    final client = SupabaseClient(
      'http://localhost',
      'local-test',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response('[]', 200, request: request);
        }
        bodies.add(request.body);
        if (unavailable) {
          return http.Response(
            jsonEncode({'code': 'PGRST003', 'message': 'pool busy'}),
            504,
            request: request,
          );
        }
        return http.Response(request.body, 201, request: request);
      }),
    );
    addTearDown(client.dispose);
    final draft = RegistrationWrite();
    final values = [
      {'show_id': 'show', 'user_id': 'owner', 'status': 'active'},
    ];
    await expectLater(
      draft.save(client, 'entry_carts', values, wait: (_) async {}),
      throwsA(isA<PostgrestException>()),
    );
    expect(bodies, hasLength(3));
    unavailable = false;
    await draft.save(client, 'entry_carts', values, wait: (_) async {});
    expect(bodies.toSet(), hasLength(1));
  });

  test('a colliding record with different values is not overwritten', () async {
    var writes = 0;
    final client = SupabaseClient(
      'http://localhost',
      'local-test',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          writes++;
          return http.Response(
            jsonEncode({'code': '23505', 'message': 'duplicate key'}),
            409,
            request: request,
          );
        }
        return http.Response(
          jsonEncode([
            {'id': 'same', 'tattoo': 'EXISTING'},
          ]),
          200,
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      insertRegistrationRows(client, 'animals', [
        {'id': 'same', 'tattoo': 'DIFFERENT'},
      ], wait: (_) async {}),
      throwsStateError,
    );
    expect(writes, 1);
  });

  test(
    'permission failures are not retried or treated as a successful save',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'http://localhost',
        'local-test',
        httpClient: MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'not permitted'}),
            403,
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        RegistrationWrite().save(client, 'exhibitors', [
          {'display_name': 'Denied'},
        ], wait: (_) async {}),
        throwsA(isA<PostgrestException>()),
      );
      expect(requests, 1);
    },
  );
}
