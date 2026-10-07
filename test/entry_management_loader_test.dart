import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/entry_management_loader.dart';

void main() {
  for (final cap in [1000, 237]) {
    for (final section in [null, 'open-a']) {
      test(
        'loads 12053 entries with server cap $cap and section $section',
        () async {
          final offsets = <int>[];
          final client = SupabaseClient(
            'https://fixture.invalid',
            'test',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((request) async {
              final q = request.url.queryParameters;
              expect(q['show_id'], 'eq.show');
              expect(q['section_id'], section == null ? null : 'eq.$section');
              expect(q['order'], 'created_at.asc.nullslast,id.asc.nullslast');
              final offset = int.parse(q['offset']!);
              offsets.add(offset);
              final end = min(offset + min(cap, int.parse(q['limit']!)), 12053);
              return http.Response(
                jsonEncode([
                  for (var i = offset; i < end; i++)
                    {
                      'id': '$i',
                      'exhibitor_id': i >= 12000 ? 'late-exhibitor' : 'earlier',
                    },
                ]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }),
          );
          addTearDown(client.dispose);
          final rows = await loadManagedEntries(
            client,
            showId: 'show',
            sectionId: section,
          );
          expect(rows.length, 12053);
          expect(rows.map((e) => e['id']).toSet().length, 12053);
          expect(rows.last['exhibitor_id'], 'late-exhibitor');
          expect(offsets.last, 12053);
        },
      );
    }
  }
  test(
    'a failed later page fails rather than displaying an incomplete list',
    () async {
      final client = SupabaseClient(
        'https://fixture.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final first = request.url.queryParameters['offset'] == '0';
          return http.Response(
            jsonEncode(
              first
                  ? [
                      {'id': 'one'},
                    ]
                  : {'code': '42501', 'message': 'denied'},
            ),
            first ? 200 : 403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        loadManagedEntries(client, showId: 'show'),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
