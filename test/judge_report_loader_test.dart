import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/judge_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/widgets/closeout_scope_widgets.dart';

void main() {
  test('judge report reads the production show_judges schema', () async {
    var readJudges = false;
    final client = SupabaseClient(
      'https://fixture.invalid',
      'key',
      httpClient: MockClient((request) async {
        dynamic body = <dynamic>[];
        if (request.url.path.endsWith('/shows')) {
          body = {'id': 'show', 'name': 'Test show'};
        }
        if (request.url.path.endsWith('/show_judges')) {
          readJudges = true;
          final order = request.url.queryParameters['order'] ?? '';
          if (order.contains('section_id')) {
            return http.Response(
              jsonEncode({
                'message': 'column show_judges.section_id does not exist',
                'code': '42703',
              }),
              400,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final report = await JudgeReportLoader(supabase: client).load(
      ReportRequest(
        showId: 'show',
        reportName: 'judge_report',
        finalizeRunId: 'run',
        sectionIds: ['section'],
      ),
    );
    expect(readJudges, isTrue);
    expect(report.show.showName, 'Test show');
  });

  test('database schema failure explains the issue without a stack trace', () {
    final failure = closeoutFailureDisplay(
      errorCategory: 'render_error',
      metadataErrorMessage: 'The report could not be rendered.',
      taskLastError:
          'PostgrestException(message: column show_judges.section_id does not exist, code: 42703)\n#0 Stack trace',
    );
    expect(failure.message, contains('unavailable database field'));
    expect(failure.message, contains('Contact support'));
    expect(failure.message, isNot(contains('PostgrestException')));
    expect(failure.message, isNot(contains('#0')));
  });
}
