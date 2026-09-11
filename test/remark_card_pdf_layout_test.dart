import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ringmaster_show/screens/admin/print_packs/remark_cards_pdf.dart';

void main() {
  final hasPoppler = Process.runSync('which', ['pdftotext']).exitCode == 0;
  for (final runners in [true, false]) {
    test(
      'remark cards keep all fields on page with runners=$runners',
      () async {
        pw.Font font(String name) => pw.Font.ttf(
          ByteData.sublistView(
            File('assets/fonts/$name.ttf').readAsBytesSync(),
          ),
        );
        final theme = pw.ThemeData.withFont(
          base: font('NotoSans-Regular'),
          bold: font('NotoSans-Bold'),
        );
        final rows = List.generate(
          3,
          (i) => <String, dynamic>{
            'tattoo': 'EAR$i',
            'coop_number': 'COOP$i',
            'exhibitor_label': 'Test Exhibitor',
            'breed': 'American Fuzzy Lop',
            'variety': 'Broken',
            'class_name': 'Senior',
            'sex': 'Doe',
          },
        );
        final doc = RemarkCardsPdfBuilder(
          showName: 'North Country R&CBA Triple Fall Show',
          includeRunnerCards: runners,
        ).build(entries: rows, theme: theme, showDateLabel: '09/12/2026');
        final dir = Directory('tmp/pdfs')..createSync(recursive: true);
        final file = File(
          '${dir.path}/remark-cards-${runners ? 'runners' : 'plain'}.pdf',
        );
        await file.writeAsBytes(await doc.save());
        final result = await Process.run('pdftotext', [
          '-bbox',
          file.path,
          '-',
        ]);
        expect(result.exitCode, 0);
        final xml = result.stdout.toString();
        expect(RegExp('<page ').allMatches(xml).length, 2);
        expect(RegExp('>DETACHABLE<').allMatches(xml).length, runners ? 3 : 0);
        // Every tattoo must appear in the main card and (when enabled) its runner.
        for (var i = 0; i < 3; i++) {
          expect(RegExp('>EAR$i<').allMatches(xml).length, runners ? 2 : 1);
          expect(RegExp('>COOP$i<').allMatches(xml).length, runners ? 2 : 1);
        }
        for (final match in RegExp('yMax="([0-9.]+)"').allMatches(xml)) {
          expect(
            double.parse(match[1]!),
            lessThanOrEqualTo(592.1),
            reason: 'Text must remain inside the bottom page margin',
          );
        }
      },
      skip: hasPoppler ? false : 'Install Poppler to verify PDF text positions',
    );
  }
}
