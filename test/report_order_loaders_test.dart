import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/check_in_sheet_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/details_by_breed_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/judge_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_awards_overview_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/breed_results_detail_order.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/check_in_sheet_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/details_by_breed_report_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart';

const varieties = ['Lilac', 'Blue', 'Chocolate', 'Black'];
final expected = [
  for (final v in varieties)
    for (final age in ['Senior', 'Junior'])
      for (final sex in ['Buck', 'Doe']) '$v $age $sex',
];
final section = {
  'id': 'section',
  'kind': 'open',
  'letter': 'A',
  'sort_order': 1,
  'is_enabled': true,
};
List<Map<String, dynamic>> entryRows() => [
  for (final (rank, v) in varieties.indexed)
    for (final age in ['Junior', 'Senior'])
      for (final sex in ['Doe', 'Buck'])
        {
          'id': '$v $age $sex',
          'entry_id': '$v $age $sex',
          'section_id': 'section',
          'show_sections': section,
          'section_kind': 'open',
          'section_letter': 'A',
          'section_sort_order': 1,
          'species': 'rabbit',
          'breed': 'Tan',
          'breed_name': 'Tan',
          'variety': v,
          'variety_name': v,
          'variety_sort_order': rank + 1,
          'class_name': age,
          'sex': sex,
          'tattoo': '$v $age $sex',
          'exhibitor_id': 'exhibitor',
          'exhibitor_label': 'Ordering Tester',
          'exhibitor_name': 'Ordering Tester',
          'placement': 1,
          'is_shown': true,
          'is_disqualified': false,
          'is_fur': false,
          'judged_by_show_judge_id': 'judge',
        },
].reversed.toList();

SupabaseClient fixture({bool cavy = false}) => SupabaseClient(
  'http://fixture.invalid',
  'key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient((request) async {
    final name = request.url.pathSegments.last;
    final single = request.headers['Accept']?.contains('object') == true;
    Object? data = [];
    switch (name) {
      case 'shows':
        data = [
          {
            'id': 'show',
            'name': 'Ordering Test',
            'start_date': '2026-10-24',
            'coop_numbering_mode': 'separate',
          },
        ];
      case 'show_sections':
        data = [section];
      case 'get_show_wave_schedule':
        data = {'enabled': false, 'waves': [], 'breeds': []};
      case 'exhibitors':
        data = [
          {'id': 'exhibitor', 'display_name': 'Ordering Tester'},
        ];
      case 'report_checkin_entries':
      case 'report_results_entry_rows':
      case 'report_results_entry_rows_for_breed_detail':
        data = entryRows();
      case 'entries':
        data = [
          for (final row in entryRows())
            Map<String, dynamic>.from(row)..remove('variety_sort_order'),
        ];
      case 'breeds':
        data = [
          {'id': 'tan', 'name': 'Tan', 'species': 'rabbit'},
        ];
      case 'varieties':
        data = [
          for (final (i, v) in varieties.indexed)
            {'id': v, 'breed_id': 'tan', 'name': v, 'sort_order': i + 1},
        ];
      case 'show_judges':
        data = [
          {'id': 'judge', 'judge_id': 'judge', 'name': 'Test Judge'},
        ];
      case 'judges':
        data = [
          {'id': 'judge', 'name': 'Test Judge'},
        ];
      case 'entry_awards':
      case 'report_results_awards_for_breed_detail':
        data = [
          for (final row in entryRows().where(
            (r) => r['class_name'] == 'Senior' && r['sex'] == 'Buck',
          ))
            {
              'id': row['id'],
              'entry_id': row['id'],
              'award_code': 'BOV',
              'entries': row,
              'breed': 'Tan',
              'variety': row['variety'],
              'exhibitor_label': 'Ordering Tester',
            },
        ];
    }
    if (cavy &&
        (name == 'entry_awards' ||
            name == 'report_results_awards_for_breed_detail')) {
      data = [];
    }
    if (cavy &&
        data is List &&
        data.isNotEmpty &&
        data.first is Map &&
        (data.first as Map).containsKey('entry_id') &&
        name != 'entry_awards') {
      data = [
        for (final v in ['Agouti', 'Self'])
          for (final age in ['Senior', 'Intermediate', 'Junior'])
            for (final sex in ['Sow', 'Boar'])
              {
                ...entryRows().first,
                'id': '$v $age $sex',
                'entry_id': '$v $age $sex',
                'breed': 'Teddy Satin',
                'breed_name': 'Teddy Satin',
                'species': 'cavy',
                'variety': v,
                'variety_name': v,
                'class_name': age,
                'sex': sex,
                'tattoo': '$v $age $sex',
              },
      ];
    }
    if (data is List) {
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 1000;
      data = data.skip(offset).take(limit).toList();
      if (single) data = data.isEmpty ? null : data.first;
    }
    return http.Response(
      jsonEncode(data),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }),
);
ReportRequest request(String name) => ReportRequest(
  showId: 'show',
  reportName: name,
  finalizeRunId: 'run',
  sectionId: 'section',
  sectionIds: ['section'],
  scope: 'OPEN',
  showLetter: 'A',
  species: 'rabbit',
  breedName: 'Tan',
  exhibitorId: 'exhibitor',
  showName: 'Ordering Test',
);

void main() {
  test(
    'cavy detail keeps each variety separate and prints Junior through Senior',
    () async {
      final client = fixture(cavy: true);
      addTearDown(client.dispose);
      final req = ReportRequest(
        showId: 'show',
        reportName: 'breed_results_detail_report',
        finalizeRunId: 'run',
        scope: 'OPEN',
        showLetter: 'A',
        species: 'cavy',
        sectionIds: ['section'],
        showName: 'Cavy ordering test',
      );
      final data = await BreedResultsDetailReportLoader(
        CloseoutRepository(client),
      ).load(req);
      expect(data.varieties.map((v) => v.varietyName), [
        'Teddy Satin — Self',
        'Teddy Satin — Agouti',
      ]);
      expect(
        data.varieties
            .expand(cavyBreedResultsClassBlocks)
            .expand((b) => b.classSection.rows)
            .map((r) => r.animal),
        [
          for (final v in ['Self', 'Agouti'])
            for (final age in ['Junior', 'Intermediate', 'Senior'])
              for (final sex in ['Boar', 'Sow']) '$v $age $sex',
        ],
      );
      expect(
        data.varieties
            .expand(cavyBreedResultsClassBlocks)
            .every((b) => b.classSection.animalsJudged == 1),
        isTrue,
      );
      if (Platform.environment['REPORT_ORDER_OUTPUT'] case final String path) {
        final pdf = await BreedResultsDetailReportPdf(
          assets: FileSystemReportAssetLoader(Directory('assets')),
        ).buildFile(data, req);
        File('$path/cavy-club.pdf').writeAsBytesSync(pdf.bytes);
      }
    },
  );

  test(
    'check-in loader prints every variety before moving to the next',
    () async {
      final client = fixture();
      addTearDown(client.dispose);
      final data = await CheckInSheetReportLoader(
        client,
      ).load(request('checkin_sheet'));
      expect(data.entries.map((r) => r['tattoo']), expected);
      if (Platform.environment['REPORT_ORDER_OUTPUT'] case final String path) {
        final pdf = await CheckInSheetReportPdfBuilder(
          assets: FileSystemReportAssetLoader(Directory('assets')),
        ).buildFile(data, request('ordering'));
        File('$path/checkin.pdf').writeAsBytesSync(pdf.bytes);
      }
    },
  );
  test('state club details retain catalog order and placements', () async {
    final client = fixture();
    addTearDown(client.dispose);
    final data = await DetailsByBreedReportLoader(
      CloseoutRepository(client),
    ).load(request('details_by_breed'));
    expect(data.breeds.single.varieties.map((v) => v.varietyName), varieties);
    expect(
      data.breeds.single.varieties
          .expand((v) => v.classes)
          .expand((c) => c.placements)
          .map((p) => p.earNumber),
      expected,
    );
    expect(data.breeds.single.animalsShown, 16);
    if (Platform.environment['REPORT_ORDER_OUTPUT'] case final String path) {
      final pdf = await DetailsByBreedReportPdf(
        assets: FileSystemReportAssetLoader(Directory('assets')),
      ).buildFile(data, request('ordering'));
      File('$path/state-club.pdf').writeAsBytesSync(pdf.bytes);
    }
  });
  test(
    'breed club detail sections and awards both follow catalog order',
    () async {
      final client = fixture();
      addTearDown(client.dispose);
      final data = await BreedResultsDetailReportLoader(
        CloseoutRepository(client),
      ).load(request('breed_results_detail_report'));
      expect(data.varieties.map((v) => v.varietyName), varieties);
      expect(
        data.varieties
            .expand(rabbitBreedResultsClassBlocks)
            .expand((c) => c.classSection.rows)
            .map((r) => r.animal),
        expected,
      );
      final awards = [...data.breedAwards]
        ..sort(compareBreedResultsDetailAwards);
      expect(awards.map((a) => a.variety), varieties);
      if (Platform.environment['REPORT_ORDER_OUTPUT'] case final String path) {
        final pdf = await BreedResultsDetailReportPdf(
          assets: FileSystemReportAssetLoader(Directory('assets')),
        ).buildFile(data, request('ordering'));
        File('$path/breed-club.pdf').writeAsBytesSync(pdf.bytes);
      }
    },
  );
  test(
    'judge raw entry query hydrates catalog ranks before converting models',
    () async {
      final client = fixture();
      addTearDown(client.dispose);
      final data = await JudgeReportLoader(
        supabase: client,
      ).load(request('judge_report'));
      expect(data.judges.single.rows.map((r) => r.tattoo), expected);
    },
  );
  test('award overview uses catalog order within each award type', () async {
    final client = fixture();
    addTearDown(client.dispose);
    final data = await BreedAwardsOverviewLoader(
      client,
    ).load(request('breed_awards_overview'));
    expect(data.rows.map((r) => r.variety), varieties);
  });
}
