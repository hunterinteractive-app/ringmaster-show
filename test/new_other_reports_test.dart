import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_awards_overview_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_mailing_labels_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_awards_overview_pdf.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/exhibitor_mailing_labels_pdf.dart';

Map<String, dynamic> award(
  String code, {
  String id = 'entry',
  String kind = 'open',
  bool scratched = false,
}) => {
  'award_code': code,
  'entry_id': id,
  'entries': {
    'id': id,
    'animal_id': 'animal',
    'section_id': kind,
    'species': 'rabbit',
    'tattoo': 'T123',
    'breed': 'Mini Rex',
    'variety': 'Broken',
    'class_name': 'Senior',
    'sex': 'Doe',
    'is_shown': true,
    'scratched_at': scratched ? '2026-01-01' : null,
    'show_sections': {
      'id': kind,
      'kind': kind,
      'letter': 'A',
      'sort_order': kind == 'open' ? 1 : 2,
    },
    'exhibitors': {'first_name': 'Emmaline', 'last_name': 'Gilson'},
  },
};

void main() {
  test(
    'award rows retain each requested win, dedupe aliases, and omit scratched/unrequested awards',
    () {
      final rows = buildBreedAwardOverviewRows(
        [
          award('BOB'),
          award('BEST OF BREED'),
          award('BOSB'),
          award('BOV'),
          award('BOSV'),
          award('BOG'),
          award('BOSG'),
          award('BIS'),
          award('BOB', id: 'scratched', scratched: true),
        ],
        [
          {'animal_id': 'animal', 'scope': 'open', 'coop_number': '12'},
        ],
        combinedCoops: false,
      );
      expect(rows.map((r) => r.award), [
        'BOB',
        'BOS',
        'BOV',
        'BOSV',
        'BOG',
        'BOSG',
      ]);
      expect(
        rows.every((r) => r.coop == '12' && r.exhibitor == 'Emmaline Gilson'),
        isTrue,
      );
    },
  );
  test(
    'coop assignment respects combined or separate Open/Youth numbering',
    () {
      final awards = [
        award('BOB'),
        award('BOB', id: 'youth-entry', kind: 'youth'),
      ];
      final coops = [
        {'animal_id': 'animal', 'scope': 'open', 'coop_number': '10'},
        {'animal_id': 'animal', 'scope': 'youth', 'coop_number': '20'},
        {'animal_id': 'animal', 'scope': 'all', 'coop_number': '30'},
      ];
      expect(
        buildBreedAwardOverviewRows(
          awards,
          coops,
          combinedCoops: false,
        ).map((r) => r.coop),
        ['10', '20'],
      );
      expect(
        buildBreedAwardOverviewRows(
          awards,
          coops,
          combinedCoops: true,
        ).map((r) => r.coop),
        ['30', '30'],
      );
      expect(
        buildBreedAwardOverviewRows(
          awards,
          [],
          combinedCoops: false,
        ).first.coop,
        '',
      );
    },
  );
  test('labels deduplicate exhibitors and preserve address lines', () {
    final entry = {
      'exhibitor_id': 'person',
      'exhibitors': {
        'first_name': 'Amy',
        'last_name': 'Brown',
        'exhibitor_number': '10',
        'address_line1': '123 Main St',
        'address_line2': 'Apt 4',
        'city': 'Indianapolis',
        'state': 'IN',
        'zip': '46201',
      },
    };
    final rows = buildExhibitorMailingLabels([entry, entry]);
    expect(rows.length, 1);
    expect(rows.first.name, 'Amy Brown');
    expect(rows.first.address, [
      '123 Main St',
      'Apt 4',
      'Indianapolis, IN 46201',
    ]);
  });
  test('label sort uses last name or numeric exhibitor number', () {
    const rows = [
      ExhibitorMailingLabel(
        id: 'a',
        name: 'Amy Zane',
        lastName: 'Zane',
        number: '2',
        address: [],
      ),
      ExhibitorMailingLabel(
        id: 'b',
        name: 'Zoe Adams',
        lastName: 'Adams',
        number: '10',
        address: [],
      ),
    ];
    expect(
      sortExhibitorMailingLabels(rows, MailingLabelSort.lastName).first.id,
      'b',
    );
    expect(
      sortExhibitorMailingLabels(
        rows,
        MailingLabelSort.exhibitorNumber,
      ).first.id,
      'a',
    );
  });
  test('render award overview and both 31-label print layouts', () async {
    final assets = FileSystemReportAssetLoader(Directory('assets'));
    final request = ReportRequest(
      showId: 'sample',
      reportName: 'sample',
      finalizeRunId: 'operational',
      showName: 'Sample Two-Day Show',
    );
    final directory = Directory('tmp/pdfs/new-reports')
      ..createSync(recursive: true);
    final awards = [
      for (var i = 0; i < 90; i++)
        award(
          ['BOB', 'BOSB', 'BOV', 'BOSV', 'BOG', 'BOSG'][i % 6],
          id: 'entry$i',
          kind: i < 60 ? 'open' : 'youth',
        ),
    ];
    final overview = await BreedAwardsOverviewPdf(assets: assets).buildFile(
      BreedAwardsOverviewData(
        'Sample Two-Day Show',
        buildBreedAwardOverviewRows(awards, [], combinedCoops: false),
      ),
      request,
    );
    await File(
      '${directory.path}/breed-awards-overview.pdf',
    ).writeAsBytes(overview.bytes);
    final labels = [
      for (var i = 1; i <= 31; i++)
        ExhibitorMailingLabel(
          id: '$i',
          name: i == 1
              ? 'Alexandra and Christopher Montgomery-Sutherland'
              : 'Exhibitor $i Sample',
          lastName: 'Sample',
          number: '$i',
          address: [
            '123 Long Meadow Drive',
            'Apartment 456',
            'Indianapolis, IN 46201',
          ],
        ),
      const ExhibitorMailingLabel(
        id: 'missing',
        name: 'Missing Address',
        lastName: 'Address',
        number: '',
        address: [],
        hasMailingAddress: false,
      ),
    ];
    for (final mode in MailingLabelMode.values) {
      final file = await ExhibitorMailingLabelsPdf(assets: assets).buildFile(
        labels,
        request,
        mode: mode,
        sort: MailingLabelSort.exhibitorNumber,
      );
      expect(file.metadata['label_count'], 31);
      expect(file.metadata['skipped_count'], 1);
      await File(
        '${directory.path}/labels-${mode.name}.pdf',
      ).writeAsBytes(file.bytes);
    }
  });
}
