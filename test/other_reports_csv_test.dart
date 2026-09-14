import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/csv/report_csv.dart';
import 'package:ringmaster_show/screens/admin/closeout/csv/builders/other_reports_csv.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_mailing_labels_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_awards_overview_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/payback_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/ribbon_payout_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/judge/judge_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/exhibitor_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/judge/breed_judged_totals_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/report_artifact_summary.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/other_reports_csv_service.dart';

ReportArtifactSummary artifact({
  String report = 'judge_report',
  List<String> sections = const ['s2'],
}) => ReportArtifactSummary(
  id: 'a1',
  showId: 'show1',
  finalizeRunId: 'run1',
  reportName: report,
  artifactStatus: 'generated',
  isCurrent: true,
  sectionIds: sections,
  metadata: {'scope': 'YOUTH', 'scope_label': 'Youth B', 'species': 'rabbit'},
);

void main() {
  test(
    'CSV preserves Unicode, commas, quotes, newlines and neutralizes formulas',
    () {
      final file = const ReportCsvTable(
        ['Name', 'Address', 'Amount'],
        [
          ['Zoë, "Jr"', 'One Street\nTown, IN', -12.25],
          [' =HYPERLINK("bad")', '+123456', 4],
        ],
      ).toFile(title: 'Contact / Report', showName: 'Test Show');
      final csv = utf8.decode(file.bytes);
      expect(file.bytes.take(3), [0xef, 0xbb, 0xbf]);
      expect(csv, startsWith('"Show","Name","Address","Amount"\r\n'));
      expect(csv, contains('"Zoë, ""Jr""","One Street\nTown, IN","-12.25"'));
      expect(csv, contains('"\' =HYPERLINK(""bad"")","\'+123456","4"'));
      expect(file.fileName, 'Contact - Report - Test Show.csv');
      expect(file.metadata['row_count'], 2);
    },
  );

  test('empty results still have a useful header and malformed rows fail', () {
    expect(
      utf8.decode(
        const ReportCsvTable([
          'Exhibitor',
        ], []).toFile(title: 'Report', showName: 'Show').bytes,
      ),
      '"Show","Exhibitor"\r\n',
    );
    expect(
      () => const ReportCsvTable(
        ['One'],
        [
          ['a', 'b'],
        ],
      ).toFile(title: 'Report', showName: 'Show'),
      throwsStateError,
    );
  });

  test('uses exact stored scope, including national show eligibility', () {
    final request = otherReportCsvRequest(
      showId: 'show1',
      reportName: 'judge_report',
      show: {
        'name': 'Show',
        'is_national_show': true,
        'national_show_section_id': 's1',
      },
      enabledSectionIds: ['s1', 's2'],
      artifact: artifact(),
    );
    expect(request.sectionIds, ['s2']);
    expect(request.scope, 'YOUTH');
    expect(request.species, 'rabbit');
    expect(request.isNationalShow, false);
    expect(
      () => otherReportCsvRequest(
        showId: 'show1',
        reportName: 'judge_report',
        show: {},
        enabledSectionIds: ['s1', 's2'],
        artifact: artifact(sections: []),
      ),
      throwsStateError,
    );
    expect(
      otherReportCsvRequest(
        showId: 'show1',
        reportName: 'judge_report',
        show: {},
        enabledSectionIds: ['s1', 's2'],
      ).sectionIds,
      ['s1', 's2'],
    );
  });

  test('label contents, eligibility and numeric sorting match PDF options', () {
    const labels = [
      ExhibitorMailingLabel(
        id: '1',
        name: 'Zoë Z',
        lastName: 'Z',
        number: '20',
        address: ['One', 'Town'],
      ),
      ExhibitorMailingLabel(
        id: '2',
        name: 'Amy A',
        lastName: 'A',
        number: '003',
        address: [],
        hasMailingAddress: false,
      ),
      ExhibitorMailingLabel(
        id: '3',
        name: 'Beth B',
        lastName: 'B',
        number: '',
        address: ['Two', 'Town'],
      ),
    ];
    final builder = OtherReportsCsvBuilder();
    final addresses = builder.build(labels);
    expect(addresses.rows, [
      ['Beth B', 'Two\nTown'],
      ['Zoë Z', 'One\nTown'],
    ]);
    final numbers = builder.build(
      labels,
      labelMode: MailingLabelMode.exhibitorNumber,
      labelSort: MailingLabelSort.exhibitorNumber,
    );
    expect(numbers.rows, [
      ['Amy A', '003'],
      ['Zoë Z', '20'],
    ]);
  });

  test(
    'breed totals use section detail without duplicating overall totals',
    () {
      final data = BreedJudgedTotalsReportData(
        show: const BreedJudgedTotalsReportShowInfo(
          showId: 'show1',
          showName: 'Show',
        ),
        generatedAt: DateTime(2026),
        scopeLabel: 'All',
        breedRows: const [
          BreedJudgedTotalsReportRow(
            breed: 'Dutch',
            species: 'Rabbit',
            totalJudged: 12,
          ),
        ],
        furRows: const [],
        showBreakdowns: const [
          BreedJudgedTotalsShowBreakdown(
            label: 'Open A',
            breedRows: [
              BreedJudgedTotalsReportRow(
                breed: 'Dutch',
                species: 'Rabbit',
                totalJudged: 5,
              ),
            ],
            furRows: [],
          ),
          BreedJudgedTotalsShowBreakdown(
            label: 'Youth B',
            breedRows: [
              BreedJudgedTotalsReportRow(
                breed: 'Dutch',
                species: 'Rabbit',
                totalJudged: 7,
              ),
            ],
            furRows: [],
          ),
        ],
      );
      final table = OtherReportsCsvBuilder().build(data);
      expect(table.rows.length, 2);
      expect(table.rows.map((r) => r.last), [5, 7]);
    },
  );

  test('print pack CSV keeps BBOS results without inventing a leg', () {
    final pack = ExhibitorPrintPackCsvData();
    pack.addReport(
      ExhibitorReportData(
        exhibitorName: 'Exhibitor',
        exhibitorAddress: 'Address',
        exhibitorCityStateZip: 'City',
        showName: 'Show',
        showDate: '2026-09-14',
        showLocation: 'Here',
        secretaryName: '',
        secretaryEmail: '',
        entries: [
          ExhibitorEntryRow(
            showSection: 'Open A',
            showSectionSort: 0,
            tattoo: 'A1',
            breed: 'Dutch',
            variety: 'Black',
            className: 'Senior',
            sex: 'Buck',
            placing: '1',
            classCount: 2,
            exhibitorCount: 2,
            awardsText: 'BOS, BBOS',
            judgeName: 'Judge',
            earnedLeg: false,
            specialtyPoints: 0,
            totalPoints: 0,
          ),
        ],
      ),
      number: '1096',
      scope: 'Open',
      species: 'rabbit',
    );
    final table = OtherReportsCsvBuilder().build(pack);
    final row = Map.fromIterables(table.headers, table.rows.single);
    expect(row['Record Type'], 'Result');
    expect(row['Awards / Win'], 'BOS, BBOS');
    expect(row['Earned Leg'], 'No');
    expect(row['Certificate ID'], '');
    expect(
      () => table.toFile(title: 'Pack', showName: 'Show'),
      returnsNormally,
    );
  });

  test('awards, judges, ribbons and paybacks retain their report details', () {
    final builder = OtherReportsCsvBuilder();
    final awards = builder.build(
      const BreedAwardsOverviewData('Show', [
        BreedAwardOverviewRow(
          sectionId: 's1',
          sectionLabel: 'Open A',
          species: 'rabbit',
          award: 'BOS',
          tattoo: '01',
          coop: '12',
          breed: 'Dutch',
          variety: 'Black',
          className: 'Senior',
          sex: 'Buck',
          exhibitor: 'Alex',
        ),
      ]),
    );
    expect(awards.rows.single, [
      'Open A',
      'rabbit',
      'BOS',
      '01',
      '12',
      'Dutch',
      'Black',
      'Senior',
      'Buck',
      'Alex',
    ]);
    final judges = builder.build(
      JudgeReportData(
        show: JudgeReportShowInfo(showId: 'show1', showName: 'Show'),
        generatedAt: DateTime(2026),
        judges: [
          JudgeReportJudge(
            judgeId: 'j1',
            displayName: 'Judge',
            arbaNumber: '123',
            rows: [
              JudgeReportRow(
                entryId: 'e1',
                sectionLabel: 'Open A',
                species: 'rabbit',
                breed: 'Dutch',
                variety: 'Black',
                className: 'Senior',
                sex: 'Buck',
                tattoo: '01',
                exhibitorName: 'Alex',
                placement: 1,
                awards: ['BOB', 'BIS'],
              ),
            ],
          ),
        ],
      ),
    );
    expect(judges.rows.single[judges.headers.indexOf('Awards')], 'BOB, BIS');
    const ribbon = RibbonPayoutRow(
      exhibitorNumber: '1096',
      exhibitorName: 'Alex',
      first: 2,
      second: 1,
      third: 0,
      fourth: 0,
      fifth: 0,
    );
    final ribbons = builder.build(
      const RibbonPayoutReportData(
        showId: 'show1',
        showName: 'Show',
        eventName: '',
        sponsoringClub: '',
        eventSecretary: '',
        eventSecretaryEmail: '',
        sponsoringSuperintendent: '',
        classification: 'All',
        showLetter: '',
        type: '',
        specialty: '',
        arbaSanction: '',
        rows: [ribbon],
        sections: [
          RibbonPayoutSectionData(
            sponsoringClub: '',
            classification: 'Open',
            showLetter: 'A',
            type: '',
            specialty: '',
            arbaSanction: '',
            rows: [ribbon],
          ),
        ],
      ),
    );
    expect(ribbons.rows, [
      ['Open', 'A', '1096', 'Alex', 2, 1, 0, 0, 0],
    ]);
    final paybacks = builder.build(
      PaybackReportData(
        showId: 'show1',
        showName: 'Show',
        showDate: null,
        showLocation: null,
        grandTotalCents: 1250,
        exhibitors: [
          PaybackExhibitorSummary(
            exhibitorId: 'ex1',
            exhibitorNumber: '1096',
            exhibitorName: 'Alex',
            mailingAddress: 'One\nTown',
            totalCents: 1250,
            rows: [
              PaybackBreakdownRow.fromJson({
                'section_label': 'Open A',
                'source_type': 'class_placement',
                'award_label': '1st',
                'entry_id': 'e1',
                'breed_name': 'Dutch',
                'tattoo': '01',
                'amount_cents': 1250,
                'eligible_count': 5,
                'placement': 1,
              }),
            ],
          ),
        ],
      ),
    );
    expect(paybacks.rows.single[paybacks.headers.indexOf('Amount')], 12.5);
    for (final table in [awards, judges, ribbons, paybacks]) {
      expect(
        () => table.toFile(title: 'Report', showName: 'Show'),
        returnsNormally,
      );
    }
  });

  group('authenticated loader integration', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    var failEntries = false;
    var withBalances = false;
    setUp(() {
      failEntries = false;
      withBalances = false;
      requests = [];
      client = SupabaseClient(
        'http://fixture.invalid',
        'anon',
        httpClient: MockClient((req) async {
          requests.add(req);
          final path = req.url.path;
          final query = req.url.queryParameters;
          Object value = [];
          if (path.endsWith('/shows')) {
            value = {'id': 'show1', 'name': 'Show', 'is_national_show': false};
          } else if (path.endsWith('/show_sections')) {
            value = [
              for (final id in ['s1', 's2'])
                {
                  'id': id,
                  'kind': 'open',
                  'letter': id == 's1' ? 'A' : 'B',
                  'sort_order': 1,
                },
            ];
          } else if (path.endsWith('/entries')) {
            if (failEntries) {
              return http.Response(
                '{"message":"permission denied","code":"42501"}',
                403,
                request: req,
              );
            }
            if ((query['offset'] ?? '0') == '0') {
              value = [
                for (final id in ['e1', 'e2'])
                  {
                    'id': id,
                    'exhibitor_id': 'ex1',
                    'exhibitors': {
                      'display_name': 'Zoë, Hunter',
                      'last_name': 'Hunter',
                      'first_name': 'Zoë',
                      'exhibitor_number': '1096',
                      'email': 'zoe@example.com',
                      'address_line1': 'One Street',
                      'city': 'Town',
                      'zip': '01234',
                    },
                  },
              ];
            }
          } else if (path.endsWith('report_show_exhibitor_balances_scoped') &&
              withBalances &&
              (query['offset'] ?? '0') == '0') {
            value = [
              {
                'exhibitor_id': 'ex1',
                'exhibitor_name': 'Zoë',
                'entry_count': 2,
                'paid_online_cents': 2000,
                'paid_manual_cents': 500,
                'refunded_cents': 200,
                'calculated_total_cents': 3050,
                'balance_due_cents': 750,
                'show_fee_subtotal_cents': 750,
                'currency': 'USD',
              },
            ];
          } else if (path.endsWith('can_access_exhibitor_print_pack')) {
            value = false;
          }
          return http.Response(
            jsonEncode(value),
            200,
            request: req,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    });
    tearDown(() => client.dispose());

    for (final report in [
      'entered_exhibitors_contact_report',
      'entered_exhibitors_list_report',
      'exhibitor_mailing_labels',
    ]) {
      test(
        '$report paginates, deduplicates and uses selected sections without feature gating',
        () async {
          final file = await OtherReportsCsvService(client).build(
            showId: 'show1',
            reportName: report,
            title: 'Report',
            artifact: artifact(report: report),
          );
          expect(file.metadata['row_count'], 1);
          expect(utf8.decode(file.bytes), contains('Zoë, Hunter'));
          final reads = requests
              .where((r) => r.url.path.endsWith('/entries'))
              .toList();
          expect(reads.length, 2);
          expect(
            reads.every((r) => r.url.queryParameters['show_id'] == 'eq.show1'),
            true,
          );
          expect(
            reads.map(
              (r) => r.url.queryParameters['section_id']?.replaceAll('"', ''),
            ),
            everyElement('in.(s2)'),
          );
          expect(
            requests.any((r) => r.url.path.contains('can_configure')),
            false,
          );
          expect(requests.every((r) => r.method == 'GET'), true);
        },
      );
    }

    for (final report in ['paid_exhibitor_report', 'unpaid_balances_report']) {
      test(
        '$report exports charges, net paid and balance in dollars',
        () async {
          withBalances = true;
          final file = await OtherReportsCsvService(client).build(
            showId: 'show1',
            reportName: report,
            title: 'Report',
            artifact: artifact(report: report),
          );
          expect(file.metadata['row_count'], 1);
          expect(
            utf8.decode(file.bytes),
            contains('"30.5","20.0","5.0","2.0","23.0","7.5","USD"'),
          );
          final body = jsonDecode(
            requests
                .firstWhere(
                  (r) => r.url.path.endsWith(
                    'report_show_exhibitor_balances_scoped',
                  ),
                )
                .body,
          );
          expect(
            body['p_section_ids'],
            report == 'unpaid_balances_report' ? ['s1', 's2'] : ['s2'],
          );
        },
      );
    }

    for (final report in [
      'breed_awards_overview',
      'breed_judged_totals_report',
      'judge_report',
      'payback_report',
      'ribbon_payout_report',
    ]) {
      test('$report loads through the CSV service', () async {
        final file = await OtherReportsCsvService(
          client,
        ).build(showId: 'show1', reportName: report, title: report);
        expect(file.fileName, endsWith('.csv'));
        expect(file.metadata['row_count'], 0);
      });
    }

    test(
      'permission failures do not turn into empty successful exports',
      () async {
        failEntries = true;
        await expectLater(
          OtherReportsCsvService(client).build(
            showId: 'show1',
            reportName: 'entered_exhibitors_contact_report',
            title: 'Contacts',
          ),
          throwsA(isA<PostgrestException>()),
        );
      },
    );
    test('print pack retains its existing access check', () async {
      await expectLater(
        OtherReportsCsvService(client).build(
          showId: 'show1',
          reportName: 'exhibitor_print_pack',
          title: 'Pack',
        ),
        throwsStateError,
      );
      expect(
        requests.any((r) => r.url.path.endsWith('/show_report_artifacts')),
        false,
      );
    });
    test('cross-show artifact rejected before any network request', () async {
      await expectLater(
        OtherReportsCsvService(client).build(
          showId: 'other',
          reportName: 'judge_report',
          title: 'Judge',
          artifact: artifact(),
        ),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });
  });
}
