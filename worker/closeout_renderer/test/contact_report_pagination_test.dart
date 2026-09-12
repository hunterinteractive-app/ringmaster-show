import 'dart:io';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/reporting_core/rendering/render_isolate.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/entered_exhibitors_contact_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/entered_exhibitors_contact_report_pdf.dart';
import 'package:test/test.dart';

void main() {
  for (final count in [0, 101, 5056]) {
    test(
      '$count contacts retain all fields across table and page boundaries',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'contact-report-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final data = EnteredExhibitorsContactReportData(
          showId: 'synthetic',
          showName: 'Synthetic National',
          rows: [
            for (var i = count; i > 0; i--)
              EnteredExhibitorsContactRow(
                exhibitorName: 'Contact${i.toString().padLeft(5, '0')}',
                address:
                    'Address$i Long Synthetic Street\nUnit$i\nTest City, IN 46000',
                email: 'contact$i@example.invalid',
                phone: '555-${i.toString().padLeft(7, '0')}',
              ),
          ],
        );
        final timer = Stopwatch()..start();
        final result = await runInRenderIsolate(
          () =>
              EnteredExhibitorsContactReportPdf(
                assets: FileSystemReportAssetLoader(Directory('../../assets')),
              ).buildFile(
                data,
                ReportRequest(
                  showId: 'synthetic',
                  reportName: 'entered_exhibitors_contact_report',
                  finalizeRunId: 'fixture',
                ),
              ),
          timeout: const Duration(seconds: 120),
        );
        timer.stop();
        final file = File('${directory.path}/contact.pdf');
        await file.writeAsBytes(result.bytes);
        final extraction = await Process.run('pdftotext', [
          '-layout',
          file.path,
          '-',
        ]);
        expect(extraction.exitCode, 0);
        final text = extraction.stdout as String;
        final names = RegExp(
          r'Contact\d{5}',
        ).allMatches(text).map((m) => m[0]).toList();
        expect(names, [
          for (var i = 1; i <= count; i++)
            'Contact${i.toString().padLeft(5, '0')}',
        ]);
        for (final pattern in [
          r'Address\d+\b',
          r'Unit\d+\b',
          r'contact\d+@example.invalid',
          r'555-\d{7}',
        ]) {
          final fields = RegExp(
            pattern,
          ).allMatches(text).map((m) => m[0]!).toList();
          expect(fields, hasLength(count));
          expect(fields.toSet(), hasLength(count));
        }
        final pages = text
            .split('\f')
            .where((p) => p.trim().isNotEmpty)
            .toList();
        if (count == 0) expect(text, contains('No entered exhibitors.'));
        for (var i = 0; i < pages.length; i++) {
          expect(pages[i], contains('Page ${i + 1} of ${pages.length}'));
          expect(pages[i], contains('Synthetic National'));
          if (count > 0) expect(pages[i], contains('Exhibitor'));
        }
        if (count == 5056) {
          final output = Platform.environment['CONTACT_REPORT_EXAMPLE'];
          if (output != null) await File(output).writeAsBytes(result.bytes);
          print(
            '5056 contacts: ${timer.elapsedMilliseconds}ms, ${pages.length} pages, ${result.bytes.length} bytes',
          );
          expect(timer.elapsed, lessThan(const Duration(seconds: 60)));
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
