import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/manual_judging_reader.dart';

void main() {
  test(
    'selected breed keeps scope, awards and scratches through a lower API cap',
    () async {
      final expected = [
        for (var i = 0; i < 2528; i++)
          {
            'entry_id': i.toString().padLeft(5, '0'),
            'section_id': 'open',
            'breed': 'American',
            'species': i.isEven ? 'rabbit' : 'cavy',
            'scratched_at': i == 0 ? '2026-09-12' : null,
            '_awards': i == 1 ? ['BOB'] : <String>[],
          },
      ];
      final client = SupabaseClient(
        'http://fixture.invalid',
        'key',
        httpClient: MockClient((request) async {
          final p = jsonDecode(request.body) as Map;
          expect(p['p_breed'], 'American');
          expect(p['p_section_id'], 'open');
          expect(p['p_page_size'], 250);
          final after = p['p_after_entry_id'] as String?;
          final rows = expected
              .where(
                (r) =>
                    after == null ||
                    (r['entry_id'] as String).compareTo(after) > 0,
              )
              .take(137)
              .toList();
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      expect(
        await loadManualJudgingRows(
          client,
          showId: 'show',
          sectionId: 'open',
          breed: 'American',
        ),
        expected,
      );
    },
  );
  test(
    'exact entry lookup remains bounded and whole-section reads are explicit',
    () async {
      final requests = <Map>[];
      final client = SupabaseClient(
        'http://fixture.invalid',
        'key',
        httpClient: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map);
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await loadManualJudgingRows(client, showId: 'show', entryId: 'target');
      expect(requests.single['p_entry_ids'], ['target']);
      await loadManualJudgingRows(client, showId: 'show', sectionId: 'youth');
      expect(requests.last['p_section_id'], 'youth');
      expect(requests.last['p_breed'], isNull);
    },
  );
  test('breed index failure is visible, not an empty section', () async {
    final client = SupabaseClient(
      'http://fixture.invalid',
      'key',
      httpClient: MockClient(
        (request) async => http.Response(
          '{"code":"42501","message":"denied"}',
          403,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      loadJudgingBreedIndex(client, showId: 'show', sectionId: 'open'),
      throwsA(isA<PostgrestException>()),
    );
  });
}
