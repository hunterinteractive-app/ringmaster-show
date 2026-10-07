import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/show_addon_report_service.dart';
import 'package:ringmaster_show/services/show_addon_service.dart';

List<Map<String, dynamic>> fixture() => [
  {
    'id': 'purchase1',
    'kind': 'extra',
    'name': 'Banquet Ticket',
    'exhibitor_id': 'ex1',
    'exhibitor_number': 101,
    'exhibitor_name': 'Zoë, Hunter',
    'email': 'zoe@example.invalid',
    'quantity': 3,
    'unit_price_cents': 1250,
    'currency': 'usd',
    'payment_status': 'unpaid',
    'deleted_at': '2026-10-01',
  },
  {
    'id': 'purchase2',
    'kind': 'extra',
    'name': 'Parking Pass',
    'exhibitor_id': 'ex1',
    'exhibitor_number': 101,
    'exhibitor_name': 'Zoë, Hunter',
    'email': 'zoe@example.invalid',
    'quantity': 1,
    'unit_price_cents': 105,
    'currency': 'cad',
    'payment_status': 'paid',
  },
  {
    'id': 'contest1',
    'kind': 'contest',
    'name': 'Individual Judging',
    'exhibitor_id': 'ex2',
    'exhibitor_number': 102,
    'exhibitor_name': 'Alex Sample',
    'email': 'alex@example.invalid',
    'quantity': 1,
    'unit_price_cents': 500,
    'currency': 'usd',
    'payment_status': 'paid',
    'division': 'Junior',
    'checked_in': true,
    'approval_status': 'accepted',
    'animal_snapshot': {'species': 'rabbit', 'breed': 'Dutch', 'tattoo': 'A1'},
    'registration_data': {'session_name': 'Morning'},
    'answers': {'private_application': 'Not part of the roster'},
  },
  {
    'id': 'contest2',
    'kind': 'contest',
    'name': 'Team Judging',
    'exhibitor_id': 'ex2',
    'exhibitor_number': 102,
    'exhibitor_name': 'Alex Sample',
    'email': 'alex@example.invalid',
    'quantity': 1,
    'unit_price_cents': 0,
    'currency': 'usd',
    'payment_status': 'paid',
    'division': 'Senior',
    'checked_in': false,
    'approval_status': 'pending',
    'registration_data': {
      'category': 'Rabbit',
      'session_name': 'Afternoon',
      'animals': [
        {
          'source': 'provided',
          'role': 'Judging animal',
          'label': 'Organizer-provided animal',
        },
      ],
      'team': {
        'name': 'County Youth Team',
        'members': [
          {'name': 'Alex Sample'},
          {'name': 'Robin Sample', 'alternate': true},
        ],
      },
    },
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'purchases retain deleted products, quantities, exact money and separate currencies',
    () {
      final data = ShowAddonReportData(
        showName: 'Test Show',
        reportName: ShowAddonReportService.purchases,
        entries: fixture(),
      );
      final csv = utf8.decode(data.csv().bytes);
      expect(data.entries.length, 2);
      expect(data.quantity, 4);
      expect(data.exhibitorCount, 1);
      expect(data.totalsCents, {'USD': 3750, 'CAD': 105});
      expect(
        csv,
        contains(
          '"Banquet Ticket","101","Zoë, Hunter","zoe@example.invalid","3","12.50","37.50","USD","Unpaid"',
        ),
      );
      expect(csv, contains('"Parking Pass"'));
      expect(csv, isNot(contains('Individual Judging')));
      expect(data.csv().fileName, 'Add-On Purchases - Test Show.csv');
    },
  );
  test(
    'contest CSV identifies exhibitor, team, animal, division, session and statuses',
    () {
      final data = ShowAddonReportData(
        showName: 'Test Show',
        reportName: ShowAddonReportService.registrations,
        entries: fixture(),
      );
      final csv = utf8.decode(data.csv().bytes);
      expect(data.entries.length, 2);
      for (final value in [
        'Individual Judging',
        'Alex Sample',
        'alex@example.invalid',
        'Junior',
        'Morning',
        'rabbit / Dutch / A1',
        'County Youth Team',
        'Robin Sample (alternate)',
        'Judging animal: Organizer-provided animal',
        'Pending',
      ]) {
        expect(csv, contains(value), reason: value);
      }
      expect(csv, isNot(contains('Banquet Ticket')));
      expect(csv, isNot(contains('Not part of the roster')));
      expect(data.totalsCents, {'USD': 500});
    },
  );
  test(
    'empty CSV retains headers and user text cannot become spreadsheet formulas',
    () {
      final empty = ShowAddonReportData(
        showName: 'Show',
        reportName: ShowAddonReportService.purchases,
        entries: [],
      );
      expect(empty.csv().metadata['row_count'], 0);
      expect(
        utf8.decode(empty.csv().bytes),
        contains('"Exhibitor #","Exhibitor","Email"'),
      );
      final data = ShowAddonReportData(
        showName: 'Show',
        reportName: ShowAddonReportService.purchases,
        entries: [
          {
            ...fixture().first,
            'name': '=SUM(1,2)',
            'exhibitor_name': '"Quoted"\nName',
          },
        ],
      );
      final csv = utf8.decode(data.csv().bytes);
      expect(csv, contains('"\'=SUM(1,2)"'));
      expect(csv, contains('"""Quoted""\nName"'));
    },
  );
  test(
    'service reads current show-wide registrations on every request without closeout',
    () async {
      var reads = 0;
      final client = SupabaseClient(
        'http://fixture.invalid',
        'anon',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_show_addon_registrations');
          expect(jsonDecode(request.body), {
            'p_show_id': 'show1',
            'p_owner_id': null,
          });
          reads++;
          return http.Response(
            jsonEncode(fixture().take(reads).toList()),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final service = ShowAddonReportService(
        service: ShowAddonService(client: client),
      );
      for (var count = 1; count <= 2; count++) {
        final file = await service.build(
          showId: 'show1',
          showName: 'Test Show',
          reportName: ShowAddonReportService.purchases,
          asCsv: true,
        );
        expect(file.metadata['row_count'], count);
      }
      expect(reads, 2);
    },
  );
  test(
    'permission failures propagate without producing an empty success report',
    () async {
      final client = SupabaseClient(
        'http://fixture.invalid',
        'anon',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': '42501',
              'message': 'Show secretary permission is required.',
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        ShowAddonReportService(service: ShowAddonService(client: client)).build(
          showId: 'other-show',
          showName: 'Show',
          reportName: ShowAddonReportService.registrations,
          asCsv: true,
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
  test(
    'both PDFs paginate long names, Unicode and team rosters and handle empty shows',
    () async {
      final rows = [
        for (var i = 0; i < 40; i++)
          for (final original in fixture())
            {
              ...original,
              'id': '${original['id']}-$i',
              'exhibitor_id': '${original['exhibitor_id']}-$i',
              'exhibitor_number': 1000 + i,
              'exhibitor_name': 'Zoë Hunter Sample Exhibitor ${i + 1}',
              if (original['id'] == 'contest2')
                'registration_data': {
                  ...(original['registration_data'] as Map),
                  'team': {
                    'name': 'County Youth Team ${i + 1}',
                    'members': [
                      for (var m = 0; m < 8; m++)
                        {
                          'name': 'Contestant ${m + 1} of County Youth Team',
                          'alternate': m == 7,
                        },
                    ],
                  },
                },
            },
      ];
      for (final name in ShowAddonReportService.reportNames) {
        for (final empty in [false, true]) {
          final file = await ShowAddonReportData(
            showName: 'Sample Livestock Show',
            reportName: name,
            entries: empty ? [] : rows,
            generatedAt: DateTime.utc(2026, 10, 7, 4, 0),
          ).pdf();
          expect(String.fromCharCodes(file.bytes.take(5)), '%PDF-');
          final dir = Platform.environment['ADDON_REPORT_QA_DIR'];
          if (dir != null) {
            await File(
              '$dir/$name${empty ? '_empty' : ''}.pdf',
            ).writeAsBytes(file.bytes);
          }
        }
      }
    },
  );
}
