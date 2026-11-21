// Opt-in read-only full-show report rehearsal; never calls a live service.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/unpaid_balances_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/unpaid_balances_report_pdf.dart';

void main() {
  final input = Platform.environment['UNPAID_REPORT_FIXTURE'];
  test(
    'full unpaid PDF reconciles every exhibitor and exhausts pagination',
    () async {
      final fixture = jsonDecode(File(input!).readAsStringSync()) as Map;
      final show = Map<String, dynamic>.from(fixture['show']);
      final expected = Map<String, dynamic>.from(fixture['expected']);
      var reads = 0;
      final client = SupabaseClient(
        'https://fixture.invalid',
        'fixture',
        httpClient: MockClient((request) async {
          final endpoint = request.url.pathSegments.last;
          dynamic response;
          if (endpoint == 'shows') {
            response = show;
          } else if (endpoint == 'show_sections') {
            response = fixture['sections'];
          } else if (endpoint == 'report_show_exhibitor_balances_scoped') {
            expect(jsonDecode(request.body)['p_show_id'], show['id']);
            final rows = fixture['balances'] as List;
            response = rows
                .skip(int.parse(request.url.queryParameters['offset'] ?? '0'))
                .take(int.parse(request.url.queryParameters['limit'] ?? '1000'))
                .toList();
            reads++;
          } else {
            fail('Unexpected report request: $endpoint');
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
      final request = ReportRequest(
        showId: show['id'],
        reportName: 'Unpaid Exhibitor Balances',
        finalizeRunId: '',
      );
      final data = await UnpaidBalancesReportLoader(
        CloseoutRepository(client),
      ).load(request);
      expect(data.totalExhibitors, expected.length);
      expect(
        data.rows.map((r) => r.exhibitorId).toSet(),
        expected.keys.toSet(),
      );
      for (final row in data.rows) {
        final fees = expected[row.exhibitorId] as List;
        expect(row.entryCount, fees[0]);
        expect(row.furCount, fees[1]);
        expect((row.totalDue * 100).round(), fees[2]);
      }
      expect(reads, greaterThanOrEqualTo(2));
      final builder = await UnpaidBalancesReportPdfBuilder.fromAssets(
        FileSystemReportAssetLoader(Directory('assets')),
      );
      final result = await builder.buildFile(data, request);
      await File(
        Platform.environment['UNPAID_REPORT_OUTPUT']!,
      ).writeAsBytes(result.bytes);
      stdout.writeln(
        'Verified ${data.totalExhibitors} exhibitors, ${data.totalEntries} class, ${data.totalFurEntries} fur, total \$${data.grandTotalDue.toStringAsFixed(2)}.',
      );
    },
    skip: input == null,
  );
}
