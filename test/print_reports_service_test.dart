import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/print_packs/print_reports_service.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final request = ReportRequest(
    showId: 'show',
    showName: 'Sample Show',
    sectionIds: ['open-a', 'youth-b'],
    reportName: '',
    finalizeRunId: 'operational',
  );
  final balances = <Map<String, dynamic>>[
    {
      'source': 'entries',
      'exhibitor_id': 'exh',
      'exhibitor_name': 'Sample Exhibitor',
      'paid_online_cents': 500,
      'paid_manual_cents': 200,
      'refunded_cents': 100,
      'balance_due_cents': 400,
      'currency': 'USD',
      'entry_count': 2,
    },
  ];
  final entries = [
    {
      'id': 'entry',
      'exhibitor_id': 'exh',
      'exhibitors': {
        'id': 'exh',
        'display_name': 'Sample Exhibitor',
        'first_name': 'Sample',
        'last_name': 'Exhibitor',
        'exhibitor_number': 123,
        'address_line1': '1 Main St',
        'city': 'Sample City',
        'state': 'IN',
        'zip': '12345',
      },
    },
  ];
  final addons = [
    {
      'id': 'extra',
      'kind': 'extra',
      'name': 'Parking pass',
      'exhibitor_id': 'exh',
      'exhibitor_name': 'Sample Exhibitor',
      'quantity': 1,
      'unit_price_cents': 500,
      'payment_status': 'paid',
    },
    {
      'id': 'contest',
      'kind': 'contest',
      'name': 'Showmanship',
      'exhibitor_id': 'exh',
      'exhibitor_name': 'Sample Exhibitor',
      'quantity': 1,
      'unit_price_cents': 500,
      'payment_status': 'paid',
    },
  ];
  SupabaseClient client({bool failBalances = false, bool empty = false}) =>
      SupabaseClient(
        'http://fixture.invalid',
        'test',
        httpClient: MockClient((r) async {
          Object body = [];
          final path = r.url.path;
          if (path.endsWith('/shows')) {
            body = {
              'id': 'show',
              'name': 'Sample Show',
              'start_date': '2026-11-11',
            };
          } else if (path.endsWith('/show_sections')) {
            body = [
              {'id': 'open-a'},
              {'id': 'youth-b'},
            ];
          } else if (path.endsWith('/report_show_exhibitor_balances_scoped')) {
            expect(jsonDecode(r.body)['p_show_id'], 'show');
            expect(jsonDecode(r.body)['p_section_ids'], ['open-a', 'youth-b']);
            if (failBalances) {
              return http.Response(
                '{"message":"denied","code":"42501"}',
                403,
                request: r,
                headers: {'content-type': 'application/json'},
              );
            }
            body = balances;
          } else if (path.endsWith('/entries')) {
            expect(r.url.queryParameters['show_id'], 'eq.show');
            expect(
              r.url.queryParameters['section_id'],
              'in.("open-a","youth-b")',
            );
            body = entries;
          } else if (path.endsWith('/get_show_addon_registrations')) {
            expect(jsonDecode(r.body)['p_show_id'], 'show');
            body = addons;
          } else {
            fail('Unexpected data request: $path');
          }
          if (empty ||
              (int.tryParse(r.url.queryParameters['offset'] ?? '0') ?? 0) > 0) {
            body = [];
          }
          return http.Response(
            jsonEncode(body),
            200,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  test(
    'partial payments appear in both; cart-only and refunded balances do not create false reports',
    () {
      expect(balancePrintReports(balances), {
        PrintReport.paid,
        PrintReport.unpaid,
      });
      expect(
        balancePrintReports([
          {'source': 'cart', 'balance_due_cents': 200},
          {
            'source': 'entries',
            'paid_online_cents': 100,
            'refunded_cents': 100,
            'balance_due_cents': 0,
          },
        ]),
        isEmpty,
      );
    },
  );
  test('all six reports use scoped data and generate fresh PDFs', () async {
    final c = client();
    addTearDown(c.dispose);
    final service = PrintReportsService(c);
    final available = await service.available(request);
    expect(available.reports, PrintReport.values.toSet());
    expect(available.errors, isEmpty);
    for (final report in PrintReport.values) {
      final file = await service.build(report, request);
      expect(file.mimeType, 'application/pdf');
      expect(ascii.decode(file.bytes.take(5).toList()), '%PDF-');
      expect(file.bytes.length, greaterThan(1000));
    }
  });
  test('empty show hides every report', () async {
    final c = client(empty: true);
    addTearDown(c.dispose);
    final available = await PrintReportsService(c).available(request);
    expect(available.reports, isEmpty);
    expect(available.errors, isEmpty);
  });
  test(
    'payment failure does not hide available exhibitor and add-on reports',
    () async {
      final c = client(failBalances: true);
      addTearDown(c.dispose);
      final available = await PrintReportsService(c).available(request);
      expect(available.reports, {
        PrintReport.labels,
        PrintReport.numbers,
        PrintReport.addons,
        PrintReport.contests,
      });
      expect(available.errors, ['Payment reports']);
    },
  );
}
