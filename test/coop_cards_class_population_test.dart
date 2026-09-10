import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/coop_cards_report_loader.dart';

void main() {
  test(
    'Prejunior spellings share their own population, separate from Junior',
    () async {
      final rows = [
        for (final (i, age) in [
          (1, 'PREJUNIOR BUCK'),
          (2, 'Pre-Junior Buck'),
          (3, 'Pre Junior Buck'),
          (4, 'Junior Buck'),
          (5, 'Junior Buck'),
        ])
          {
            'id': 'entry$i',
            'entry_id': 'entry$i',
            'animal_id': 'animal$i',
            'exhibitor_id': 'ex$i',
            'section_id': 'open',
            'section_kind': 'OPEN',
            'species': 'rabbit',
            'breed': 'Californian',
            'variety': '',
            'class_name': age,
            'sex': 'Buck',
            'is_fur': false,
          },
      ];
      final client = SupabaseClient(
        'http://fixture.invalid',
        'fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          final Object data;
          switch (request.url.path) {
            case '/rest/v1/shows':
              data = {
                'id': 'show',
                'name': 'Synthetic class regression',
                'coop_numbering_mode': 'separate',
              };
            case '/rest/v1/show_sections':
              data = [
                {'id': 'open', 'kind': 'open', 'letter': 'A', 'sort_order': 1},
              ];
            case '/rest/v1/rpc/report_checkin_entries':
            case '/rest/v1/entries':
              data = rows.skip(offset).toList();
            case '/rest/v1/exhibitors':
              data = [
                for (var n = 1; n <= 5; n++)
                  {'id': 'ex$n', 'exhibitor_number': '$n'},
              ].skip(offset).toList();
            case '/rest/v1/show_animal_coop_numbers':
              data = [
                for (var n = 1; n <= 5; n++)
                  {
                    'animal_id': 'animal$n',
                    'scope': 'open',
                    'coop_number': '$n',
                  },
              ].skip(offset).toList();
            default:
              throw StateError('Unexpected request: ${request.url.path}');
          }
          return http.Response(
            jsonEncode(data),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await CoopCardsReportLoader(
        supabase: client,
      ).load(showId: 'show');
      expect(result.cards, hasLength(5));
      for (final card in result.cards) {
        final preJunior = int.parse(card.coopNumber) <= 3;
        expect(card.className, preJunior ? 'Pre-Junior' : 'Junior');
        expect(card.classEntryCount, preJunior ? 3 : 2);
        expect(card.classExhibitorCount, preJunior ? 3 : 2);
      }
    },
  );
}
