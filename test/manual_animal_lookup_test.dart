import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/manual_animal_lookup.dart';

void main() {
  test(
    'Broken J does not reuse REW J; exact REW still reuses its ID',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          final filters = request.url.queryParameters;
          expect(filters['tattoo'], 'eq.J');
          expect(filters['breed'], 'eq.Britannia Petite');
          expect(filters['sex'], 'eq.Buck');
          expect(filters['owner_user_id'], 'eq.owner');
          expect(filters['deleted_at'], 'is.null');
          final matches = filters['variety'] == 'eq.Ruby Eyed White';
          return http.Response(
            jsonEncode(
              matches
                  ? [
                      {'id': 'rew-animal'},
                    ]
                  : [],
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      Future<Map<String, dynamic>?> lookup(String variety) =>
          findManualEntryAnimal(
            client,
            tattoo: 'j',
            breed: 'Britannia Petite',
            variety: variety,
            species: 'rabbit',
            sex: 'Buck',
            ownerUserId: 'owner',
            exhibitorId: 'exhibitor',
          );
      expect(await lookup('Broken'), isNull);
      expect((await lookup('Ruby Eyed White'))?['id'], 'rew-animal');
      await client.dispose();
    },
  );
  test(
    'show-only animal remains scoped to exhibitor and blank variety',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          expect(
            request.url.queryParameters['exhibitor_id'],
            'eq.local-exhibitor',
          );
          expect(
            request.url.queryParameters.containsKey('owner_user_id'),
            isFalse,
          );
          expect(request.url.queryParameters['variety'], 'is.null');
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      expect(
        await findManualEntryAnimal(
          client,
          tattoo: 'J',
          breed: 'Rabbit',
          variety: '',
          species: 'rabbit',
          sex: 'Doe',
          ownerUserId: '',
          exhibitorId: 'local-exhibitor',
        ),
        isNull,
      );
      await client.dispose();
    },
  );
}
