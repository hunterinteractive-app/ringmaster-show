import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/exhibitor/exhibitor_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/exhibitor_report_pdf.dart';

void main() {
  final hasPoppler = Process.runSync('which', ['pdftotext']).exitCode == 0;
  for (final length in [6, 45]) {
    test('compact award populations render with $length entries', () async {
      final builder = await ExhibitorReportPdfBuilder.fromAssets(
        FileSystemReportAssetLoader(Directory('assets')),
      );
      final result = await builder.buildFile(
        ExhibitorReportData(
          exhibitorName: 'Sample Exhibitor',
          exhibitorAddress: '123 Example Lane',
          exhibitorCityStateZip: 'Example City, NY 12345',
          showName: 'Southern Adirondack Rabbit & Cavy Show',
          showDate: '11/14/2026',
          showLocation: 'Example Showgrounds',
          secretaryName: 'Sample Secretary',
          secretaryEmail: 'secretary@example.test',
          entries: List.generate(
            length,
            (i) => ExhibitorEntryRow(
              showSection: i.isEven ? 'Open A' : 'Open B',
              showSectionSort: 0,
              tattoo: 'EAR${i + 1}',
              breed: i % 3 == 0 ? 'American Fuzzy Lop' : 'Mini Rex',
              variety: i % 3 == 0 ? 'Broken' : 'Black',
              className: 'Senior',
              sex: 'Doe',
              placing: i % 3 == 0 ? '1' : '2',
              classCount: 7,
              exhibitorCount: 4,
              awardsText: i % 3 == 0
                  ? 'Best of Breed, BOG, Best of Variety'
                  : (i % 3 == 1 ? 'Best Opposite Sex of Variety' : ''),
              awardCounts: i % 3 == 0
                  ? const {
                      'Best of Breed': ExhibitorAwardCount(42, 12),
                      'BOG': ExhibitorAwardCount(18, 7),
                      'Best of Variety': ExhibitorAwardCount(12, 5),
                    }
                  : (i % 3 == 1
                        ? const {
                            'Best Opposite Sex of Variety': ExhibitorAwardCount(
                              7,
                              4,
                            ),
                          }
                        : const {}),
              judgeName: 'Sample Judge (#1234)',
              earnedLeg: i % 3 != 2,
              specialtyPoints: 0,
              totalPoints: 0,
            ),
          ),
        ),
        ReportRequest(
          showId: 'preview',
          reportName: 'Exhibitor Report',
          finalizeRunId: 'preview',
        ),
      );
      final dir = Directory('/tmp/ringmaster-jennifer-review')
        ..createSync(recursive: true);
      final file = File('${dir.path}/exhibitor-$length.pdf');
      await file.writeAsBytes(result.bytes);
      if (!hasPoppler) {
        expect(result.bytes.length, greaterThan(1000));
        return;
      }
      final extracted = await Process.run('pdftotext', [
        '-layout',
        file.path,
        '-',
      ]);
      expect(extracted.exitCode, 0);
      final text = extracted.stdout.toString();
      expect(text, contains('42 / 12'));
      expect(text, contains('18 / 7'));
      expect(text, contains('12 / 5'));
      expect(text, contains('EAR$length'));
      expect(text, contains('Counts do not indicate a leg.'));
      final pages = text.split('\f').where((p) => p.trim().isNotEmpty).toList();
      expect(pages.length, length == 6 ? 1 : greaterThan(1));
      for (final page in pages) {
        expect(page, contains('Awards'));
        expect(page, contains('Page'));
      }
    });
  }
}
