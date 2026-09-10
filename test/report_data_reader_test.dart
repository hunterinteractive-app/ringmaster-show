import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/report_data_reader.dart';

void main() {
  for (final length in [0, 999, 1000, 1001, 2501]) {
    test(
      'reads $length rows even when the server caps each page at 37',
      () async {
        final offsets = <int>[];
        final rows = await readAllReportPages((from, to) async {
          offsets.add(from);
          return List.generate(min(37, length - from), (i) => {'id': from + i});
        });
        expect(
          rows.map((row) => row['id']),
          orderedEquals(List.generate(length, (i) => i)),
        );
        expect(offsets.last, length);
      },
    );
  }

  test(
    'propagates a later page failure instead of returning partial rows',
    () async {
      await expectLater(
        readAllReportPages((from, to) async {
          if (from > 0) throw StateError('Connection interrupted');
          return [
            {'id': 1},
          ];
        }),
        throwsStateError,
      );
    },
  );

  test(
    'splits 501 UUIDs, removes duplicate inputs, and honors a lower row cap',
    () async {
      final ids = List.generate(
        501,
        (i) => '94000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
      );
      var requests = 0;
      final client = SupabaseClient(
        'http://fixture.invalid',
        'fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests++;
          expect(request.url.toString().length, lessThan(8000));
          expect(request.url.queryParameters['order'], 'id.asc.nullslast');
          final selected = _inIds(request, 'id');
          expect(selected.length, lessThanOrEqualTo(100));
          final offset = int.parse(request.url.queryParameters['offset']!);
          return _json(
            request,
            selected.skip(offset).take(17).map((id) => {'id': id}).toList(),
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await loadReportRowsByIds(
        client,
        table: 'entries',
        columns: 'id',
        ids: [...ids, ids.first, '', '  ${ids.first}  '],
      );
      expect(rows.map((row) => row['id']), orderedEquals(ids));
      expect(requests, greaterThan(6));
    },
  );

  test(
    'pages one-to-many awards even when the ID batch itself is small',
    () async {
      final client = SupabaseClient(
        'http://fixture.invalid',
        'fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(_inIds(request, 'entry_id'), ['entry-1']);
          final offset = int.parse(request.url.queryParameters['offset']!);
          return _json(
            request,
            List.generate(
              1201,
              (i) => {'id': i, 'entry_id': 'entry-1'},
            ).skip(offset).take(1000).toList(),
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await loadReportRowsByIds(
        client,
        table: 'entry_awards',
        columns: 'id,entry_id',
        ids: ['entry-1'],
        idColumn: 'entry_id',
      );
      expect(rows.length, 1201);
      expect(rows.map((row) => row['id']).toSet().length, 1201);
    },
  );
}

List<String> _inIds(http.Request request, String column) => request
    .url
    .queryParameters[column]!
    .substring(4)
    .replaceAll(')', '')
    .replaceAll('"', '')
    .split(',');
http.Response _json(http.Request request, Object value) => http.Response(
  jsonEncode(value),
  200,
  request: request,
  headers: {'content-type': 'application/json'},
);
