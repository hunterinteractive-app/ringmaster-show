import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/best_display_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/check_in_sheet_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/entered_exhibitors_contact_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/payback_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';

ReportRequest get _request => ReportRequest(
  showId: 'show',
  reportName: 'test',
  finalizeRunId: 'run',
  sectionIds: ['open'],
  exhibitorId: 'exhibitor',
  species: 'rabbit',
);
String _id(int n) => '94000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

SupabaseClient _client(Future<http.Response> Function(http.Request) handle) {
  final client = SupabaseClient(
    'http://fixture.invalid',
    'fixture',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handle),
  );
  addTearDown(client.dispose);
  return client;
}

http.Response _json(http.Request request, Object data) => http.Response(
  jsonEncode(data),
  200,
  request: request,
  headers: {'content-type': 'application/json'},
);
http.Response _page(
  http.Request request,
  List<Map<String, dynamic>> rows, {
  int cap = 37,
}) {
  final offset = int.parse(request.url.queryParameters['offset']!);
  return _json(request, rows.skip(offset).take(cap).toList());
}

List<String> _ids(http.Request request, String column) => request
    .url
    .queryParameters[column]!
    .substring(4)
    .replaceAll(')', '')
    .replaceAll('"', '')
    .split(',');

void main() {
  test(
    'contact report includes 2528 exhibitors and deduplicates repeated entries across pages',
    () async {
      final rows = List.generate(
        5056,
        (i) => <String, dynamic>{
          'exhibitor_id': 'ex${i % 2528}',
          'exhibitors': {
            'display_name': 'Exhibitor ${i % 2528}',
            'email': '$i@example.invalid',
          },
        },
      );
      final client = _client((request) async {
        expect(request.url.queryParameters['show_id'], 'eq.show');
        expect(_ids(request, 'section_id'), ['open']);
        expect(request.url.queryParameters['order'], 'id.asc.nullslast');
        return _page(request, rows);
      });
      final data = await EnteredExhibitorsContactReportLoader(
        client,
      ).load(_request);
      expect(data.rows.map((r) => r.exhibitorName).toSet(), {
        for (var i = 0; i < 2528; i++) 'Exhibitor $i',
      });
      expect(data.rows.length, 2528);
    },
  );

  test(
    'check-in retains all 501 entries and coops within gateway URL limits',
    () async {
      final entries = List.generate(
        501,
        (i) => <String, dynamic>{
          'entry_id': _id(i),
          'animal_id': _id(i),
          'section_kind': 'open',
          'species': 'rabbit',
          'tattoo': '$i',
          'breed_name': 'Mini Rex',
        },
      );
      final client = _client((request) async {
        expect(request.url.toString().length, lessThan(8000));
        switch (request.url.path.split('/').last) {
          case 'shows':
            return _json(request, {'coop_numbering_mode': 'separate'});
          case 'exhibitors':
            return _json(request, {'display_name': 'Test Exhibitor'});
          case 'report_closeout_checkin_entries':
            expect(jsonDecode(request.body)['p_section_ids'], ['open']);
            return _page(request, entries);
          case 'entries':
            final ids = _ids(request, 'id');
            expect(ids.length, lessThanOrEqualTo(100));
            return _page(
              request,
              ids
                  .map(
                    (id) => <String, dynamic>{
                      'id': id,
                      'animal_id': id,
                      'is_fur': false,
                      'class_name': 'Senior Buck',
                    },
                  )
                  .toList(),
            );
          case 'show_animal_coop_numbers':
            expect(request.url.queryParameters['show_id'], 'eq.show');
            final ids = _ids(request, 'animal_id');
            expect(ids.length, lessThanOrEqualTo(100));
            return _page(
              request,
              ids
                  .map(
                    (id) => <String, dynamic>{
                      'animal_id': id,
                      'scope': 'open',
                      'coop_number': '${int.parse(id.split('-').last) + 1}',
                    },
                  )
                  .toList(),
            );
          default:
            throw StateError('Unexpected request ${request.url}');
        }
      });
      final data = await CheckInSheetReportLoader(client).load(_request);
      expect(data.entries.length, 501);
      expect(data.entries.map((r) => r['entry_id']).toSet(), {
        for (var i = 0; i < 501; i++) _id(i),
      });
      for (final row in data.entries) {
        expect(row['coop_number'], '${int.parse(row['tattoo']) + 1}');
      }
    },
  );

  test(
    'payback reconciles all 2501 amounts and retries after a later-page failure',
    () async {
      var failLaterPage = true;
      final rows = List.generate(
        2501,
        (i) => <String, dynamic>{
          'entry_id': _id(i),
          'section_id': 'open',
          'exhibitor_id': 'ex$i',
          'exhibitor_name': 'Exhibitor $i',
          'amount_cents': 125,
        },
      );
      final client = _client((request) async {
        if (request.url.path.endsWith('/shows')) {
          return _json(request, {'name': 'Local show'});
        }
        expect(request.url.path, endsWith('/rpc/report_payback_rows'));
        expect(jsonDecode(request.body)['p_section_id'], 'open');
        if (failLaterPage && request.url.queryParameters['offset'] != '0') {
          return http.Response(
            '{"message":"Interrupted page","code":"XX000"}',
            500,
            headers: {'content-type': 'application/json'},
          );
        }
        return _page(request, rows, cap: 1000);
      });
      final loader = PaybackReportLoader(supabase: client);
      await expectLater(
        loader.loadRequest(_request),
        throwsA(isA<PaybackSectionBatchLoadException>()),
      );
      failLaterPage = false;
      final data = await loader.loadRequest(_request);
      expect(data.totalExhibitors, 2501);
      expect(data.grandTotalCents, 312625);
      expect(
        data.exhibitors.expand((e) => e.rows).map((r) => r.entryId).toSet(),
        {for (var i = 0; i < 2501; i++) _id(i)},
      );
    },
  );

  test(
    'best-display standings span server pages without omitting exhibitors',
    () async {
      final rows = List.generate(
        2528,
        (i) => <String, dynamic>{
          'exhibitor_id': 'ex$i',
          'exhibitor_name': 'Exhibitor $i',
          'section_id': 'open',
          'scope': 'OPEN',
          'show_letter': 'A',
          'species': 'rabbit',
          'rank': i + 1,
        },
      );
      final client = _client((request) async {
        switch (request.url.path.split('/').last) {
          case 'shows':
            return _json(request, {'id': 'show', 'name': 'Local show'});
          case 'report_best_display_standings':
            return _page(request, rows);
          case 'report_best_display_entry_rows':
            return _page(request, []);
          default:
            throw StateError('Unexpected request ${request.url}');
        }
      });
      final data = await BestDisplayReportLoader(
        supabase: client,
      ).load(_request);
      expect(data.totalStandingRows, 2528);
      expect(data.allRows.map((r) => r.exhibitorId).toSet(), {
        for (var i = 0; i < 2528; i++) 'ex$i',
      });
    },
  );
}
