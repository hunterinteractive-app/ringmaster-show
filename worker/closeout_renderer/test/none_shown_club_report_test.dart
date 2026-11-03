import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/sweepstakes_report_loader.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/club_report_shown_entries.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/sweepstakes_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart';

void main() {
  test(
    'shown count is breed scoped and includes DQ/COD with no points',
    () async {
      final client = SupabaseClient(
        'http://localhost:9999',
        'synthetic',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/show_sections')) {
            expect(request.url.queryParameters['kind'], 'eq.open');
            expect(request.url.queryParameters['letter'], 'eq.B');
            return http.Response(
              jsonEncode([
                {'id': 'section'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          expect(request.url.path, endsWith('/entries'));
          expect(request.url.queryParameters['section_id'], 'eq.section');
          if (request.url.queryParameters['offset'] != '0') {
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          const base = {
            'species': 'rabbit',
            'breed': 'Czech Frosty',
            'is_shown': true,
          };
          return http.Response(
            jsonEncode([
              {...base, 'id': 'shown'},
              {...base, 'id': 'dq', 'is_disqualified': true},
              {...base, 'id': 'cod', 'variety': 'Blue (COD)'},
              {...base, 'id': 'scratched', 'scratched_at': '2026-01-01'},
              {...base, 'id': 'not-shown', 'is_shown': false},
              {...base, 'id': 'different', 'breed': 'Silver'},
              {...base, 'id': 'cavy', 'species': 'cavy'},
              {...base, 'id': 'shown'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      expect(
        await loadShownClubReportEntryCount(
          repo: CloseoutRepository(client),
          breedName: 'czech frosty',
          showId: 'show',
          scope: 'OPEN',
          showLetter: 'B',
          species: 'rabbit',
        ),
        3,
      );
    },
  );
  for (final shown in [false, true]) {
    test(
      'empty report loaders preserve actual shown population: $shown',
      () async {
        final client = SupabaseClient(
          'http://fixture.invalid',
          'synthetic',
          httpClient: MockClient((request) async {
            Object rows = <Object>[];
            final table = request.url.pathSegments.last;
            if (table == 'show_sections')
              rows = [
                {'id': 'section'},
              ];
            if (table == 'show_sanctions')
              rows = [
                {'sanction_number': 'SANCTION'},
              ];
            if (table == 'entries' &&
                request.url.queryParameters['offset'] == '0' &&
                shown) {
              rows = [
                {
                  'id': 'a',
                  'breed': 'Czech Frosty',
                  'species': 'rabbit',
                  'is_shown': true,
                  'is_disqualified': true,
                },
              ];
            }
            return http.Response(
              jsonEncode(rows),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        final request = ReportRequest(
          showId: 'show',
          reportName: 'sweepstakes_report',
          finalizeRunId: 'run',
          breedName: 'Czech Frosty',
          species: 'rabbit',
          scope: 'OPEN',
          showLetter: 'A',
        );
        final repo = CloseoutRepository(client);
        final sweeps = await SweepstakesReportLoader(repo).load(request);
        final detail = await BreedResultsDetailReportLoader(repo).load(request);
        expect(sweeps.shownEntryCount, shown ? 1 : 0);
        expect(detail.sections.single.totalAnimalsShown, shown ? 1 : 0);
        expect(detail.breedSanctionNumber, 'SANCTION');
        expect(
          breedDetailNoResultsMessage(
            detail.sections.single.totalAnimalsShown,
          ).contains('None shown'),
          !shown,
        );
      },
    );
  }
  test(
    'recorded but unshown entries do not create a populated breed report',
    () {
      expect(
        breedResultsDetailIsShownEntry({'entry_is_shown': false}),
        isFalse,
      );
      expect(
        breedResultsDetailIsShownEntry({
          'entry_is_shown': true,
          'entry_scratched_at': '2026-01-01',
        }),
        isFalse,
      );
      expect(
        breedResultsDetailIsShownEntry({
          'entry_is_shown': true,
          'entry_status': 'not shown',
        }),
        isFalse,
      );
      expect(
        breedResultsDetailIsShownEntry({
          'entry_is_shown': true,
          'entry_is_disqualified': true,
        }),
        isTrue,
      );
      expect(
        breedResultsDetailIsShownEntry({
          'entry_is_shown': true,
          'variety_name': 'Blue (COD)',
        }),
        isTrue,
      );
      expect(
        breedResultsDetailIsShownEntry({
          'entry_is_shown': false,
          'is_shown': true,
          'is_fur': true,
          'fur_placement': 1,
        }),
        isTrue,
      );
    },
  );
  test(
    'unshown entry rows return none shown before loading show awards',
    () async {
      final client = SupabaseClient(
        'http://fixture.invalid',
        'synthetic',
        httpClient: MockClient((request) async {
          final table = request.url.pathSegments.last;
          Object rows = <Object>[];
          if (table.contains('awards'))
            throw StateError('Unshown breed must not load awards');
          if (table == 'show_sections')
            rows = [
              {'id': 'section'},
            ];
          if (table == 'show_sanctions')
            rows = [
              {'sanction_number': 'SANCTION'},
            ];
          if (request.url.queryParameters['offset'] == '0') {
            if (table == 'report_results_entry_rows_for_breed_detail_dated')
              rows = [
                {
                  'entry_id': 'a',
                  'breed_name': 'Czech Frosty',
                  'species': 'rabbit',
                  'is_shown': false,
                },
              ];
            if (table == 'entries')
              rows = [
                {
                  'id': 'a',
                  'breed': 'Czech Frosty',
                  'species': 'rabbit',
                  'is_shown': false,
                  'status': 'entered',
                },
              ];
          }
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result =
          await BreedResultsDetailReportLoader(CloseoutRepository(client)).load(
            ReportRequest(
              showId: 'show',
              reportName: 'breed_results_detail_report',
              finalizeRunId: 'run',
              breedName: 'Czech Frosty',
              species: 'rabbit',
              scope: 'OPEN',
              showLetter: 'A',
            ),
          );
      expect(result.noResultsFound, isTrue);
      expect(result.sections.single.totalAnimalsShown, 0);
      expect(result.breedAwards, isEmpty);
    },
  );
  for (final species in ['rabbit', 'cavy']) {
    for (final scope in ['OPEN', 'YOUTH']) {
      for (final letter in ['A', 'B', 'C']) {
        test(
          '$species $scope $letter none-shown PDFs retain normal report details',
          () async {
            final dir = await Directory.systemTemp.createTemp(
              'none-shown-pdf-',
            );
            addTearDown(() => dir.delete(recursive: true));
            final breed = species == 'cavy' ? 'Cavy' : 'Czech Frosty';
            final data = SweepstakesReportData(
              showId: 'show',
              breedName: breed,
              scope: scope,
              showLetter: letter,
              ruleSource: 'NO_RESULTS',
              verificationStatus: 'VERIFIED',
              engineType: 'NO_RESULTS',
              rows: [],
              species: species,
              breedSanctionNumber: 'SANCTION-$scope-$letter',
              breedClubName: 'Synthetic Breed Club',
              hostClubName: 'Synthetic Host Club',
              showLocation: 'Test City, IN',
              secretaryName: 'Test Secretary',
              secretaryEmail: 'secretary@example.test',
              secretaryPhone: '555-123-4567',
            );
            final request = ReportRequest(
              showId: 'show',
              reportName: 'sweepstakes_report',
              finalizeRunId: 'fixture',
              showName: 'Synthetic Fall Show',
              showDate: '2026-10-01',
            );
            final assets = FileSystemReportAssetLoader(
              Directory('../../assets'),
            );
            final sweeps = await SweepstakesReportPdf(
              assets: assets,
            ).buildFile(data, request);
            final detail = await BreedResultsDetailReportPdf(assets: assets)
                .buildFile(
                  BreedResultsDetailReportData(
                    showId: 'show',
                    breedName: breed,
                    species: species,
                    scope: scope,
                    showLetter: letter,
                    judgeName: '',
                    arbaSanction: 'ARBA-$letter',
                    breedSanctionNumber: 'SANCTION-$scope-$letter',
                    breedClubName: 'Synthetic Breed Club',
                    hostClubName: 'Synthetic Host Club',
                    showLocation: 'Test City, IN',
                    secretaryName: 'Test Secretary',
                    secretaryEmail: 'secretary@example.test',
                    secretaryPhone: '555-123-4567',
                    breedAwards: [],
                    varieties: [],
                    sections: [
                      BreedResultsDetailSection(
                        showLetter: letter,
                        judgeName: '',
                        breedAwards: [],
                        varieties: [],
                        noResultsFound: true,
                      ),
                    ],
                  ),
                  request.copyWith(reportName: 'breed_results_detail_report'),
                );
            for (final (name, file) in [
              ('sweepstakes', sweeps),
              ('detail', detail),
            ]) {
              final pdf = File('${dir.path}/$name.pdf');
              await pdf.writeAsBytes(file.bytes);
              final extracted = await Process.run('pdftotext', [
                '-layout',
                pdf.path,
                '-',
              ]);
              expect(extracted.exitCode, 0);
              final text = extracted.stdout.toString();
              for (final value in [
                'None shown.',
                breed,
                'Synthetic Fall Show',
                '2026-10-01',
                'Synthetic Breed Club',
                'Synthetic Host Club',
                'Test City, IN',
                'Test Secretary',
                'secretary@example.test',
                '555-123-4567',
                'SANCTION-$scope-$letter',
              ]) {
                expect(text, contains(value), reason: name);
              }
              expect(
                text.split('\f').where((x) => x.trim().isNotEmpty),
                hasLength(1),
              );
              if (name == 'detail') expect(text, contains('ARBA-$letter'));
            }
          },
        );
      }
    }
  }
  test(
    'empty scoring results never claim none shown when animals competed',
    () {
      final rabbit = SweepstakesReportData(
        showId: 'show',
        breedName: 'Czech Frosty',
        scope: 'OPEN',
        showLetter: 'A',
        ruleSource: 'NO_RESULTS',
        verificationStatus: 'VERIFIED',
        engineType: 'NO_RESULTS',
        rows: [],
        species: 'rabbit',
      );
      expect(
        sweepstakesNoResultsMessage(rabbit, shownEntryCount: 2),
        contains('2 rabbits were shown'),
      );
      expect(
        sweepstakesNoResultsMessage(rabbit, shownEntryCount: 2),
        isNot(contains('None shown')),
      );
      expect(breedDetailNoResultsMessage(2), contains('2 animals were shown'));
      expect(breedDetailNoResultsMessage(2), isNot(contains('None shown')));
    },
  );
}
