import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/payback_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/csv/builders/other_reports_csv.dart';

void main() {
  for (final scoped in [false, true]) {
    test(
      'loads exhibitor emails for ${scoped ? 'scoped' : 'ordinary'} payback reports and CSV',
      () async {
        final contactRequests = <http.Request>[];
        final client = SupabaseClient(
          'http://fixture.invalid',
          'test',
          httpClient: MockClient((request) async {
            Object response = [];
            final firstPage =
                (request.url.queryParameters['offset'] ?? '0') == '0';
            if (request.url.path.endsWith('/shows')) {
              response = {'id': 'show1', 'name': 'Payback Show'};
            } else if (request.url.path.endsWith('/report_payback_rows') &&
                firstPage) {
              response = [
                for (final (entryId, exhibitorId, amount) in [
                  ('entry1', 'ex1', 1000),
                  ('entry2', 'ex1', 250),
                  ('entry3', 'ex2', 500),
                  ('entry4', 'excluded', 0),
                ])
                  {
                    'entry_id': entryId,
                    'exhibitor_id': exhibitorId,
                    'exhibitor_name': exhibitorId,
                    'exhibitor_number': '1096',
                    'amount_cents': amount,
                    'section_label': 'Open A',
                    'breed_name': 'Dutch',
                    'source_type': 'class_placement',
                  },
              ];
            } else if (request.url.path.endsWith('/exhibitors')) {
              contactRequests.add(request);
              if (firstPage) {
                response = [
                  {'id': 'ex1', 'email': '  exhibitor@example.com  '},
                  {'id': 'ex2', 'email': null},
                ];
              }
            }
            return http.Response(
              jsonEncode(response),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        final loader = PaybackReportLoader(supabase: client);
        final data = scoped
            ? await loader.loadRequest(
                ReportRequest(
                  showId: 'show1',
                  reportName: 'payback_report',
                  finalizeRunId: 'run1',
                  sectionIds: ['s1'],
                ),
              )
            : await loader.load(showId: 'show1', sectionId: 's1');
        expect(data.exhibitors.map((ex) => ex.email), [
          'exhibitor@example.com',
          '',
        ]);
        expect(data.exhibitors.first.totalCents, 1250);
        expect(data.grandTotalCents, 1750);
        expect(contactRequests.length, 2); // one batch, read to exhaustion
        expect(contactRequests.first.url.queryParameters['select'], 'id,email');
        expect(
          contactRequests.first.url.queryParameters['id']?.replaceAll('"', ''),
          'in.(ex1,ex2)',
        );
        final csv = OtherReportsCsvBuilder().build(data);
        final emailColumn = csv.headers.indexOf('Email');
        expect(emailColumn, greaterThanOrEqualTo(0));
        expect(csv.rows.map((row) => row[emailColumn]), [
          'exhibitor@example.com',
          'exhibitor@example.com',
          '',
        ]);
      },
    );
  }

  test('large payback show loads in bounded exact-section batches', () async {
    const sectionIds = <String>[
      'open-a',
      'open-b',
      'open-c',
      'youth-a',
      'youth-b',
      'youth-c',
    ];
    const rowsPerSection = 2500;
    final requestedSections = <String>[];
    final timingEvents = <Map<String, Object?>>[];
    var activeRequests = 0;
    var peakActiveRequests = 0;

    final loader = PaybackSectionBatchLoader(
      fetchRows: (showId, sectionId) async {
        expect(showId, 'large-show');
        requestedSections.add(sectionId);
        activeRequests++;
        peakActiveRequests = activeRequests > peakActiveRequests
            ? activeRequests
            : peakActiveRequests;
        await Future<void>.delayed(Duration.zero);
        activeRequests--;
        return List<Map<String, dynamic>>.generate(
          rowsPerSection,
          (index) => <String, dynamic>{
            'entry_id': '$sectionId-entry-$index',
            'section_id': sectionId,
          },
        );
      },
      timingSink: timingEvents.add,
    );

    final rows = await loader.load(
      showId: 'large-show',
      sectionIds: sectionIds,
    );

    expect(requestedSections, sectionIds);
    expect(peakActiveRequests, 1);
    expect(rows, hasLength(sectionIds.length * rowsPerSection));
    expect(timingEvents, hasLength(sectionIds.length));
    for (var index = 0; index < sectionIds.length; index++) {
      expect(timingEvents[index]['event'], 'payback_section_loaded');
      expect(timingEvents[index]['section_id'], sectionIds[index]);
      expect(timingEvents[index]['row_count'], rowsPerSection);
      expect(timingEvents[index]['duration_ms'], isA<int>());
    }
  });

  test(
    'failed section is identified while later sections still load',
    () async {
      final requestedSections = <String>[];
      final loader = PaybackSectionBatchLoader(
        fetchRows: (showId, sectionId) async {
          requestedSections.add(sectionId);
          if (sectionId == 'open-b') {
            throw StateError('statement timeout');
          }
          return <Map<String, dynamic>>[];
        },
      );

      await expectLater(
        loader.load(
          showId: 'pandemic-palooza-spring-2026',
          sectionIds: const ['open-a', 'open-b', 'open-c'],
        ),
        throwsA(
          isA<PaybackSectionBatchLoadException>().having(
            (error) => error.failures.single.toString(),
            'failure details',
            contains(
              'report_payback_rows failed for '
              'show=pandemic-palooza-spring-2026 section=open-b',
            ),
          ),
        ),
      );

      expect(requestedSections, ['open-a', 'open-b', 'open-c']);
    },
  );
}
