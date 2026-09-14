import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/check_in_sheet_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';

void main() {
  for (final mode in ['ordinary', 'selected', 'archive', 'invalid']) {
    test('check-in report keeps $mode wave scope', () async {
      final calls = <String>[];
      final client = SupabaseClient(
        'http://fixture.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final endpoint = request.url.path.split('/').last;
          calls.add(endpoint);
          Object result = <dynamic>[];
          switch (endpoint) {
            case 'shows':
              result = {'coop_numbering_mode': 'separate'};
            case 'exhibitors':
              result = {'display_name': 'Wave Tester'};
            case 'get_show_wave_schedule':
              result = {
                'enabled': mode != 'ordinary',
                'timezone': 'America/Chicago',
                'active_wave_id': null,
                'waves': [
                  for (var i = 1; i <= 2; i++)
                    {
                      'id': 'wave$i',
                      'wave_number': i,
                      'checkin_start_local': '2027-03-${10 + i}T08:00:00',
                      'checkin_end_local': '2027-03-${10 + i}T10:00:00',
                      'show_date': '2027-03-${10 + i}',
                      'checkout_date': '2027-03-${11 + i}',
                    },
                ],
                'breeds': [
                  {
                    'species': 'rabbit',
                    'breed_name': 'American',
                    'wave_id': 'wave1',
                  },
                  {
                    'species': 'rabbit',
                    'breed_name': 'Himalayan',
                    'wave_id': 'wave2',
                  },
                ],
              };
            case 'report_closeout_checkin_entries':
            case 'report_wave_checkin_entries':
              final params = jsonDecode(request.body);
              expect(params['p_exhibitor_id'], 'exhibitor');
              expect(params['p_section_ids'], ['open']);
              if (mode == 'selected') expect(params['p_wave_id'], 'wave2');
              if (request.url.queryParameters['offset'] == '0') {
                result = [
                  for (final breed
                      in mode == 'selected'
                          ? ['Himalayan']
                          : ['American', 'Himalayan'])
                    {
                      'species': 'rabbit',
                      'breed': breed,
                      'section_kind': 'open',
                      'class_name': 'Senior',
                      'sex': 'Buck',
                      'tattoo': breed,
                    },
                ];
              }
            case 'entries':
            case 'show_animal_coop_numbers':
              break;
            default:
              throw StateError('Unexpected request: $endpoint');
          }
          return http.Response(
            jsonEncode(result),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final request = ReportRequest(
        showId: 'show',
        reportName: 'checkin_sheet',
        finalizeRunId: 'run',
        exhibitorId: 'exhibitor',
        sectionIds: ['open'],
        waveId: mode == 'selected'
            ? 'wave2'
            : mode == 'invalid'
            ? 'bad-wave'
            : null,
      );
      final pending = CheckInSheetReportLoader(client).load(request);
      if (mode == 'invalid') {
        await expectLater(pending, throwsStateError);
        expect(calls, isNot(contains('report_closeout_checkin_entries')));
        return;
      }
      final data = await pending;
      if (mode == 'selected') {
        expect(calls, contains('report_wave_checkin_entries'));
        expect(data.entries.single['breed'], 'Himalayan');
        expect(data.sectionLabel, contains('Wave 2'));
        expect(data.waveNote, contains('Entries tab'));
      } else {
        expect(calls, contains('report_closeout_checkin_entries'));
        expect(data.entries.length, 2);
        expect(data.waveSheets.length, mode == 'archive' ? 2 : 0);
        if (mode == 'archive') {
          expect(data.waveSheets.first.entries.single['breed'], 'American');
          expect(data.waveSheets.last.entries.single['breed'], 'Himalayan');
        }
      }
    });
  }
}
