import 'dart:io';

import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/arba/arba_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/arba_report_pdf.dart';
import 'package:test/test.dart';

void main() {
  for (final count in [0, 12, 13, 110]) {
    test(
      '$count judges are printed once with automatic continuation',
      () async {
        final directory = await Directory.systemTemp.createTemp('arba-judges-');
        addTearDown(() => directory.delete(recursive: true));
        final builder = ArbaReportPdfBuilder(
          assets: FileSystemReportAssetLoader(Directory('../../assets')),
        );
        final data = _report(count);
        final file = await builder.buildFile(
          data,
          ReportRequest(
            showId: 'synthetic',
            reportName: 'arba_report',
            finalizeRunId: 'synthetic-finalize',
            scope: 'open',
            showLetter: 'A',
          ),
        );
        final pdf = File('${directory.path}/report.pdf');
        await pdf.writeAsBytes(file.bytes);
        final extraction = await Process.run('pdftotext', [
          '-layout',
          pdf.path,
          '-',
        ]);
        expect(extraction.exitCode, 0, reason: '${extraction.stderr}');
        final pages = (extraction.stdout as String).split('\f');
        if (pages.last.trim().isEmpty) pages.removeLast();

        expect(
          pages.length,
          count <= 12
              ? 1
              : count == 13
              ? 2
              : greaterThan(2),
        );
        final names = RegExp(r'Judge\d{3}');
        List<String> judges(String text) =>
            names.allMatches(text).map((m) => m[0]!).toList();
        final expected = List.generate(count, (i) => _judgeName(i + 1));
        expect(
          pages.first,
          contains('Was there an official protest filed at this show?'),
        );
        expect(
          pages.first,
          contains(
            'If so, has a report been filed with the ARBA office at this time?',
          ),
        );
        expect(judges(pages.first), expected.take(12).toList());
        expect(judges(pages.skip(1).join('\n')), expected.skip(12).toList());
        for (var i = 1; i <= count; i++) {
          expect(
            RegExp(
              'LICENSE-${i.toString().padLeft(3, '0')}\\b',
            ).allMatches(pages.join('\n')),
            hasLength(1),
          );
        }
        if (count > 12) {
          expect(pages.first, contains('ADDITIONAL JUDGES: SEE PAGE 2'));
          for (var page = 1; page < pages.length; page++) {
            expect(pages[page], contains('ARBA REPORT - ADDITIONAL JUDGES'));
            expect(pages[page], contains(data.sectionLabel));
            expect(pages[page], contains(data.sanctionNumber));
            expect(
              pages[page],
              contains('Page ${page + 1} of ${pages.length}'),
            );
            expect(
              pages[page],
              isNot(contains('Number of Rabbits Exhibited:')),
            );
            expect(pages[page], isNot(contains('BEST IN SHOW')));
          }
        } else {
          expect(pages.first, isNot(contains('SEE PAGE 2')));
        }

        if (count == 110 &&
            Platform.environment['ARBA_JUDGES_EXAMPLE'] != null) {
          final example = File(Platform.environment['ARBA_JUDGES_EXAMPLE']!);
          await example.parent.create(recursive: true);
          await example.writeAsBytes(file.bytes);
        }
      },
    );
  }
}

String _judgeName(int number) => 'Judge${number.toString().padLeft(3, '0')}';

ArbaReportData _report(int count) => ArbaReportData(
  showName: 'Synthetic National Convention',
  sectionId: 'synthetic-open-a',
  sectionLabel: 'Rabbit Open A',
  scope: 'open',
  showLetter: 'A',
  secretaryName: 'Synthetic Secretary',
  secretaryEmail: 'secretary@example.invalid',
  secretaryPhone: '317-555-0100',
  sanctionNumber: 'LOCAL-OPEN-ARBA',
  reportDate: DateTime(2026, 9, 11),
  rabbitsShown: 17337,
  caviesShown: 0,
  clubName: 'Synthetic Convention Club',
  showDate: DateTime(2026, 9, 10),
  showLocation: 'Local only',
  secretaryAddress: '1 Synthetic Lane, Localtown, IN 46000',
  superintendentName: 'Synthetic Superintendent',
  superintendentArbaNumber: 'LOCAL-SUPER',
  ribbonsReportsMailedAt: DateTime(2026, 9, 11),
  sweepstakesReportsFiledAt: DateTime(2026, 9, 11),
  judges: List.generate(
    count,
    (i) =>
        '${_judgeName(i + 1)} - LICENSE-${(i + 1).toString().padLeft(3, '0')}',
  ),
  troubleReceivingSanctions: 'No',
  troubleReceivingSanctionClubs: 'N/A',
  filedDate: DateTime(2026, 9, 11),
  signedBy: 'Synthetic Secretary',
  protestFiled: 'No',
  protestReportFiled: 'N/A',
  bisRabbitOwner: 'Synthetic Exhibitor',
  bisRabbitCityState: 'Localtown, IN',
  bisRabbitBreed: 'American',
  bisRabbitEarNumber: 'C00001',
  bisCavyOwner: 'No cavies shown',
  bisCavyCityState: '',
  bisCavyBreed: '',
  bisCavyEarNumber: '',
);
