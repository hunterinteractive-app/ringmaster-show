import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/coop_cards_report_loader.dart';

void main() {
  const animal = '00000000-0000-0000-0000-000000000001';
  for (final repeat in [false, true]) {
    test(
      repeat
          ? 'a repeated coop cursor fails visibly'
          : 'a short page retains both scopes of the same animal',
      () async {
        final cursors = <String?>[];
        final client = SupabaseClient(
          'http://localhost',
          'local-test',
          httpClient: MockClient((request) async {
            final table = request.url.path.split('/').last;
            final offset =
                int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
            dynamic body;
            switch (table) {
              case 'shows':
                body = [
                  {
                    'id': 'show',
                    'name': 'Local',
                    'coop_numbering_mode': 'separate',
                  },
                ];
              case 'show_sections':
                body = [
                  for (final scope in ['open', 'youth'])
                    {
                      'id': scope,
                      'kind': scope,
                      'letter': 'A',
                      'sort_order': scope == 'open' ? 1 : 2,
                    },
                ];
              case 'report_checkin_entries':
                body = offset > 0
                    ? []
                    : [
                        for (final scope in ['open', 'youth'])
                          {
                            'entry_id': scope,
                            'section_id': scope,
                            'exhibitor_id': 'exhibitor',
                            'species': 'rabbit',
                            'tattoo': 'ONE',
                            'breed': 'Mini Rex',
                            'variety': 'Black',
                            'class_name': 'Senior',
                            'sex': 'Buck',
                            'exhibitor_label': 'Synthetic Exhibitor',
                          },
                      ];
              case 'entries':
                body = offset > 0
                    ? []
                    : [
                        for (final scope in ['open', 'youth'])
                          {'id': scope, 'animal_id': animal},
                      ];
              case 'exhibitors':
                body = offset > 0
                    ? []
                    : [
                        {
                          'id': 'exhibitor',
                          'exhibitor_number': '1',
                          'city': 'Localtown',
                          'state': 'IN',
                        },
                      ];
              case 'show_animal_coop_numbers':
                expect(
                  request.url.queryParameters.containsKey('offset'),
                  isFalse,
                );
                final cursor = request.url.queryParameters['or'];
                cursors.add(cursor);
                if (cursor == null || repeat) {
                  body = [
                    {
                      'animal_id': animal,
                      'scope': 'open',
                      'coop_number': 'MR1',
                    },
                  ];
                } else if (cursor.contains('scope.gt.open')) {
                  body = [
                    {
                      'animal_id': animal,
                      'scope': 'youth',
                      'coop_number': 'MR1',
                    },
                  ];
                } else {
                  expect(cursor, contains('scope.gt.youth'));
                  body = [];
                }
              default:
                throw StateError('Unexpected request: $table');
            }
            return http.Response(jsonEncode(body), 200, request: request);
          }),
        );
        addTearDown(client.dispose);
        final load = CoopCardsReportLoader(
          supabase: client,
        ).load(showId: 'show');
        if (repeat) {
          await expectLater(load, throwsStateError);
          expect(cursors, hasLength(2));
        } else {
          final report = await load;
          expect(report.cards, hasLength(2));
          expect(report.cards.map((c) => c.scope), ['open', 'youth']);
          expect(cursors, hasLength(3));
          expect(cursors[1], contains('animal_id.eq.$animal,scope.gt.open'));
        }
      },
    );
  }
}
