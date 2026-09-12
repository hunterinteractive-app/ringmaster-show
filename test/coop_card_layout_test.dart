import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/coop_cards/coop_cards_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/coop_cards_report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'four complete coop cards fit on a letter page',
    () async {
      final builder = await CoopCardsReportPdfBuilder.fromAssets();
      final data = CoopCardsReportData(
        showId: 'test',
        showName: 'A Long National Convention Name for Layout Verification',
        showDateLabel: 'September 10, 2026',
        showLocationLabel: 'Local',
        coopNumberingMode: 'separate',
        generatedAt: DateTime(2026),
        cards: List.generate(
          4,
          (i) => CoopCardRow(
            coopNumber: 'AB${12345 + i}',
            entryNumber: '${54321 + i}',
            scope: i.isEven ? 'open' : 'youth',
            species: i.isEven ? 'rabbit' : 'cavy',
            animalId: 'animal-$i',
            animalName: 'Sample Animal With A Long Name',
            tattoo: 'EAR${111 + i}',
            breed: 'American',
            variety: 'Black',
            groupName: '',
            className: 'Senior',
            sex: 'Buck',
            exhibitorId: 'exh-$i',
            exhibitorName: 'Sample Exhibitor With A Long Name',
            exhibitorCity: 'Town',
            exhibitorState: 'IN',
            exhibitorNumber: '${9876 + i}',
            showLetters: ['A'],
            sectionLabels: ['Open A'],
            classEntryCount: 1000,
            classExhibitorCount: 100,
          ),
        ),
      );
      final bytes = await builder.build(data);
      final file = File(
        Platform.environment['COOP_LAYOUT_PDF'] ??
            '${Directory.systemTemp.path}/ringmaster-coop-layout-test.pdf',
      );
      file.writeAsBytesSync(bytes);
      // Text extraction tests final layout output, including widgets silently
      // omitted by the PDF library when a fixed-height box overflows.
      final text = await Process.run('pdftotext', [file.path, '-']);
      expect(text.exitCode, 0);
      final content = text.stdout as String;
      for (var i = 0; i < 4; i++) {
        for (final value in [
          'AB${12345 + i}',
          '${54321 + i}',
          'EAR${111 + i}',
          '${9876 + i}',
        ]) {
          expect(
            content,
            contains(value),
            reason: 'Missing printed identifier $value',
          );
        }
      }
      expect('COOP NO.'.allMatches(content), hasLength(4));
      expect('EXHIBITOR NO.'.allMatches(content), hasLength(4));
      expect('OPEN RABBIT'.allMatches(content), hasLength(2));
      expect('YOUTH CAVY'.allMatches(content), hasLength(2));
    },
    skip: Platform.environment['COOP_LAYOUT_PDF'] == null
        ? 'Requires opt-in Poppler layout verification'
        : false,
  );
}
