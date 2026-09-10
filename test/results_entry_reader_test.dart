import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/results_entry_reader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/report_data_reader.dart';

String id(int n) => '95400000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
void main() {
  test(
    'roster cursor remains complete as earlier exhibitors finish check-in',
    () async {
      final client = SupabaseClient(
        'http://fixture.invalid',
        'key',
        httpClient: MockClient((req) async {
          final p = jsonDecode(req.body) as Map;
          final after = p['p_after_exhibitor_id'] as String?;
          // First-page exhibitors disappear from the pending-status query while
          // staff continue checking in. An offset would skip the next two rows.
          final eligible = after == null ? [1, 2, 3, 4, 5] : [3, 4, 5];
          final rows = eligible
              .map(id)
              .where((i) => after == null || i.compareTo(after) > 0)
              .take(2)
              .map((i) => {'exhibitor_id': i})
              .toList();
          return http.Response(
            jsonEncode(rows),
            200,
            request: req,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await loadReportCursorRows(
        client,
        'get_show_checkin_roster_page',
        params: {'p_show_id': 'show', 'p_status': 'not_started'},
        cursorParameter: 'p_after_exhibitor_id',
        idColumn: 'exhibitor_id',
      );
      expect(rows.map((r) => r['exhibitor_id']), [
        for (var n = 1; n <= 5; n++) id(n),
      ]);
    },
  );

  test(
    'reads every result through a low API cap and retains the breed filter',
    () async {
      var calls = 0;
      final client = SupabaseClient(
        'http://fixture.invalid',
        'key',
        httpClient: MockClient((req) async {
          calls++;
          final p = jsonDecode(req.body) as Map;
          expect(p['p_breed'], 'Mini Rex');
          final after = p['p_after_entry_id'] as String?;
          final rows =
              [
                    for (var n = 1; n <= 2528; n++) {'entry_id': id(n)},
                  ]
                  .where(
                    (r) => after == null || r['entry_id']!.compareTo(after) > 0,
                  )
                  .take(137)
                  .toList();
          return http.Response(
            jsonEncode(rows),
            200,
            request: req,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await loadResultsEntryRows(
        client,
        params: {'p_show_id': 'show', 'p_breed': 'Mini Rex'},
      );
      expect(rows.map((r) => r['entry_id']), [
        for (var n = 1; n <= 2528; n++) id(n),
      ]);
      expect(calls, greaterThan(2));
    },
  );
  test('manual refreshes split and deduplicate exact entry IDs', () async {
    final client = SupabaseClient(
      'http://fixture.invalid',
      'key',
      httpClient: MockClient((req) async {
        final p = jsonDecode(req.body) as Map;
        final ids = List<String>.from(p['p_entry_ids'] as List)..sort();
        expect(ids.length, lessThanOrEqualTo(100));
        final after = p['p_after_entry_id'] as String?;
        return http.Response(
          jsonEncode(
            ids
                .where((id) => after == null || id.compareTo(after) > 0)
                .take(37)
                .map((id) => {'entry_id': id})
                .toList(),
          ),
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final expected = [for (var n = 1; n <= 251; n++) id(n)];
    final rows = await loadResultsEntryRows(
      client,
      params: {'p_show_id': 'show'},
      entryIds: [...expected, id(1), ''],
    );
    expect(rows.map((r) => r['entry_id']), expected);
  });
  test(
    'repeated pages fail visibly rather than looping or hiding rows',
    () async {
      final client = SupabaseClient(
        'http://fixture.invalid',
        'key',
        httpClient: MockClient(
          (req) async => http.Response(
            jsonEncode([
              {'entry_id': id(1)},
            ]),
            200,
            request: req,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        loadResultsEntryRows(client, params: {'p_show_id': 'show'}),
        throwsStateError,
      );
    },
  );
}
